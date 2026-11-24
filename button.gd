extends StaticBody3D

@onready var button_mesh: MeshInstance3D = $MeshInstance3D
@onready var on_sound: AudioStreamPlayer3D = $On
@onready var off_sound: AudioStreamPlayer3D = $Off
@onready var detection_area: Area3D = $DetectionArea

var button_off: Material = preload("res://materials/ButtonOff.tres")
var button_on: Material = preload("res://materials/ButtonOn.tres")

var box_on_button: bool = false
var interactables_on_button: Array[RigidBody3D] = []


func _ready() -> void:

	button_mesh.material_override = button_off

	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:

	if not body is RigidBody3D:
		return

	if not body.is_in_group("Interactable"):
		return

	var rigid_body := body as RigidBody3D

	if interactables_on_button.has(rigid_body):
		return

	interactables_on_button.append(rigid_body)

	if not box_on_button:
		turn_button_on()


func _on_body_exited(body: Node3D) -> void:

	if not body is RigidBody3D:
		return

	var rigid_body := body as RigidBody3D

	if not interactables_on_button.has(rigid_body):
		return

	interactables_on_button.erase(rigid_body)

	if interactables_on_button.is_empty() and box_on_button:
		turn_button_off()


func turn_button_on() -> void:

	box_on_button = true

	button_mesh.material_override = button_on

	# Play when button turns ON.
	off_sound.play()


func turn_button_off() -> void:

	box_on_button = false

	button_mesh.material_override = button_off

	# Play when button turns OFF.
	on_sound.play()
