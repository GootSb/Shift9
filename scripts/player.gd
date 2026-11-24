extends CharacterBody3D

# ==================================================
# MOVEMENT
# ==================================================

@export_group("Movement")

@export var move_speed: float = 7.0
@export var heavy_move_speed: float = 3.5
@export var acceleration: float = 20.0
@export var deceleration: float = 25.0
@export var gravity: float = 20.0


func get_current_move_speed() -> float:
	if is_instance_valid(held_object) and held_object.is_in_group("Heavy"):
		return heavy_move_speed

	return move_speed


# ==================================================
# JUMP CHARGING
# ==================================================

@export_group("Jump")

@export var min_jump_velocity: float = 4.5
@export var max_jump_velocity: float = 12.0
@export var jump_charge_time: float = 2.0

var is_charging_jump: bool = false
var jump_charge: float = 0.0


# ==================================================
# CAMERA
# ==================================================

@export_group("Camera")

@export var mouse_sensitivity: float = 0.002
@export var max_look_angle: float = 85.0

var camera_pitch: float = 0.0


# ==================================================
# HEAD BOB
# ==================================================

@export_group("Head Bob")

@export var head_bob_enabled: bool = true
@export var head_bob_frequency: float = 9.0
@export var head_bob_amount: float = 0.06
@export var head_bob_smoothing: float = 10.0

var camera_rest_position: Vector3
var head_bob_time: float = 0.0
var head_bob_offset: Vector3 = Vector3.ZERO


# ==================================================
# FREECAM
# ==================================================

@export_group("Freecam")

@export var freecam_speed: float = 8.0
@export var freecam_fast_speed: float = 20.0
@export var freecam_sensitivity: float = 0.002

var freecam_enabled: bool = false
var freecam_position: Vector3
var freecam_rotation: Vector3

var saved_player_rotation: float
var saved_camera_pitch: float


# ==================================================
# INTERACTABLE OBJECTS
# ==================================================

@export_group("Interactables")

@export var pickup_range: float = 3.0
@export var hold_distance: float = 2.0
@export var hold_smoothing: float = 15.0

@export var min_throw_force: float = 3.0
@export var max_throw_force: float = 25.0
@export var throw_charge_time: float = 2.0

var held_object: RigidBody3D = null
var held_collision_shape: CollisionShape3D = null

var original_collision_layer: int = 0
var original_collision_mask: int = 0
var original_freeze_mode: int = RigidBody3D.FREEZE_MODE_STATIC
var original_freeze: bool = false

var is_charging_throw: bool = false
var throw_charge: float = 0.0


# ==================================================
# LIGHTNING
# ==================================================

@export_group("Lightning")

@export var zap_segments: int = 20
@export var zap_jaggedness: float = 0.14
@export var zap_update_speed: float = 0.025

@export var zap_outer_width: float = 0.11
@export var zap_middle_width: float = 0.045
@export var zap_core_width: float = 0.012

@export var zap_glow: float = 8.0
@export var zap_branch_count: int = 4

var zap_active: bool = false
var zap_update_timer: float = 0.0

var zap_mesh: ImmediateMesh
var zap_mesh_instance: MeshInstance3D

var zap_outer_material: StandardMaterial3D
var zap_middle_material: StandardMaterial3D
var zap_core_material: StandardMaterial3D


# ==================================================
# NODE REFERENCES
# ==================================================

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

@onready var zap_point_0: Node3D = $Head/RightArm/ZapPoint0
@onready var zap_point_1: Node3D = $Head/LeftArm/ZapPoint1

@onready var jump_charge_bar: ProgressBar = $HUD/JumpChargeBar
@onready var throw_charge_bar: ProgressBar = $HUD/ThrowChargeBar

@onready var electricity_sound: AudioStreamPlayer3D = $Electricity


# ==================================================
# READY
# ==================================================

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	camera_rest_position = camera.position

	jump_charge_bar.min_value = 0.0
	jump_charge_bar.max_value = 100.0
	jump_charge_bar.hide()

	throw_charge_bar.min_value = 0.0
	throw_charge_bar.max_value = 100.0
	throw_charge_bar.hide()

	electricity_sound.stop()

	create_zap_effect()


# ==================================================
# INPUT
# ==================================================

