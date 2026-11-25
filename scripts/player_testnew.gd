extends CharacterBody3D

@export_group("Movement")
@export var move_speed: float = 7.0
@export var heavy_move_speed: float = 3.5
@export var acceleration: float = 20.0
@export var deceleration: float = 25.0
@export var gravity: float = 20.0

@export_group("Jump")
@export var min_jump_velocity: float = 4.5
@export var max_jump_velocity: float = 12.0
@export var jump_charge_time: float = 2.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.002
@export_range(1.0, 89.0, 1.0) var max_look_angle: float = 85.0

@export_group("Head Bob")
@export var head_bob_enabled: bool = true
@export var head_bob_frequency: float = 9.0
@export var head_bob_amount: float = 0.06
@export var head_bob_smoothing: float = 10.0

@export_group("Freecam")
@export var freecam_speed: float = 8.0
@export var freecam_fast_speed: float = 20.0
@export var freecam_sensitivity: float = 0.002

@export_group("Interactables")
@export var pickup_range: float = 3.0
@export var hold_distance: float = 2.0
@export var hold_smoothing: float = 15.0
@export var min_throw_force: float = 3.0
@export var max_throw_force: float = 25.0
@export var throw_charge_time: float = 2.0

@export_group("Lightning")
@export_range(5, 64, 1) var zap_segments: int = 20
@export var zap_jaggedness: float = 0.14
@export var zap_update_speed: float = 0.025
@export var zap_outer_width: float = 0.11
@export var zap_middle_width: float = 0.045
@export var zap_core_width: float = 0.012
@export var zap_glow: float = 8.0
@export_range(0, 16, 1) var zap_branch_count: int = 4

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var zap_point_0: Node3D = $Head/RightArm/ZapPoint0
@onready var zap_point_1: Node3D = $Head/LeftArm/ZapPoint1
@onready var jump_charge_bar: ProgressBar = $HUD/JumpChargeBar
@onready var throw_charge_bar: ProgressBar = $HUD/ThrowChargeBar
@onready var electricity_sound: AudioStreamPlayer3D = $Electricity

var camera_pitch: float = 0.0
var camera_rest_position: Vector3
var head_bob_time: float = 0.0
var head_bob_offset: Vector3 = Vector3.ZERO

var is_charging_jump: bool = false
var jump_charge: float = 0.0
var jump_release_pending: bool = false

var freecam_enabled: bool = false
var freecam_position: Vector3
var freecam_rotation: Vector3
var saved_player_rotation: float = 0.0
var saved_camera_pitch: float = 0.0

var held_object: RigidBody3D
var original_collision_layer: int = 0
var original_collision_mask: int = 0
var original_freeze_mode: int = RigidBody3D.FREEZE_MODE_STATIC
var original_freeze: bool = false

var is_charging_throw: bool = false
var throw_charge: float = 0.0

var zap_active: bool = false
var zap_update_timer: float = 0.0
var zap_mesh: ImmediateMesh
var zap_mesh_instance: MeshInstance3D
var zap_outer_material: StandardMaterial3D
var zap_middle_material: StandardMaterial3D
var zap_core_material: StandardMaterial3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera_rest_position = camera.position

	jump_charge_bar.min_value = 0.0
	jump_charge_bar.max_value = 100.0
	jump_charge_bar.value = 0.0
	jump_charge_bar.hide()

	throw_charge_bar.min_value = 0.0
	throw_charge_bar.max_value = 100.0
	throw_charge_bar.value = 0.0
	throw_charge_bar.hide()

	electricity_sound.stop()
	create_zap_effect()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		if freecam_enabled:
			freecam_rotation.y -= event.relative.x * freecam_sensitivity
			freecam_rotation.x = clampf(
				freecam_rotation.x - event.relative.y * freecam_sensitivity,
				deg_to_rad(-max_look_angle),
				deg_to_rad(max_look_angle)
			)
			camera.global_rotation = freecam_rotation
		else:
			rotate_y(-event.relative.x * mouse_sensitivity)
			camera_pitch = clampf(
				camera_pitch - event.relative.y * mouse_sensitivity,
				deg_to_rad(-max_look_angle),
				deg_to_rad(max_look_angle)
			)
			head.rotation.x = camera_pitch
		return

	if event.is_action_pressed("jump") and not event.is_echo():
		if not freecam_enabled and is_on_floor() and not is_charging_jump:
			is_charging_jump = true
			jump_charge = 0.0
		return

	if event.is_action_released("jump"):
		if is_charging_jump:
			jump_release_pending = true
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if freecam_enabled:
			return
		if event.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				start_throw_charge()
		elif is_charging_throw:
			throw_object()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = (
					Input.MOUSE_MODE_VISIBLE
					if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
					else Input.MOUSE_MODE_CAPTURED
				)
			KEY_F3:
				toggle_freecam()
			KEY_E:
				if not freecam_enabled:
					if is_instance_valid(held_object):
						drop_object()
					else:
						pickup_interactable()


