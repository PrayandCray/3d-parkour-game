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
const SLIDE_BOOST = 4.0
const SLIDE_MIN_SPEED = 8.0
const SLIDE_FRICTION = 0.5
const SLIDE_SLOPE_ACCEL = 20.0
const SLIDE_SLOPE_FRICTION_REDUCTION = 1.0
const SLIDE_MAX_SPEED = 18.0
const SLIDE_JUMP_BOOST = 1.6
const SLIDE_JUMP_MAX_SPEED = 24.0
const SLIDE_JUMP_DIVE_GRACE = 0.35
const SLIDE_CAM_OFFSET = Vector3(0.0, -0.4, 0.0)
const SLIDE_BODY_TILT = 85.0
const WALLRUN_SPEED = 9.0
const WALLRUN_MIN_SPEED = 3.0
const WALLRUN_MAX_TIME = 2.0
const WALLRUN_GRAVITY = 2.0
const WALL_STICK_FORCE = 12.0
const WALLRUN_COYOTE = 0.15
const WALL_NORMAL_MAX_Y = 0.25
const WALL_JUMP_UP = 5.0
const WALL_JUMP_AWAY = 7.0
const WALL_JUMP_ALONG_KEEP = 0.8
const WALL_JUMP_LOCKOUT = 0.35
const WALLRUN_COOLDOWN = 0.3

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
var slide_speed = 0.0
var slide_jump_timer = 0.0
var jump_stored = false
var t_bob = 0.0
var smooth_speed = 5
var wall_normal = Vector3.ZERO
var wallrun_time = 0
var wall_side = 0
var wall_coyote_timer = 0.0
var wall_jump_timer = 0.0
var wallrun_cooldown = 0.0
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
	left_raycast.add_exception(self)
	right_raycast.add_exception(self)

func _unhandled_input(event):
	# mouse movement
	if event is InputEventMouseMotion:
		rotate_object_local(Vector3.UP, -event.relative.x * SENSITIVITY)
		head.rotate_x(-event.relative.y * SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-40), deg_to_rad(60))

func _physics_process(delta: float) -> void:
	wall_jump_timer = maxf(wall_jump_timer - delta, 0.0)
	wallrun_cooldown = maxf(wallrun_cooldown - delta, 0.0)
	slide_jump_timer = maxf(slide_jump_timer - delta, 0.0)

	# gravity is applied in every state except WALLRUN, which has its own
	# downward force handled in handle_wallrun()
	if state != PlayerState.WALLRUN:
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
		slide_boost()
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
		return

	if not is_on_floor() and Input.is_action_pressed("Slide") and slide_jump_timer <= 0.0:
		impulse_check = false
		collision_shape_check = false
		state = PlayerState.DIVE
		return
	
	# wallrun
	if wall_jump_timer <= 0.0 and wallrun_cooldown <= 0.0 and can_wallrun():
		wallrun_time = 0.0
		wall_coyote_timer = WALLRUN_COYOTE
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
		# land straight into the slide. The dive already uses the slide collider,
		# so we must NOT reset_pos here: that swaps colliders back and forth and
		# pops the body. Keeping the shape also keeps the dive's momentum.
		state = PlayerState.SLIDE
	elif is_on_floor() and not Input.is_action_pressed("Slide"):
		reset_pos(delta)
		state = PlayerState.MOVING

func can_wallrun() -> bool:
	if is_on_floor():
		return false

	# something must be driving us along the wall: held input or existing speed
	var input_dir := Input.get_vector("Strafe Left", "Strafe Right", "Forward", "Strafe Backwards")
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if input_dir.length() < 0.1 and horizontal_speed < WALLRUN_MIN_SPEED:
		return false

	if _detect_wall(left_raycast, -1):
		return true

	if _detect_wall(right_raycast, 1):
		return true

	return false

func _detect_wall(ray: RayCast3D, side: int) -> bool:
	if not ray.is_colliding():
		return false

	var normal := ray.get_collision_normal()

	if abs(normal.y) >= WALL_NORMAL_MAX_Y:
		return false

	wall_normal = normal
	wall_side = side
	return true

func state_wallrun(delta: float) -> void:
	if can_wallrun():
		wall_coyote_timer = WALLRUN_COYOTE
		handle_wallrun(delta)
		return

	# lost the wall: keep the run alive for a short grace window so a single
	# missed frame (ray sweep, corner) does not drop the player
	if wall_coyote_timer > 0.0 and not is_on_floor():
		wall_coyote_timer -= delta
		handle_wallrun(delta)
		return

	wallrun_time = 0.0
	wall_coyote_timer = 0.0
	if is_on_floor():
		if Input.is_action_pressed("Slide"):
			state = PlayerState.SLIDE
		else:
			state = PlayerState.MOVING
	else:
		state = PlayerState.IN_AIR

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
		if wall_jump_timer <= 0.0 and slide_jump_timer <= 0.0:
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

		if is_on_floor() or (wall_jump_timer <= 0.0 and slide_jump_timer <= 0.0):
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 7.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 7.0)
		
	else:
		t_bob_check = false