func _input(event: InputEvent) -> void:

	if event is InputEventMouseMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return

		if freecam_enabled:
			freecam_rotation.y -= event.relative.x * freecam_sensitivity
			freecam_rotation.x -= event.relative.y * freecam_sensitivity

			freecam_rotation.x = clampf(
				freecam_rotation.x,
				deg_to_rad(-max_look_angle),
				deg_to_rad(max_look_angle)
			)

			camera.global_rotation = freecam_rotation

		else:
			rotate_y(-event.relative.x * mouse_sensitivity)

			camera_pitch -= event.relative.y * mouse_sensitivity

			camera_pitch = clampf(
				camera_pitch,
				deg_to_rad(-max_look_angle),
				deg_to_rad(max_look_angle)
			)

			head.rotation.x = camera_pitch

	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return

		if freecam_enabled:
			return

		if event.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				start_throw_charge()
		else:
			throw_object()

	elif event is InputEventKey:
		if not event.pressed or event.echo:
			return

		match event.keycode:
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

			KEY_F3:
				toggle_freecam()

			KEY_E:
				if freecam_enabled:
					return

				if held_object == null:
					pickup_interactable()
				else:
					drop_object()


# ==================================================
# PHYSICS
# ==================================================

func _physics_process(delta: float) -> void:

	if freecam_enabled:
		handle_freecam(delta)
		return

	handle_movement(delta)
	handle_jump(delta)
	handle_gravity(delta)

	handle_head_bob(delta)
	handle_held_object(delta)

	update_jump_charge_bar()
	update_throw_charge_bar(delta)

	move_and_slide()


# ==================================================
# MOVEMENT
# ==================================================

func handle_movement(delta: float) -> void:

	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	var direction: Vector3 = (
		transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	).normalized()

	var current_speed: float = get_current_move_speed()

	if direction.length_squared() > 0.0:
		velocity.x = move_toward(
			velocity.x,
			direction.x * current_speed,
			acceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			direction.z * current_speed,
			acceleration * delta
		)

	else:
		velocity.x = move_toward(
			velocity.x,
			0.0,
			deceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			deceleration * delta
		)


# ==================================================
# JUMP
# ==================================================

func handle_jump(delta: float) -> void:

	if not is_on_floor():
		is_charging_jump = false
		jump_charge = 0.0
		return

	if Input.is_action_just_pressed("jump"):
		is_charging_jump = true
		jump_charge = 0.0

	if is_charging_jump and Input.is_action_pressed("jump"):
		jump_charge = minf(
			jump_charge + delta,
			maxf(jump_charge_time, 0.0)
		)

	if is_charging_jump and Input.is_action_just_released("jump"):
		velocity.y = lerpf(
			min_jump_velocity,
			max_jump_velocity,
			get_jump_charge_percentage()
		)

		is_charging_jump = false
		jump_charge = 0.0


func get_jump_charge_percentage() -> float:

	if jump_charge_time <= 0.0:
		return 1.0

	return clampf(jump_charge / jump_charge_time, 0.0, 1.0)


func update_jump_charge_bar() -> void:

	if is_charging_jump:
		jump_charge_bar.show()
		jump_charge_bar.value = get_jump_charge_percentage() * 100.0
	else:
		jump_charge_bar.hide()


# ==================================================
# GRAVITY
# ==================================================

func handle_gravity(delta: float) -> void:

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


# ==================================================
# HEAD BOB
# ==================================================

func handle_head_bob(delta: float) -> void:

	var horizontal_speed: float = Vector2(
		velocity.x,
		velocity.z
	).length()

	var moving: bool = horizontal_speed > 0.1 and is_on_floor()

	var target_offset: Vector3 = Vector3.ZERO

	if head_bob_enabled and moving:
		head_bob_time += delta * head_bob_frequency

		target_offset.y = sin(head_bob_time) * head_bob_amount
		target_offset.x = (
			cos(head_bob_time * 0.5) * head_bob_amount * 0.5
		)

	var smooth_amount: float = 1.0 - exp(-head_bob_smoothing * delta)

	head_bob_offset = head_bob_offset.lerp(
		target_offset,
		smooth_amount
	)

	camera.position = camera_rest_position + head_bob_offset


