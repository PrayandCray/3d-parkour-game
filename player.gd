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
const JUMP_SPEED = 3.0
const JUMP_VELOCITY = 5.0
const SENSITIVITY = 0.003
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
const BASE_FOV = 72.0
const FOV_CHANGE = 1.5

var collision_shape_check = true
var slide_jump_cam_reset = false
var rotate_shape_check = false
var t_bob_check = true
var cam_flip = false
var flip_speed = 8.0
var has_flipped = false
var impulse_force = Vector3(0, 3, -1.5)
var impulse_check = true
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
	IN_AIR, #0
	SLIDE, #1
	DIVE, #2
	MOVING, #3
	WALLRUN #4
}


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	slide_collision_shape.disabled = true

func _unhandled_input(event):
	# mouse movement
	if event is InputEventMouseMotion:
		rotate_object_local(Vector3.UP, -event.relative.x * SENSITIVITY)
		head.rotate_x(-event.relative.y * SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-40), deg_to_rad(60))

func _physics_process(delta: float) -> void:
	velocity += get_gravity() * delta

	# character controller
	match state:
		PlayerState.IN_AIR:
			state_in_air(delta)
		PlayerState.SLIDE:
			state_slide(delta)
		PlayerState.DIVE:
			state_dive(delta)
		PlayerState.MOVING:
			state_moving(delta)
		PlayerState.WALLRUN:
			state_wallrun(delta)

	# for leaving game
	if Input.is_action_just_pressed("Escape"):
		get_tree().quit()
	
	# mouse hide/unhide
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

func dir_move(delta: float) -> void:
	var input_dir = Input.get_vector("Strafe Left", "Strafe Right", "Forward", "Strafe Backwards")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	velocity.x = lerp(velocity.x, direction.x * speed, delta * 0.825)
	velocity.z = lerp(velocity.z, direction.z * speed, delta * 0.825)

func state_in_air(delta: float) -> void:
	collision_shape.rotation = Vector3.ZERO
	sprint_check(delta)
	handle_movement(delta)

	if is_on_floor() and not Input.is_action_pressed("Slide"):
		collision_shape_check = false
		state = PlayerState.MOVING
	if not is_on_floor() and Input.is_action_pressed("Slide"):
		impulse_check = false
		collision_shape_check = false
		state = PlayerState.DIVE
	
	# wallrun
	if is_on_wall_only():
		rotate_shape_check = true
		state = PlayerState.WALLRUN

func state_slide(delta: float) -> void:
	handle_slide(delta)

	if not is_on_floor() and not Input.is_action_pressed("Slide"):
		state = PlayerState.IN_AIR
	elif not Input.is_action_pressed("Slide"):
		reset_pos(delta)

func state_dive(delta: float) -> void:
	handle_dive(delta)
	dir_move(delta)
	
	if slide_jump_cam_reset == true:
		camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 8.0)
		if abs(camera.rotation.z) < 0.01:
			slide_jump_cam_reset = false

	if is_on_floor() and Input.is_action_pressed("Slide"):
		reset_pos(delta)
		state = PlayerState.SLIDE
	elif is_on_floor() and not Input.is_action_pressed("Slide"):
		state = PlayerState.MOVING

func state_wallrun(delta: float) -> void:
	handle_wallrun(delta)
	
	if not is_on_wall_only() and not is_on_floor():
		state = PlayerState.IN_AIR
	elif not is_on_wall() and is_on_floor() and not Input.is_action_pressed("Slide"):
		state = PlayerState.MOVING
	elif not is_on_wall() and is_on_floor() and Input.is_action_pressed("Slide"):
		state = PlayerState.SLIDE

func jump(delta: float) -> void:
	velocity.y = JUMP_VELOCITY
	jump_stored = false

func sprint_check(delta: float) -> void:
	if Input.is_action_just_pressed("Sprint"):
		speed = SPRINT_SPEED
	if Input.is_action_just_released("Sprint"):
		speed = WALK_SPEED

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
		
		var velocity_clamped = clamp(velocity.length(), 0.5, SPRINT_SPEED * 2)
		var target_fov = BASE_FOV + FOV_CHANGE * velocity_clamped
		camera.fov = lerp(camera.fov, target_fov, delta * 8)
		
	else:
		velocity.x = lerp(velocity.x, direction.x * speed, delta * 0.825)
		velocity.z = lerp(velocity.z, direction.z * speed, delta * 0.825)
		
		var target_fov = BASE_FOV + FOV_CHANGE
		camera.fov = lerp(camera.fov, target_fov, delta * 8)

	camera.rotation.z = lerp(camera.rotation.z, 0.0, delta * 6.0)

	sprint_check(delta)

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
	camera.transform.origin.z = 0.0
	
	# lerp slide
	var target_rot = deg_to_rad(85)
	var lerp_speed = 6.0
	
	mesh.rotation.x = lerp_angle(mesh.rotation.x, target_rot, lerp_speed * delta)
	
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		reset_pos(delta)
		slide_jump_cam_reset = true
		state = PlayerState.MOVING
		jump(delta)

func handle_dive(delta: float) -> void:
	collision_shape.disabled = true
	slide_collision_shape.disabled = false
	
	if impulse_check == false:
		if speed == SPRINT_SPEED:
			velocity += (transform.basis * impulse_force)
		elif speed == WALK_SPEED:
			velocity += 0.8 * (transform.basis * impulse_force)
		impulse_check = true
		
		camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(0), delta * 8.0)
		camera.transform.origin.z = -1.0
	
	var target_rot = deg_to_rad(-85)
	var lerp_speed = 6.0
	
	mesh.rotation.x = lerp_angle(mesh.rotation.x, target_rot, lerp_speed * delta)

func handle_wallrun(delta: float) -> void:

	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		if collision.get_normal().y < 0.1:
			wall_normal = collision.get_normal()
			break

	var input_dir := Input.get_vector("Strafe Left", "Strafe Right", "Forward", "Strafe Backwards")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var camera_forward = -head.transform.basis.z
	var wall_dir
	var wallrun_direction: Vector3
	
	var grav_force = get_gravity().y
	var counteract_gravity = -grav_force * 0.55
	velocity.y += counteract_gravity * delta
	
	# wall normal calcs
	if wall_normal.x == 1.00 and direction.z > 0:
		wall_dir = "right"
		wallrun_direction = Vector3(0, 0, 1)
		camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(15), delta * 8.0)
	elif wall_normal.x == 1.00 and direction.z < 0:
		wall_dir = "left"
		wallrun_direction = Vector3(0, 0, -1)
		camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(-15), delta * 8.0)
	if wall_normal.x == -1.00 and direction.z > 0:
		wall_dir = "left"
		wallrun_direction = Vector3(0, 0, 1)
		camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(-15), delta * 8.0)
	elif wall_normal.x == -1.00 and direction.z < 0:
		wall_dir = "right"
		wallrun_direction = Vector3(0, 0, -1)
		camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(15), delta * 8.0)
	
	if input_dir.length() > 0.1:
		velocity.x = lerp(velocity.x, wallrun_direction.x * speed, delta * 7.0)
		velocity.z = lerp(velocity.z, wallrun_direction.z * speed, delta * 7.0)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 3.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 3.0)
	
	screen_output.print(str(wall_dir))
	
	if Input.is_action_just_pressed("Jump"):
		var jump_force = wall_normal * 8.0 + Vector3.UP * JUMP_VELOCITY
		velocity += jump_force
		state = PlayerState.IN_AIR
		slide_jump_cam_reset = true
