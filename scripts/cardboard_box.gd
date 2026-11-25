extends RigidBody3D

@export var impact_speed: float = 2.0
@export var sound_cooldown: float = 0.25

@onready var metal_sound: AudioStreamPlayer3D = get_node_or_null("Metal")
@onready var cardboard_sound: AudioStreamPlayer3D = get_node_or_null("Cardboard")

var previous_vertical_speed: float = 0.0
var sound_timer: float = 0.0


func _physics_process(delta: float) -> void:
	sound_timer = maxf(sound_timer - delta, 0.0)

	var current_vertical_speed := linear_velocity.y

	# Detect when the box hits something while falling.
	if previous_vertical_speed < -impact_speed and current_vertical_speed > previous_vertical_speed:
		if sound_timer <= 0.0:
			play_landing_sound()
			sound_timer = sound_cooldown

	previous_vertical_speed = current_vertical_speed


func play_landing_sound() -> void:
	if is_in_group("Metal"):
		if metal_sound:
			metal_sound.play()

	elif is_in_group("Cardboard"):
		if cardboard_sound:
			cardboard_sound.play()
