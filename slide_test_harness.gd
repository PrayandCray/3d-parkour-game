extends Node3D

@onready var player: CharacterBody3D = $Player
@onready var ramp: CSGBox3D = $Ramp

var elapsed: float = 0.0

func _physics_process(delta: float) -> void:
	elapsed += delta
	if Engine.get_physics_frames() % 4 == 0:
		var horizontal_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
		print("t=%.2f state=%d floor=%s z=%.2f y=%.3f hspeed=%.2f vy=%.2f" % [elapsed, player.get("state"), str(player.is_on_floor()), player.global_position.z, player.global_position.y, horizontal_speed, player.velocity.y])

func _ready() -> void:
	print("test floor basis.y=", ramp.global_transform.basis.y)