# ==================================================
# PICKUP INTERACTABLE
# ==================================================

func pickup_interactable() -> void:

	var space_state := get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		camera.global_position - camera.global_transform.basis.z * pickup_range
	)

	query.exclude = [get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)

	if result.is_empty():
		return

	var collider: Object = result.get("collider")

	if not (collider is RigidBody3D):
		return

	var body := collider as RigidBody3D

	if not body.is_in_group("Interactable"):
		return

	var shape := body.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D

	if shape == null or shape.shape == null:
		push_warning(
			"Interactable needs a direct child CollisionShape3D with a shape."
		)
		return

	held_object = body
	held_collision_shape = shape

	original_collision_layer = body.collision_layer
	original_collision_mask = body.collision_mask
	original_freeze_mode = body.freeze_mode
	original_freeze = body.freeze

	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO

	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true

	start_zap()

	print("INTERACTABLE PICKED UP: ", body.name)


# ==================================================
# HOLD INTERACTABLE
# ==================================================

func handle_held_object(delta: float) -> void:

	if held_object == null:
		return

	if not is_instance_valid(held_object):
		clear_held_reference()
		stop_zap()
		return

	var target_position: Vector3 = (
		camera.global_position -
		camera.global_transform.basis.z * hold_distance
	)

	var smooth_amount: float = 1.0 - exp(-hold_smoothing * delta)

	held_object.global_position = held_object.global_position.lerp(
		target_position,
		smooth_amount
	)

	held_object.global_rotation = camera.global_rotation

	update_zap_effect(delta)


# ==================================================
# RESTORE OBJECT PHYSICS
# ==================================================

func restore_object_physics(
	object: RigidBody3D,
	force_unfreeze: bool = false
) -> void:

	if not is_instance_valid(object):
		return

	object.collision_layer = original_collision_layer
	object.collision_mask = original_collision_mask
	object.freeze_mode = original_freeze_mode

	if force_unfreeze:
		object.freeze = false
	else:
		object.freeze = original_freeze


# ==================================================
# CLEAR HELD REFERENCE
# ==================================================

func clear_held_reference() -> void:

	held_object = null
	held_collision_shape = null

	is_charging_throw = false
	throw_charge = 0.0

	throw_charge_bar.hide()


# ==================================================
# DROP INTERACTABLE
# ==================================================

func drop_object() -> void:

	if held_object == null:
		return

	if is_instance_valid(held_object):
		restore_object_physics(held_object)

		held_object.linear_velocity = Vector3.ZERO
		held_object.angular_velocity = Vector3.ZERO

	clear_held_reference()
	stop_zap()

	print("INTERACTABLE DROPPED")


# ==================================================
# THROW CHARGING
# ==================================================

func start_throw_charge() -> void:

	if not is_instance_valid(held_object):
		return

	if is_charging_throw:
		return

	is_charging_throw = true
	throw_charge = 0.0


func update_throw_charge_bar(delta: float) -> void:

	if is_charging_throw and is_instance_valid(held_object):
		throw_charge = minf(
			throw_charge + delta,
			maxf(throw_charge_time, 0.0)
		)

		throw_charge_bar.show()
		throw_charge_bar.value = get_throw_charge_percentage() * 100.0

	else:
		throw_charge_bar.hide()


func get_throw_charge_percentage() -> float:

	if throw_charge_time <= 0.0:
		return 1.0

	return clampf(throw_charge / throw_charge_time, 0.0, 1.0)


# ==================================================
# THROW INTERACTABLE
# ==================================================

func throw_object() -> void:

	if not is_charging_throw:
		return

	is_charging_throw = false
	throw_charge_bar.hide()

	if not is_instance_valid(held_object):
		clear_held_reference()
		stop_zap()
		return

	var percentage: float = get_throw_charge_percentage()

	var throw_force: float = lerpf(
		min_throw_force,
		max_throw_force,
		percentage
	)

	var direction: Vector3 = (
		-camera.global_transform.basis.z
	).normalized()

	var object_to_throw: RigidBody3D = held_object

	restore_object_physics(object_to_throw, true)

	object_to_throw.linear_velocity = Vector3.ZERO
	object_to_throw.angular_velocity = Vector3.ZERO

	clear_held_reference()
	stop_zap()

	object_to_throw.apply_central_impulse(
		direction * throw_force
	)

	print("INTERACTABLE THROWN")


