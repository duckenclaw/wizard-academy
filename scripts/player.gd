extends CharacterBody3D

const WALK_SPEED = 5.0
const RUN_SPEED = 8.0
const SPRINT_SPEED = 12.0
const CROUCH_SPEED = 3.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002
const INPUT_BUFFER_TIME = 1.0
const CHARGE_BUFFER_TIME = 0.8

# Move types
enum MoveType {
	REGULAR_ATTACK,
	FORWARD_ATTACK,
	BACKWARD_ATTACK,
	AREA_ATTACK,
	CHARGE_ATTACK
}

# Node references
@onready var camera: Camera3D = $Armature/Camera3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer

# Character properties
var current_animation: String = "idle0"
var health: float = 100.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var idle_threshold: float = 5.0
var is_casting: bool = false
var is_running: bool = false
var is_crouching: bool = false
var is_blocking: bool = false
var can_move: bool = true

# Input buffer properties
var input_buffer: Array = []
var input_times: Array = []
var last_direction: String = ""
var direction_change_time: float = 0.0
var is_moving_forward: bool = false
var is_moving_backward: bool = false
var last_mouse_x: float = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	anim_player.animation_finished.connect(Callable(self, "_on_animation_player_animation_finished"))

func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mouse_delta_x = event.relative.x
		
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
	
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Track movement inputs for input buffer
	if event.is_action_pressed("Forward"):
		add_to_input_buffer("W")
		last_direction = "forward"
		direction_change_time = Time.get_ticks_msec() / 1000.0
	elif event.is_action_pressed("Backward"):
		add_to_input_buffer("S")
		last_direction = "backward"
		direction_change_time = Time.get_ticks_msec() / 1000.0
	elif event.is_action_pressed("Left"):
		add_to_input_buffer("A")
		last_direction = "left"
		direction_change_time = Time.get_ticks_msec() / 1000.0
	elif event.is_action_pressed("Right"):
		add_to_input_buffer("D")
		last_direction = "right"
		direction_change_time = Time.get_ticks_msec() / 1000.0
	
	# Handle crouch
	if event.is_action_pressed("Crouch") and !is_blocking:
		start_crouch()
	elif event.is_action_released("Crouch") and is_crouching:
		end_crouch()
	
	# Handle block
	if event.is_action_pressed("AlternateAttack") and !is_crouching:
		start_block()
	elif event.is_action_released("AlternateAttack") and is_blocking:
		end_block()
	
	# Handle run toggle
	if event.is_action_pressed("ToggleRun"):
		is_running = !is_running

func _physics_process(delta):
	if health <= 0:
		play_animation("death_standing")
		return

	if !can_move:
		return

	# Add the gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle movement and animations
	handle_movement(delta)
	
	move_and_slide()

func handle_movement(delta):
	if !can_move or is_blocking:
		return

	var input_forward = Input.get_action_strength("Forward") - Input.get_action_strength("Backward")
	var input_right = Input.get_action_strength("Right") - Input.get_action_strength("Left")
	
	# Update movement state
	is_moving_forward = input_forward > 0
	is_moving_backward = input_forward < 0
	
	# Get movement directions
	var forward = -camera.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	
	var right = camera.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	
	# Calculate movement direction
	var direction = (forward * input_forward + right * input_right).normalized()
	
	# Handle jumping
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		if direction.length() > 0:
			play_animation("jump_running")
		else:
			play_animation("jump_standing")
	
	# Handle landing
	if is_on_floor():
		if current_animation == "jump_running":
			if direction.length() > 0:
				play_animation("landing_running")
			else:
				play_animation("landing_running_standing")
	
	# Handle movement animations and velocity
	if direction:
		var speed = WALK_SPEED
		if is_crouching:
			speed = CROUCH_SPEED
		elif is_running:
			speed = RUN_SPEED
			if Input.is_action_pressed("Sprint") and is_moving_forward:
				speed = SPRINT_SPEED
		
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# Determine movement animation
		if is_crouching:
			if is_moving_forward:
				play_animation("crouch_forward")
			elif is_moving_backward:
				play_animation("crouch_backward")
			elif input_right > 0:
				play_animation("crouch_right")
			else:
				play_animation("crouch_left")
		else:
			var anim_name
			if is_running:
				if Input.is_action_pressed("Sprint") and is_moving_forward:
					anim_name = "sprint_forward"
				elif is_moving_forward:
					anim_name = "run_forward"
				elif is_moving_backward:
					anim_name = "run_backward"
				elif input_right > 0:
					anim_name = "run_right"
				else:
					anim_name = "run_left"
			else:
				if is_moving_forward:
					anim_name = "walk_forward"
				elif is_moving_backward:
					anim_name = "walk_backward"
				elif input_right > 0:
					anim_name = "walk_right"
				else:
					anim_name = "walk_left"
			play_animation(anim_name)
	else:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
		if is_crouching:
			play_animation("crouch_idle")
		elif is_blocking:
			play_animation("block_idle")
		elif !is_casting:
			play_animation("idle0")

	# Handle attacks
	if Input.is_action_just_pressed("Attack") and !is_blocking:
		handle_attack_input()

