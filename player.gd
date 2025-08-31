extends CharacterBody3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast: RayCast3D = $Head/RayCast3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0 
const JUMP_VELOCITY = 5.0
const SENSITIVITY = 0.003
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
const BASE_FOV = 72.0
const FOV_CHANGE = 1.5

var speed
var current_height = 1
var target_height
var sliding = false
var jump_stored = false
var t_bob = 0.0
var smooth_speed = 5

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-40), deg_to_rad(60))

func _physics_process(delta: float) -> void:
	
	# for leaving game
	if Input.is_action_just_pressed("Escape"):
		get_tree().quit()

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("Jump") and is_on_floor() and sliding == false or jump_stored == true and is_on_floor() and sliding == false:
		velocity.y = JUMP_VELOCITY
		jump_stored = false

	var input_dir := Input.get_vector("Strafe Left", "Strafe Right", "Forward", "Strafe Backwards")
	var direction := (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	#sprint check
	if Input.is_action_pressed("Sprint"):
		speed = SPRINT_SPEED
	else:
		speed = WALK_SPEED
	
		
	if is_on_floor():
			#slide 
		if Input.is_action_just_pressed("Slide"):
			speed = SPRINT_SPEED
			
		
		elif Input.is_action_pressed("Slide"):
			sliding = true
			# horizon align
			
			target_height = 0.36
			scale.y = lerp(scale.y, target_height, delta * smooth_speed)
			
			camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-30), deg_to_rad(30))
			# roll tilt
			camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(10), delta * 6.0)
			velocity.x = lerp(velocity.x, 0.0, delta * 1)
			velocity.z = lerp(velocity.z, 0.0, delta * 1)
			if get_slide_collision_count() > 3:
				velocity.z = 0
				velocity.x = 0

		else:
			sliding = false
			scale.y = 1
			camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 6.0)
			collision_shape.scale.y = 1
			speed = WALK_SPEED
		
			if direction:
				velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
				velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
				
				#head bob
				t_bob += delta * velocity.length() * float(is_on_floor())
				camera.transform.origin = headbob(t_bob)
				
				#fov change
				var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
				var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
				camera.fov = lerp(camera.fov, target_fov, delta * 8)
				
			
			else:
				t_bob = 0.0
				var target = 0.0
				var current_cam_y = camera.transform.origin.y
				var current_cam_x = camera.transform.origin.x
				
				camera.transform.origin.y = lerp(current_cam_y, target, delta * smooth_speed)
				camera.transform.origin.x = lerp(current_cam_x, target, delta * smooth_speed)
		
				velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
				velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 3.0)
		
		if raycast.is_colliding() and Input.is_action_just_pressed("Jump") and velocity.y < 0:
			var hit_point = raycast.get_collision_point()
			var distance = raycast.global_position.distance_to(hit_point)
			if distance < 0.75:
				jump_stored = true
	
	move_and_slide()
	
func headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = sin(time * BOB_FREQ / 2) * BOB_AMP
	return pos