func _physics_process(delta: float) -> void:
	if freecam_enabled:
		handle_freecam(delta)
		return

	handle_movement(delta)
	handle_jump(delta)
	handle_gravity(delta)
	handle_head_bob(delta)
	handle_held_object(delta)
	update_throw_charge_bar(delta)
	move_and_slide()


func get_current_move_speed() -> float:
	if is_instance_valid(held_object) and held_object.is_in_group("Heavy"):
		return heavy_move_speed
	return move_speed


func handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward"
	)
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_speed := get_current_move_speed()

	if direction.length_squared() > 0.0001:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)


func handle_jump(delta: float) -> void:
	if not is_on_floor():
		is_charging_jump = false
		jump_charge = 0.0
		jump_release_pending = false
		jump_charge_bar.hide()
		return

	if is_charging_jump:
		jump_charge = minf(jump_charge + delta, maxf(jump_charge_time, 0.0))
		jump_charge_bar.show()
		jump_charge_bar.value = get_jump_charge_percentage() * 100.0

	if jump_release_pending and is_charging_jump:
		velocity.y = lerpf(min_jump_velocity, max_jump_velocity, get_jump_charge_percentage())
		is_charging_jump = false
		jump_release_pending = false
		jump_charge = 0.0
		jump_charge_bar.hide()


func get_jump_charge_percentage() -> float:
	if jump_charge_time <= 0.0:
		return 1.0
	return clampf(jump_charge / jump_charge_time, 0.0, 1.0)


func handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= maxf(gravity, 0.0) * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func handle_head_bob(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var moving := horizontal_speed > 0.1 and is_on_floor()
	var target_offset := Vector3.ZERO

	if head_bob_enabled and moving:
		head_bob_time += delta * head_bob_frequency
		target_offset.y = sin(head_bob_time) * head_bob_amount
		target_offset.x = cos(head_bob_time * 0.5) * head_bob_amount * 0.5

	var blend := 1.0 - exp(-maxf(head_bob_smoothing, 0.0) * delta)
	head_bob_offset = head_bob_offset.lerp(target_offset, blend)
	camera.position = camera_rest_position + head_bob_offset


func pickup_interactable() -> void:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		camera.global_position - camera.global_transform.basis.z * maxf(pickup_range, 0.0)
	)
	query.exclude = [get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return

	var body := result.get("collider") as RigidBody3D
	if not is_instance_valid(body) or not body.is_in_group("Interactable"):
		return

	held_object = body
	original_collision_layer = body.collision_layer
	original_collision_mask = body.collision_mask
	original_freeze_mode = body.freeze_mode
	original_freeze = body.freeze

	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true

	start_zap()


func handle_held_object(delta: float) -> void:
	if not is_instance_valid(held_object):
		if held_object != null:
			clear_held_reference()
			stop_zap()
		return

	var target_position := camera.global_position - camera.global_transform.basis.z * hold_distance
	var blend := 1.0 - exp(-maxf(hold_smoothing, 0.0) * delta)
	held_object.global_position = held_object.global_position.lerp(target_position, blend)
	held_object.global_rotation = camera.global_rotation
	update_zap_effect(delta)


func restore_object_physics(object: RigidBody3D, force_unfreeze: bool = false) -> void:
	if not is_instance_valid(object):
		return
	object.collision_layer = original_collision_layer
	object.collision_mask = original_collision_mask
	object.freeze_mode = original_freeze_mode
	object.freeze = false if force_unfreeze else original_freeze


func clear_held_reference() -> void:
	held_object = null
	is_charging_throw = false
	throw_charge = 0.0
	throw_charge_bar.hide()
	throw_charge_bar.value = 0.0


func drop_object() -> void:
	if not is_instance_valid(held_object):
		clear_held_reference()
		stop_zap()
		return

	var object := held_object
	restore_object_physics(object)
	if not object.freeze:
		object.linear_velocity = Vector3.ZERO
		object.angular_velocity = Vector3.ZERO

	clear_held_reference()
	stop_zap()


func start_throw_charge() -> void:
	if not is_instance_valid(held_object) or is_charging_throw:
		return
	is_charging_throw = true
	throw_charge = 0.0
	throw_charge_bar.value = 0.0
	throw_charge_bar.show()


func update_throw_charge_bar(delta: float) -> void:
	if not is_charging_throw or not is_instance_valid(held_object):
		throw_charge_bar.hide()
		return
	throw_charge = minf(throw_charge + delta, maxf(throw_charge_time, 0.0))
	throw_charge_bar.value = get_throw_charge_percentage() * 100.0
	throw_charge_bar.show()


func get_throw_charge_percentage() -> float:
	if throw_charge_time <= 0.0:
		return 1.0
	return clampf(throw_charge / throw_charge_time, 0.0, 1.0)


func throw_object() -> void:
	if not is_charging_throw:
		return
	if not is_instance_valid(held_object):
		clear_held_reference()
		stop_zap()
		return

	var object := held_object
	var percentage := get_throw_charge_percentage()
	var force := lerpf(min_throw_force, max_throw_force, percentage)
	var direction := -camera.global_transform.basis.z.normalized()

	restore_object_physics(object, true)
	object.linear_velocity = Vector3.ZERO
	object.angular_velocity = Vector3.ZERO

	clear_held_reference()
	stop_zap()
	object.apply_central_impulse(direction * force)


func make_zap_material(color: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func create_zap_effect() -> void:
	zap_mesh = ImmediateMesh.new()
	zap_mesh_instance = MeshInstance3D.new()
	zap_mesh_instance.name = "LightningEffect"
	zap_mesh_instance.mesh = zap_mesh
	zap_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(zap_mesh_instance)

	zap_outer_material = make_zap_material(Color(0.02, 0.2, 1.0), zap_glow * 1.5, 0.25)
	zap_middle_material = make_zap_material(Color(0.0, 0.65, 1.0), zap_glow * 1.2, 0.65)
	zap_core_material = make_zap_material(Color(0.75, 0.95, 1.0), zap_glow, 1.0)
	zap_mesh_instance.hide()


func start_zap() -> void:
	if not is_instance_valid(zap_mesh_instance):
		return
	zap_active = true
	zap_update_timer = maxf(zap_update_speed, 0.001)
	zap_mesh_instance.show()
	if is_instance_valid(electricity_sound) and not electricity_sound.playing:
		electricity_sound.play()
	update_zap_effect(0.0)


func stop_zap() -> void:
	zap_active = false
	if is_instance_valid(zap_mesh):
		zap_mesh.clear_surfaces()
	if is_instance_valid(zap_mesh_instance):
		zap_mesh_instance.hide()
	if is_instance_valid(electricity_sound) and electricity_sound.playing:
		electricity_sound.stop()


func draw_zap_ribbon(points: Array[Vector3], side: Vector3, width: float, material: Material) -> void:
	if points.size() < 2:
		return

	var safe_width := maxf(width, 0.0)
	zap_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for i in range(points.size() - 1):
		var a := points[i] - side * safe_width
		var b := points[i] + side * safe_width
		var c := points[i + 1] - side * safe_width
		var d := points[i + 1] + side * safe_width
		zap_mesh.surface_add_vertex(a)
		zap_mesh.surface_add_vertex(b)
		zap_mesh.surface_add_vertex(c)
		zap_mesh.surface_add_vertex(b)
		zap_mesh.surface_add_vertex(d)
		zap_mesh.surface_add_vertex(c)
	zap_mesh.surface_end()


func generate_zap_points(
	start_position: Vector3,
	end_position: Vector3,
	segments: int,
	jaggedness: float,
	side: Vector3,
	perpendicular: Vector3
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var safe_segments := maxi(segments, 1)
	var safe_jaggedness := maxf(jaggedness, 0.0)

	for i in range(safe_segments + 1):
		var progress := float(i) / float(safe_segments)
		var point := start_position.lerp(end_position, progress)
		if i > 0 and i < safe_segments:
			var falloff := sin(progress * PI)
			point += side * randf_range(-safe_jaggedness, safe_jaggedness) * falloff
			point += perpendicular * randf_range(-safe_jaggedness, safe_jaggedness) * falloff
		points.append(point)
	return points


func update_zap_effect(delta: float) -> void:
	if not zap_active or not is_instance_valid(zap_mesh_instance):
		return

	zap_update_timer += delta
	var interval := maxf(zap_update_speed, 0.001)
	if zap_update_timer < interval:
		return
	zap_update_timer = 0.0

	if not is_instance_valid(zap_point_0) or not is_instance_valid(zap_point_1):
		return

	var start_position := zap_mesh_instance.to_local(zap_point_0.global_position)
	var end_position := zap_mesh_instance.to_local(zap_point_1.global_position)
	var direction := end_position - start_position
	if direction.length_squared() < 0.0001:
		return

	var direction_normalized := direction.normalized()
	var camera_right := (
		zap_mesh_instance.global_transform.basis.inverse() * camera.global_transform.basis.x
	).normalized()
	var side := camera_right - direction_normalized * camera_right.dot(direction_normalized)

	if side.length_squared() < 0.001:
		side = direction_normalized.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = direction_normalized.cross(Vector3.RIGHT)
	side = side.normalized()
	var perpendicular := direction_normalized.cross(side).normalized()

	var segments := maxi(zap_segments, 5)
	var main_points := generate_zap_points(
		start_position, end_position, segments, zap_jaggedness, side, perpendicular
	)

	zap_mesh.clear_surfaces()
	draw_zap_ribbon(main_points, side, zap_outer_width, zap_outer_material)
	draw_zap_ribbon(main_points, perpendicular, zap_middle_width, zap_middle_material)
	draw_zap_ribbon(main_points, side, zap_core_width, zap_core_material)

	# Branch indices are kept inside the main bolt, even at the minimum segment count.
	for branch_index in range(maxi(zap_branch_count, 0)):
		var start_index := randi_range(2, segments - 2)
		var branch_start := main_points[start_index]
		var branch_direction := (
			side * randf_range(-0.4, 0.4) + perpendicular * randf_range(0.6, 1.0)
		).normalized()
		var branch_end := branch_start + branch_direction * randf_range(0.15, 0.4)
		var branch_points := generate_zap_points(
			branch_start,
			branch_end,
			4,
			maxf(zap_jaggedness, 0.0) * 0.5,
			side,
			perpendicular
		)
		draw_zap_ribbon(branch_points, side, zap_core_width * 1.5, zap_middle_material)


func toggle_freecam() -> void:
	if not freecam_enabled:
		if is_instance_valid(held_object):
			drop_object()

		freecam_enabled = true
		saved_player_rotation = rotation.y
		saved_camera_pitch = camera_pitch
		freecam_position = camera.global_position
		freecam_rotation = camera.global_rotation

		is_charging_jump = false
		jump_release_pending = false
		jump_charge = 0.0
		jump_charge_bar.hide()
		is_charging_throw = false
		throw_charge = 0.0
		throw_charge_bar.hide()
		velocity = Vector3.ZERO
	else:
		freecam_enabled = false
		rotation.y = saved_player_rotation
		camera_pitch = saved_camera_pitch
		head.rotation.x = camera_pitch
		head_bob_offset = Vector3.ZERO
		camera.position = camera_rest_position
		camera.rotation = Vector3.ZERO


func handle_freecam(delta: float) -> void:
	var speed := freecam_fast_speed if Input.is_key_pressed(KEY_SHIFT) else freecam_speed
	var input_dir := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		input_dir.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_SPACE):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_CTRL):
		input_dir.y -= 1.0

	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
		freecam_position += Basis.from_euler(freecam_rotation) * input_dir * speed * delta

	camera.global_position = freecam_position
	camera.global_rotation = freecam_rotation


func _exit_tree() -> void:
	if is_instance_valid(held_object):
		restore_object_physics(held_object)
	if is_instance_valid(zap_mesh):
		zap_mesh.clear_surfaces()
	if is_instance_valid(electricity_sound):
		electricity_sound.stop()
