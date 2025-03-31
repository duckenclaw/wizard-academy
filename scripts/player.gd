extends CharacterBody3D

const WALK_SPEED = 5.0
const RUN_SPEED = 8.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002
const INPUT_BUFFER_TIME = 0.5  # Time window for input buffer in seconds
const CHARGE_BUFFER_TIME = 0.3  # Time window for charge moves

# Animation states
enum AnimState {
	IDLE,
	IDLE1,
	WALK_FORWARD,
	WALK_BACKWARD,
	RUN_FORWARD,
	RUN_BACKWARD,
	CAST,
	AREA_CAST,
	JUMP,
	SMALL_IMPACT,
	DEAD
}

# Move types
enum MoveType {
	REGULAR_ATTACK,
	FORWARD_ATTACK,
	BACKWARD_ATTACK,
	AREA_ATTACK,
	CHARGE_ATTACK
}

# Node references
@onready var camera: Camera3D = $Camera3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var spell_timer: Timer = $SpellTimer

# Character properties
var current_state: AnimState = AnimState.IDLE
var health: float = 100.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var idle_timer: float = 0.0
var idle_threshold: float = 5.0  # Time before playing idle1
var is_casting: bool = false

# Input buffer properties
var input_buffer: Array = []
var input_times: Array = []
var last_direction: String = ""
var direction_change_time: float = 0.0
var is_moving_forward: bool = false
var is_moving_backward: bool = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	spell_timer = Timer.new()
	add_child(spell_timer)
	spell_timer.wait_time = 1.0
	spell_timer.one_shot = true
	spell_timer.connect("timeout", Callable(self, "_on_spell_timer_timeout"))

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
	
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	if health <= 0:
		play_animation(AnimState.DEAD)
		return

	# Add the gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle movement and animations
	handle_movement(delta)
	
	# Update idle animation
	if current_state == AnimState.IDLE:
		idle_timer += delta
		if idle_timer >= idle_threshold:
			play_animation(AnimState.IDLE1)
			idle_timer = 0.0
	else:
		idle_timer = 0.0

	move_and_slide()

func handle_movement(delta):
	# Get input for all four directions
	var input_forward = Input.get_action_strength("Forward") - Input.get_action_strength("Backward")
	var input_right = Input.get_action_strength("Right") - Input.get_action_strength("Left")
	var is_running = Input.is_action_pressed("Sprint")
	
	# Update movement state
	is_moving_forward = input_forward > 0
	is_moving_backward = input_forward < 0
	
	# Track direction changes for charge attacks
	if is_moving_forward and last_direction == "backward":
		direction_change_time = Time.get_ticks_msec() / 1000.0
	elif is_moving_backward and last_direction == "forward":
		direction_change_time = Time.get_ticks_msec() / 1000.0
	
	if is_moving_forward:
		last_direction = "forward"
	elif is_moving_backward:
		last_direction = "backward"
	
	# Handle input buffer for movement
	if Input.is_action_just_pressed("Forward"):
		add_to_input_buffer("W")
	if Input.is_action_just_pressed("Backward"):
		add_to_input_buffer("S")
	if Input.is_action_just_pressed("Left"):
		add_to_input_buffer("A")
	if Input.is_action_just_pressed("Right"):
		add_to_input_buffer("D")
	
	# Get the forward and right directions relative to the camera
	var forward = -camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	
	var right = camera.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	
	# Calculate the movement direction
	var direction = (forward * input_forward + right * input_right)
	direction = direction.normalized()
	
	# Handle jump
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		play_animation(AnimState.JUMP)
	
	# Handle movement animations and velocity
	if direction:
		var speed = RUN_SPEED if is_running else WALK_SPEED
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# Determine movement animation based on forward/backward movement relative to character facing
		var forward_dot = direction.dot(-global_transform.basis.z)
		if forward_dot > 0:
			play_animation(is_running if AnimState.RUN_FORWARD else AnimState.WALK_FORWARD)
		elif forward_dot < 0:
			play_animation(is_running if AnimState.RUN_BACKWARD else AnimState.WALK_BACKWARD)
	else:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
		if current_state != AnimState.IDLE1 and current_state != AnimState.CAST:
			play_animation(AnimState.IDLE)

	# Handle attacks
	if Input.is_action_just_pressed("Attack"):
		handle_attack_input()