# ==================================================
# LIGHTNING MATERIALS
# ==================================================

func make_zap_material(
	color: Color,
	energy: float,
	alpha: float
) -> StandardMaterial3D:

	var material := StandardMaterial3D.new()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	material.albedo_color = Color(
		color.r,
		color.g,
		color.b,
		alpha
	)

	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy

	return material


# ==================================================
# CREATE LIGHTNING
# ==================================================

func create_zap_effect() -> void:

	zap_mesh = ImmediateMesh.new()

	zap_mesh_instance = MeshInstance3D.new()
	zap_mesh_instance.name = "LightningEffect"
	zap_mesh_instance.mesh = zap_mesh

	zap_mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	add_child(zap_mesh_instance)

	zap_outer_material = make_zap_material(
		Color(0.02, 0.2, 1.0),
		zap_glow * 1.5,
		0.25
	)

	zap_middle_material = make_zap_material(
		Color(0.0, 0.65, 1.0),
		zap_glow * 1.2,
		0.65
	)

	zap_core_material = make_zap_material(
		Color(0.75, 0.95, 1.0),
		zap_glow,
		1.0
	)

	zap_mesh_instance.hide()


# ==================================================
# START LIGHTNING AND SOUND
# ==================================================

func start_zap() -> void:

	zap_active = true
	zap_update_timer = maxf(zap_update_speed, 0.001)

	zap_mesh_instance.show()

	if not electricity_sound.playing:
		electricity_sound.play()

	update_zap_effect(0.0)


# ==================================================
# STOP LIGHTNING AND SOUND
# ==================================================

func stop_zap() -> void:

	zap_active = false

	if zap_mesh != null:
		zap_mesh.clear_surfaces()

	if zap_mesh_instance != null:
		zap_mesh_instance.hide()

	if electricity_sound.playing:
		electricity_sound.stop()


# ==================================================
# DRAW LIGHTNING RIBBON
# ==================================================

func draw_zap_ribbon(
	points: Array[Vector3],
	side: Vector3,
	width: float,
	material: Material
) -> void:

	if points.size() < 2:
		return

	zap_mesh.surface_begin(
		Mesh.PRIMITIVE_TRIANGLES,
		material
	)

	var safe_width: float = maxf(width, 0.0)

	for i in range(points.size() - 1):

		var a: Vector3 = points[i] - side * safe_width
		var b: Vector3 = points[i] + side * safe_width
		var c: Vector3 = points[i + 1] - side * safe_width
		var d: Vector3 = points[i + 1] + side * safe_width

		zap_mesh.surface_add_vertex(a)
		zap_mesh.surface_add_vertex(b)
		zap_mesh.surface_add_vertex(c)

		zap_mesh.surface_add_vertex(b)
		zap_mesh.surface_add_vertex(d)
		zap_mesh.surface_add_vertex(c)

	zap_mesh.surface_end()


# ==================================================
# GENERATE LIGHTNING POINTS
# ==================================================

func generate_zap_points(
	start_position: Vector3,
	end_position: Vector3,
	segments: int,
	jaggedness: float,
	side: Vector3,
	perpendicular: Vector3
) -> Array[Vector3]:

	var points: Array[Vector3] = []

	var safe_segments: int = maxi(segments, 1)

	for i in range(safe_segments + 1):

		var progress: float = float(i) / float(safe_segments)

		var point: Vector3 = start_position.lerp(
			end_position,
			progress
		)

		if i > 0 and i < safe_segments:

			var falloff: float = sin(progress * PI)

			point += side * randf_range(
				-jaggedness,
				jaggedness
			) * falloff

			point += perpendicular * randf_range(
				-jaggedness,
				jaggedness
			) * falloff

		points.append(point)

	return points


# ==================================================
# UPDATE LIGHTNING
# ==================================================

