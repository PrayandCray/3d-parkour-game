extends CharacterBody3D

@onready var screen_output: CanvasLayer = $OnscreenOutput
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var raycast: RayCast3D = $Head/RayCast3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var left_raycast: RayCast3D = $"Wall Raycasts/Left Raycast"
@onready var right_raycast: RayCast3D = $"Wall Raycasts/Right Raycast"
@onready var slide_collision_shape: CollisionShape3D = $"Slide Collision Shape"

const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0 
const JUMP_VELOCITY = 5.0
const SENSITIVITY = 0.003
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
const BASE_FOV = 72.0
const FOV_CHANGE = 1.5

var collision_shape_check = true
var t_bob_check = true
var state: PlayerState = PlayerState.MOVING
var speed: float = WALK_SPEED
var current_height = 1
var target_height
var sliding = false
var jump_stored = false
var t_bob = 0.0
var smooth_speed = 5
var wall_normal = Vector3.ZERO
enum PlayerState {
	IN_AIR,
	SLIDE,
	MOVING
}


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	slide_collision_shape.disabled = true

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_object_local(Vector3.UP, -event.relative.x * SENSITIVITY)
		head.rotate_x(-event.relative.y * SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-40), deg_to_rad(60))

func _physics_process(delta: float) -> void:
	velocity += get_gravity() * delta

	match state:
		PlayerState.IN_AIR:
			state_in_air(delta)
		PlayerState.SLIDE:
			state_slide(delta)
		PlayerState.MOVING:
			state_moving(delta)

	# for leaving game
	if Input.is_action_just_pressed("Escape"):
		get_tree().quit()
	if Input.is_action_just_pressed("ui_up"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if Input.is_action_just_pressed("ui_down"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if Input.is_action_just_released("Slide") and is_on_floor():
		reset_pos(delta)

	move_and_slide()

func state_moving(delta: float) -> void:
	handle_movement(delta)

	if not is_on_floor() and not Input.is_action_just_pressed("Slide"):
		state = PlayerState.IN_AIR
	elif Input.is_action_just_pressed("Slide") and is_on_floor():
		state = PlayerState.SLIDE

func state_in_air(delta: float) -> void:
	collision_shape.rotation = Vector3.ZERO
	handle_movement(delta)

	if is_on_floor() and not Input.is_action_pressed("Slide"):
		collision_shape_check = false
		state = PlayerState.MOVING

func state_slide(delta: float) -> void:
	handle_slide(delta)

	if not is_on_floor() and not Input.is_action_pressed("Slide"):
		state = PlayerState.IN_AIR
	elif not Input.is_action_pressed("Slide"):
		reset_pos(delta)

func jump(delta: float) -> void:
	velocity.y = JUMP_VELOCITY
	jump_stored = false

func reset_pos(delta: float) -> void:
	sliding = false 
	mesh.rotation = Vector3.ZERO
	collision_shape.disabled = false
	slide_collision_shape.disabled = true
	state = PlayerState.MOVING

func headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	if not Input.is_action_pressed("Slide"):
		pos.y = sin(time * BOB_FREQ) * BOB_AMP
		pos.x = sin(time * BOB_FREQ / 2) * BOB_AMP
	return pos

func handle_movement(delta):
	if collision_shape_check == false:
		reset_pos(delta)
		collision_shape_check = true

	var input_dir := Input.get_vector("Strafe Left", "Strafe Right", "Forward", "Strafe Backwards")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if is_on_floor():
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 0.8)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 0.8)
	
	var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
	var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
	camera.fov = lerp(camera.fov, target_fov, delta * 8)

	camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 6.0)

	if Input.is_action_just_pressed("Sprint"):
		speed = SPRINT_SPEED
	if Input.is_action_just_released("Sprint"):
		speed = WALK_SPEED

	if Input.is_action_just_pressed("Jump") and is_on_floor() and sliding == false or jump_stored == true:
		velocity.y = JUMP_VELOCITY
		jump_stored = false

	# headbob
	
	if direction.length() > 0.01 and is_on_floor() and state != PlayerState.SLIDE:
		if t_bob_check == false:
			t_bob = 0
			t_bob_check = true
		else:
			t_bob += delta * velocity.length()
			camera.transform.origin = headbob(t_bob)
	else:
		camera.transform.origin = camera.transform.origin.lerp(Vector3.ZERO, delta * 5.0)

	if state == PlayerState.MOVING and Input.is_action_just_pressed("Slide") and is_on_floor():
		state = PlayerState.SLIDE

	if direction.length() > 0.001:
		var target = 0.0
		var current_cam_y = camera.transform.origin.y
		var current_cam_x = camera.transform.origin.x

		camera.transform.origin.y = lerp(current_cam_y, target, delta * smooth_speed)
		camera.transform.origin.x = lerp(current_cam_x, target, delta * smooth_speed)

		velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
		
	else:
		t_bob_check = false

func handle_slide(delta):
	collision_shape.disabled = true
	slide_collision_shape.disabled = false
	
	velocity.x = lerp(velocity.x, 0.0, delta * 0.8)
	velocity.z = lerp(velocity.z, 0.0, delta * 0.8)
	
	sliding = true
	camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(15), delta * 8.0)
	camera.transform.origin.x = -0.4
	camera.transform.origin.y = -0.1 
	
	# lerp slide
	var target_rot = deg_to_rad(85)
	var lerp_speed = 6.0
	
	mesh.rotation.x = lerp_angle(mesh.rotation.x, target_rot, lerp_speed * delta)
	
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		reset_pos(delta)
		state = PlayerState.MOVING
		jump(delta)

func start_wallrun(normal: Vector3) -> void:
	var wall_forward = velocity - normal * velocity.dot(normal)
	wall_forward = wall_forward.normalized() * speed
	
	velocity.x = wall_forward.x
	velocity.z = wall_forward.z
	velocity.y = clamp(velocity.y, -2.0, -5.0)