func start_crouch():
	is_crouching = true
	can_move = false
	play_animation("crouch")

func end_crouch():
	play_animation("uncrouch")

func start_block():
	print("blocking")
	can_move = false
	play_animation("block")

func end_block():
	print("unblocking")
	play_animation("unblock")

func take_damage(amount: float):
	if is_blocking:
		print("Blocked!")
		play_animation("block_stagger")
		return
		
	health -= amount
	can_move = false
	play_animation("impact0")
	
	if health <= 0:
		play_animation("death_standing")

func execute_regular_attack():
	is_casting = true
	can_move = false
	play_animation("cast0")

func execute_forward_attack():
	is_casting = true
	can_move = false
	play_animation("cast_upward0")

func execute_backward_attack():
	is_casting = true
	can_move = false
	play_animation("cast_ground")

func execute_area_attack():
	is_casting = true
	can_move = false
	play_animation("cast_area")

func execute_charge_attack():
	is_casting = true
	can_move = false
	play_animation("cast_charge0")


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

func play_animation(anim_name: String):
	# Don't interrupt non-interruptible animations
		
	current_animation = anim_name
	anim_player.play(anim_name)

func can_interrupt_current_animation() -> bool:
	# List of animations that can be interrupted
	var interruptible_animations = [
		"idle0", "idle1", "idle2",
		"walk_forward", "walk_backward", "walk_right", "walk_left",
		"run_forward", "run_backward", "run_right", "run_left", "sprint_forward",
		"crouch_idle", "crouch_forward", "crouch_backward", "crouch_left", "crouch_right",
		"block_idle"
	]
	
	return current_animation in interruptible_animations

func _on_animation_player_animation_finished(anim_name: String):
	print(anim_name)
	
	# Handle transitions back to idle state for non-interruptible animations
	match anim_name:
		"idle0", "idle1":
			anim_player.play("idle0")
		
		# Jump animations
		"jump_standing", "jump_running":
			if is_on_floor():
				play_animation("idle0")
		"landing_running", "landing_running_standing":
			play_animation("idle0")
		
		# Combat animations
		"cast0", "cast_area", "cast_charge0", "cast_ground", "cast_upward0":
			is_casting = false
			can_move = true
			print("playing idle animation")
			play_animation("idle0")
			
		
		# Impact animations
		"impact0":
			if health > 0:  # Only transition to idle if not dead
				play_animation("idle0")
				return
			can_move = true
		
		# Crouch transitions
		"crouch":
			if is_crouching:
				play_animation("crouch_idle")
				can_move = true
		"uncrouch":
			is_crouching = false
			can_move = true
			play_animation("idle0")
		
		# Block transitions
		"block":
			is_blocking = true
			play_animation("block_idle")
		"unblock":
			print("unblock ended")
			is_blocking = false
			can_move = true
			play_animation("idle0")
		"block_stagger":
			can_move = true
			if is_blocking:
				play_animation("block_idle")
			else:
				play_animation("idle0")
		
		# Death animation (no transition)
		"death_standing":
			pass  # Stay in death animation