func update_zap_effect(delta: float) -> void:

	if not zap_active:
		return

	zap_update_timer += delta

	var update_interval: float = maxf(zap_update_speed, 0.001)

	if zap_update_timer < update_interval:
		return

	zap_update_timer = 0.0

	if not is_instance_valid(zap_point_0):
		return

	if not is_instance_valid(zap_point_1):
		return

	var start_position: Vector3 = zap_mesh_instance.to_local(
		zap_point_0.global_position
	)

	var end_position: Vector3 = zap_mesh_instance.to_local(
		zap_point_1.global_position
	)

	var direction: Vector3 = end_position - start_position

	if direction.length_squared() < 0.0001:
		return

	var direction_normalized: Vector3 = direction.normalized()

	var camera_right: Vector3 = (
		zap_mesh_instance.global_transform.basis.inverse() *
		camera.global_transform.basis.x
	).normalized()

	var side: Vector3 = camera_right - (
		direction_normalized *
		camera_right.dot(direction_normalized)
	)

	if side.length_squared() < 0.001:
		side = direction_normalized.cross(Vector3.UP)

	if side.length_squared() < 0.001:
		side = direction_normalized.cross(Vector3.RIGHT)

	side = side.normalized()

	var perpendicular: Vector3 = (
		direction_normalized.cross(side)
	).normalized()

	var segments: int = maxi(zap_segments, 5)

	var main_points: Array[Vector3] = generate_zap_points(
		start_position,
		end_position,
		segments,
		maxf(zap_jaggedness, 0.0),
		side,
		perpendicular
	)

	zap_mesh.clear_surfaces()

	draw_zap_ribbon(
		main_points,
		side,
		zap_outer_width,
		zap_outer_material
	)

	draw_zap_ribbon(
		main_points,
		perpendicular,
		zap_middle_width,
		zap_middle_material
	)

	draw_zap_ribbon(
		main_points,
		side,
		zap_core_width,
		zap_core_material
	)

	var safe_branch_count: int = maxi(zap_branch_count, 0)

	for branch_index in range(safe_branch_count):

		var start_index: int = randi_range(
			2,
			segments - 3
		)

		var branch_start: Vector3 = main_points[start_index]

		var branch_direction: Vector3 = (
			side * randf_range(-0.4, 0.4) +
			perpendicular * randf_range(0.6, 1.0)
		).normalized()

		var branch_end: Vector3 = (
			branch_start +
			branch_direction * randf_range(0.15, 0.4)
		)

		var branch_points: Array[Vector3] = generate_zap_points(
			branch_start,
			branch_end,
			4,
			maxf(zap_jaggedness, 0.0) * 0.5,
			side,
			perpendicular
		)

		draw_zap_ribbon(
			branch_points,
			side,
			zap_core_width * 1.5,
			zap_middle_material
		)


# ==================================================
# FREECAM TOGGLE
# ==================================================

func toggle_freecam() -> void:

	if not freecam_enabled and is_instance_valid(held_object):
		drop_object()

	freecam_enabled = not freecam_enabled

	if freecam_enabled:

		saved_player_rotation = rotation.y
		saved_camera_pitch = camera_pitch

		freecam_position = camera.global_position
		freecam_rotation = camera.global_rotation

		is_charging_jump = false
		jump_charge = 0.0
		jump_charge_bar.hide()

		is_charging_throw = false
		throw_charge = 0.0
		throw_charge_bar.hide()

		velocity = Vector3.ZERO

	else:

		rotation.y = saved_player_rotation

		camera_pitch = saved_camera_pitch
		head.rotation.x = camera_pitch

		head_bob_offset = Vector3.ZERO

		camera.position = camera_rest_position
		camera.rotation = Vector3.ZERO


# ==================================================
# FREECAM MOVEMENT
# ==================================================

func handle_freecam(delta: float) -> void:

	var speed: float = freecam_speed

	if Input.is_key_pressed(KEY_SHIFT):
		speed = freecam_fast_speed

	var input_dir: Vector3 = Vector3.ZERO

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

		var movement: Vector3 = (
			Basis.from_euler(freecam_rotation) * input_dir
		)

		freecam_position += movement * speed * delta

	camera.global_position = freecam_position
	camera.global_rotation = freecam_rotation


# ==================================================
# CLEANUP
# ==================================================

func _exit_tree() -> void:

	if is_instance_valid(held_object):
		restore_object_physics(held_object)

	if zap_mesh != null:
		zap_mesh.clear_surfaces()

	if electricity_sound != null and electricity_sound.playing:
		electricity_sound.stop()