func add_to_input_buffer(input: String):
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Remove old inputs
	while input_buffer.size() > 0 and current_time - input_times[0] > INPUT_BUFFER_TIME:
		input_buffer.pop_front()
		input_times.pop_front()
	
	# Add new input
	input_buffer.append(input)
	input_times.append(current_time)
	print("Input Buffer: ", input_buffer)  # Debug log

func handle_attack_input():
	var current_time = Time.get_ticks_msec() / 1000.0
	var move_type = determine_move_type(current_time)
	
	match move_type:
		MoveType.AREA_ATTACK:
			print("Executing Area Attack!")  # Debug log
			execute_area_attack()
		MoveType.CHARGE_ATTACK:
			print("Executing Charge Attack!")  # Debug log
			execute_charge_attack()
		MoveType.FORWARD_ATTACK:
			print("Executing Forward Attack!")  # Debug log
			execute_forward_attack()
		MoveType.BACKWARD_ATTACK:
			print("Executing Backward Attack!")  # Debug log
			execute_backward_attack()
		MoveType.REGULAR_ATTACK:
			print("Executing Regular Attack!")  # Debug log
			execute_regular_attack()

func determine_move_type(current_time: float) -> int:
	# Check for area attack (circular motion)
	if check_circular_motion():
		return MoveType.AREA_ATTACK
	
	# Check for charge attack
	if current_time - direction_change_time < CHARGE_BUFFER_TIME:
		if (last_direction == "forward" and input_buffer.has("S")) or \
		   (last_direction == "backward" and input_buffer.has("W")):
			return MoveType.CHARGE_ATTACK
	
	# Check for directional attacks
	if is_moving_forward:
		return MoveType.FORWARD_ATTACK
	elif is_moving_backward:
		return MoveType.BACKWARD_ATTACK
	
	# Default to regular attack
	return MoveType.REGULAR_ATTACK

func check_circular_motion() -> bool:
	if input_buffer.size() < 4:
		return false
	
	var circular_patterns = [
		["W", "A", "S", "D"],
		["A", "S", "D", "W"],
		["S", "D", "W", "A"],
		["D", "W", "A", "S"]
	]
	
	var last_four = input_buffer.slice(-4)
	for pattern in circular_patterns:
		if arrays_equal(last_four, pattern):
			return true
	
	return false

func arrays_equal(arr1: Array, arr2: Array) -> bool:
	if arr1.size() != arr2.size():
		return false
	
	for i in range(arr1.size()):
		if arr1[i] != arr2[i]:
			return false
	
	return true

func execute_regular_attack():
	is_casting = true
	play_animation(AnimState.CAST)
	spell_timer.start()

func execute_forward_attack():
	is_casting = true
	play_animation(AnimState.CAST)
	spell_timer.start()

func execute_backward_attack():
	is_casting = true
	play_animation(AnimState.CAST)
	spell_timer.start()

func execute_area_attack():
	is_casting = true
	play_animation(AnimState.AREA_CAST)
	spell_timer.start()

func execute_charge_attack():
	is_casting = true
	play_animation(AnimState.CAST)
	spell_timer.start()

func _on_spell_timer_timeout():
	is_casting = false
	
func take_damage(amount: float):
	health -= amount
	play_animation(AnimState.SMALL_IMPACT)
	if health <= 0:
		play_animation(AnimState.DEAD)

func play_animation(anim_state: AnimState):
	if current_state == anim_state:
		return
		
	current_state = anim_state
	match anim_state:
		AnimState.IDLE:
			anim_player.play("idle")
		AnimState.IDLE1:
			anim_player.play("idle1")
		AnimState.WALK_FORWARD:
			anim_player.play("walk_forward")
		AnimState.WALK_BACKWARD:
			anim_player.play("walk_backward")
		AnimState.RUN_FORWARD:
			anim_player.play("run_forward")
		AnimState.RUN_BACKWARD:
			anim_player.play("run_backward")
		AnimState.CAST:
			anim_player.play("cast")
		AnimState.AREA_CAST:
			anim_player.play("area_cast")
		AnimState.JUMP:
			anim_player.play("standing_jump")
		AnimState.SMALL_IMPACT:
			anim_player.play("small_impact")
		AnimState.DEAD:
			anim_player.play("dead")
