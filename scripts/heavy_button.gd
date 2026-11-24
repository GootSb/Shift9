extends StaticBody3D

@onready var button_mesh: MeshInstance3D = $MeshInstance3D
@onready var on_sound: AudioStreamPlayer3D = $On
@onready var off_sound: AudioStreamPlayer3D = $Off
@onready var detection_area: Area3D = $DetectionArea

var button_off: Material = preload("res://materials/ButtonOff.tres")
var button_on: Material = preload("res://materials/ButtonOn.tres")

var heavy_objects_on_button: Array[RigidBody3D] = []
var button_is_on: bool = false


func _ready() -> void:
	button_mesh.material_override = button_off

	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body is RigidBody3D:
		return

	if not body.is_in_group("Heavy"):
		return

	var rigid_body := body as RigidBody3D

	if heavy_objects_on_button.has(rigid_body):
		return

	heavy_objects_on_button.append(rigid_body)

	if not button_is_on:
		turn_button_on()


func _on_body_exited(body: Node3D) -> void:
	if not body is RigidBody3D:
		return

	var rigid_body := body as RigidBody3D

	if not heavy_objects_on_button.has(rigid_body):
		return

	heavy_objects_on_button.erase(rigid_body)

	if heavy_objects_on_button.is_empty() and button_is_on:
		turn_button_off()


func turn_button_on() -> void:
	button_is_on = true
	button_mesh.material_override = button_on

	# Preserve your original sound mapping.
	off_sound.play()


func turn_button_off() -> void:
	button_is_on = false
	button_mesh.material_override = button_off

	# Preserve your original sound mapping.
	on_sound.play()