func slide_boost():
	var input_dir := Input.get_vector(
		"Strafe Left",
		"Strafe Right",
		"Forward",
		"Strafe Backwards"
	)

	var direction := (
		transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	if direction.length() > 0.1:
		velocity += direction * SLIDE_BOOST

	var horizontal_velocity := Vector3(
			velocity.x,
			0,
			velocity.z
		)

	if horizontal_velocity.length() < SLIDE_MIN_SPEED:
		horizontal_velocity = direction * SLIDE_MIN_SPEED

		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.z

func slide_jump(delta: float) -> void:
	# capture the momentum carried out of the slide (larger after slopes)
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var speed_now := planar.length()

	reset_pos(delta)
	slide_jump_cam_reset = true
	slide_jump_timer = SLIDE_JUMP_DIVE_GRACE
	state = PlayerState.MOVING

	# vertical jump...
	velocity.y = JUMP_VELOCITY

	# ...plus a horizontal burst that grows with the slide speed
	if speed_now > 0.01:
		var dir := planar / speed_now
		var burst_speed := minf(speed_now * SLIDE_JUMP_BOOST, SLIDE_JUMP_MAX_SPEED)
		velocity.x = dir.x * burst_speed
		velocity.z = dir.z * burst_speed

func handle_slide(delta):
	collision_shape.disabled = true
	slide_collision_shape.disabled = false
	
	# slope physics: gravity projected onto the floor surface points downhill
	var floor_normal := get_floor_normal()
	var slope_vec := Vector3.DOWN - floor_normal * Vector3.DOWN.dot(floor_normal)
	var slope := clampf(slope_vec.length(), 0.0, 1.0)  # sin of the slope angle
	var downhill := Vector3(slope_vec.x, 0.0, slope_vec.z)
	if downhill.length() > 0.001:
		downhill = downhill.normalized()

	# accelerate downhill, steeper slopes gain more momentum
	if slope > 0.01:
		velocity.x += downhill.x * SLIDE_SLOPE_ACCEL * slope * delta
		velocity.z += downhill.z * SLIDE_SLOPE_ACCEL * slope * delta

	# friction fades on slopes so momentum is kept while descending
	var friction := SLIDE_FRICTION * (1.0 - SLIDE_SLOPE_FRICTION_REDUCTION * slope)
	velocity.x = lerp(velocity.x, 0.0, delta * friction)
	velocity.z = lerp(velocity.z, 0.0, delta * friction)

	# cap the slide so long/steep slopes do not run away
	var planar := Vector2(velocity.x, velocity.z)
	if planar.length() > SLIDE_MAX_SPEED:
		planar = planar.normalized() * SLIDE_MAX_SPEED
		velocity.x = planar.x
		velocity.z = planar.y

	slide_speed = planar.length()

	# hug the slope: keep the horizontal speed but aim the vertical component
	# along the incline, so the body glides parallel to the surface instead of
	# travelling horizontally and dropping to re-contact each frame (that stepping
	# is what makes it bob)
	if is_on_floor() and floor_normal.y > 0.2:
		velocity.y = -(velocity.x * floor_normal.x + velocity.z * floor_normal.z) / floor_normal.y

	sliding = true

	# slide pose: lean the body down and drop the camera close to the ground
	camera.rotation.z = lerp(camera.rotation.z, deg_to_rad(15), delta * 8.0)
	mesh.rotation.x = lerp_angle(mesh.rotation.x, deg_to_rad(SLIDE_BODY_TILT), delta * 6.0)
	camera.transform.origin = camera.transform.origin.lerp(SLIDE_CAM_OFFSET, delta * 10.0)
	
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		slide_jump(delta)

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
	wallrun_time += delta

	if wallrun_time >= WALLRUN_MAX_TIME:
		wallrun_time = 0.0
		wall_coyote_timer = 0.0
		wallrun_cooldown = WALLRUN_COOLDOWN
		state = PlayerState.IN_AIR
		return

	var input_dir := Input.get_vector(
		"Strafe Left",
		"Strafe Right",
		"Forward",
		"Strafe Backwards"
	)
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# horizontal direction along the wall surface
	var wall_dir := Vector3.UP.cross(wall_normal).normalized()

	# align the run with where the player is already heading
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var reference := horizontal if horizontal.length() > 0.1 else direction
	if reference.length() > 0.1 and wall_dir.dot(reference) < 0.0:
		wall_dir = -wall_dir

	# keep the momentum we arrived with (never below WALLRUN_SPEED, gently capped)
	var along_speed := clampf(maxf(horizontal.length(), WALLRUN_SPEED), WALLRUN_SPEED, WALLRUN_SPEED * 1.5)
	var target_velocity := wall_dir * along_speed

	velocity.x = lerp(velocity.x, target_velocity.x, delta * 6.0)
	velocity.z = lerp(velocity.z, target_velocity.z, delta * 6.0)

	# drift down gently instead of snapping, so entering from a jump is smooth
	velocity.y = lerp(velocity.y, -WALLRUN_GRAVITY, delta * 5.0)

	# press into the wall so we stay attached
	velocity += -wall_normal * WALL_STICK_FORCE * delta

	var target_tilt := 0.0
	if wall_side == -1:
		target_tilt = deg_to_rad(15.0)
	elif wall_side == 1:
		target_tilt = deg_to_rad(-15.0)

	camera.rotation.z = lerp(camera.rotation.z, target_tilt, delta * 8.0)

	if Input.is_action_just_pressed("Jump"):
		wall_jump(wall_dir, along_speed)

func wall_jump(wall_dir: Vector3, along_speed: float) -> void:
	# strong push away from the wall plus lift, while keeping along-wall speed
	velocity.x = wall_normal.x * WALL_JUMP_AWAY + wall_dir.x * along_speed * WALL_JUMP_ALONG_KEEP
	velocity.z = wall_normal.z * WALL_JUMP_AWAY + wall_dir.z * along_speed * WALL_JUMP_ALONG_KEEP
	velocity.y = WALL_JUMP_UP

	# brief air-control lockout so the launch momentum is not pulled back into the wall
	wall_jump_timer = WALL_JUMP_LOCKOUT
	wallrun_time = 0.0
	wall_coyote_timer = 0.0
	slide_jump_cam_reset = true
	state = PlayerState.IN_AIR
