extends CharacterBody3D

const WALK_SPEED = 5.0
const RUN_SPEED = 8.0
const SPRINT_SPEED = 12.0
const CROUCH_SPEED = 3.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002
const INPUT_BUFFER_TIME = 1.0
const CHARGE_BUFFER_TIME = 0.8

# Animation states
enum AnimState {
	# Idle states
	IDLE0,
	IDLE1,
	IDLE2,
	
	# Movement states
	WALK_FORWARD,
	WALK_BACKWARD,
	WALK_RIGHT,
	WALK_LEFT,
	RUN_FORWARD,
	RUN_BACKWARD,
	RUN_RIGHT,
	RUN_LEFT,
	SPRINT_FORWARD,
	
	# Turn states
	TURN_RIGHT,
	TURN_LEFT,
	
	# Jump states
	JUMP_STANDING,
	JUMP_RUNNING,
	LANDING_RUNNING,
	LANDING_RUNNING_STANDING,
	
	# Combat states
	CAST0,
	CAST1,
	CAST_AREA,
	CAST_CHARGE0,
	CAST_CHARGE1,
	CAST_CHARGE2,
	CAST_GROUND,
	CAST_UPWARD0,
	
	# Impact states
	IMPACT0,
	IMPACT1,
	IMPACT2,
	DEATH_STANDING,
	
	# Crouch states
	CROUCH,
	CROUCH_IDLE,
	CROUCH_FORWARD,
	CROUCH_BACKWARD,
	CROUCH_LEFT,
	CROUCH_RIGHT,
	UNCROUCH,
	
	# Block states
	BLOCK,
	BLOCK_IDLE,
	BLOCK_STAGGER,
	UNBLOCK
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
@onready var camera: Camera3D = $Armature/Camera3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var spell_timer: Timer = $SpellTimer

# Character properties
var current_state: AnimState = AnimState.IDLE0
var health: float = 100.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var idle_timer: float = 0.0
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
	spell_timer = Timer.new()
	add_child(spell_timer)
	spell_timer.wait_time = 1.0
	spell_timer.one_shot = true
	spell_timer.connect("timeout", Callable(self, "_on_spell_timer_timeout"))
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
		play_animation(AnimState.DEATH_STANDING)
		return

	if !can_move:
		return

	# Add the gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle movement and animations
	handle_movement(delta)
	
	# Update idle animations
	if current_state == AnimState.IDLE0:
		idle_timer += delta
		if idle_timer >= idle_threshold:
			play_random_idle()
			idle_timer = 0.0
	
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
			play_animation(AnimState.JUMP_RUNNING)
		else:
			play_animation(AnimState.JUMP_STANDING)
	
	# Handle landing
	if is_on_floor():
		if current_state == AnimState.JUMP_RUNNING:
			if direction.length() > 0:
				play_animation(AnimState.LANDING_RUNNING)
			else:
				play_animation(AnimState.LANDING_RUNNING_STANDING)
	
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
				play_animation(AnimState.CROUCH_FORWARD)
			elif is_moving_backward:
				play_animation(AnimState.CROUCH_BACKWARD)
			elif input_right > 0:
				play_animation(AnimState.CROUCH_RIGHT)
			else:
				play_animation(AnimState.CROUCH_LEFT)
		else:
			var anim_state
			if is_running:
				if Input.is_action_pressed("Sprint") and is_moving_forward:
					anim_state = AnimState.SPRINT_FORWARD
				elif is_moving_forward:
					anim_state = AnimState.RUN_FORWARD
				elif is_moving_backward:
					anim_state = AnimState.RUN_BACKWARD
				elif input_right > 0:
					anim_state = AnimState.RUN_RIGHT
				else:
					anim_state = AnimState.RUN_LEFT
			else:
				if is_moving_forward:
					anim_state = AnimState.WALK_FORWARD
				elif is_moving_backward:
					anim_state = AnimState.WALK_BACKWARD
				elif input_right > 0:
					anim_state = AnimState.WALK_RIGHT
				else:
					anim_state = AnimState.WALK_LEFT
			play_animation(anim_state)
	else:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
		if is_crouching:
			play_animation(AnimState.CROUCH_IDLE)
		elif is_blocking:
			play_animation(AnimState.BLOCK_IDLE)
		else:
			play_animation(AnimState.IDLE0)

	# Handle attacks
	if Input.is_action_just_pressed("Attack") and !is_blocking:
		handle_attack_input()

func play_random_idle():
	var idles = [AnimState.IDLE1, AnimState.IDLE2]
	play_animation(idles[randi() % idles.size()])

func start_crouch():
	is_crouching = true
	play_animation(AnimState.CROUCH)
	await anim_player.animation_finished
	if is_crouching:  # Check if still crouching after animation
		play_animation(AnimState.CROUCH_IDLE)

func end_crouch():
	play_animation(AnimState.UNCROUCH)
	await anim_player.animation_finished
	is_crouching = false
	play_animation(AnimState.IDLE0)

func start_block():
	is_blocking = true
	can_move = false
	play_animation(AnimState.BLOCK)
	await anim_player.animation_finished
	if is_blocking:  # Check if still blocking after animation
		play_animation(AnimState.BLOCK_IDLE)
		can_move = true

func end_block():
	can_move = false
	play_animation(AnimState.UNBLOCK)
	await anim_player.animation_finished
	is_blocking = false
	can_move = true
	play_animation(AnimState.IDLE0)

func take_damage(amount: float):
	if is_blocking:
		print("Blocked!")
		play_animation(AnimState.BLOCK_STAGGER)
		return
		
	health -= amount
	var impact_anims = [AnimState.IMPACT0, AnimState.IMPACT1, AnimState.IMPACT2]
	play_animation(impact_anims[randi() % impact_anims.size()])
	
	if health <= 0:
		play_animation(AnimState.DEATH_STANDING)

func execute_regular_attack():
	is_casting = true
	play_animation([AnimState.CAST0, AnimState.CAST1][randi() % 2])
	spell_timer.start()

func execute_forward_attack():
	is_casting = true
	play_animation(AnimState.CAST_UPWARD0)
	spell_timer.start()

func execute_backward_attack():
	is_casting = true
	play_animation(AnimState.CAST_GROUND)
	spell_timer.start()

func execute_area_attack():
	is_casting = true
	play_animation(AnimState.CAST_AREA)
	spell_timer.start()

func execute_charge_attack():
	is_casting = true
	var charge_anims = [AnimState.CAST_CHARGE0, AnimState.CAST_CHARGE1, AnimState.CAST_CHARGE2]
	play_animation(charge_anims[randi() % charge_anims.size()])
	spell_timer.start()

func _on_spell_timer_timeout():
	is_casting = false

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

func play_animation(anim_state: AnimState):
	# Don't interrupt non-interruptible animations
	if !can_interrupt_current_animation() and current_state != anim_state:
		return
		
	current_state = anim_state
	match anim_state:
		AnimState.IDLE0:
			anim_player.play("idle0")
			print("playing idle animation")
		AnimState.IDLE1:
			anim_player.play("idle1")
		AnimState.IDLE2:
			anim_player.play("idle2")
		AnimState.WALK_FORWARD:
			anim_player.play("walk_forward")
		AnimState.WALK_BACKWARD:
			anim_player.play("walk_backward")
		AnimState.WALK_RIGHT:
			anim_player.play("walk_right")
		AnimState.WALK_LEFT:
			anim_player.play("walk_left")
		AnimState.RUN_FORWARD:
			anim_player.play("run_forward")
		AnimState.RUN_BACKWARD:
			anim_player.play("run_backward")
		AnimState.RUN_RIGHT:
			anim_player.play("run_right")
		AnimState.RUN_LEFT:
			anim_player.play("run_left")
		AnimState.SPRINT_FORWARD:
			anim_player.play("sprint_forward")
		AnimState.JUMP_STANDING:
			anim_player.play("jump_standing")
		AnimState.JUMP_RUNNING:
			anim_player.play("jump_running")
		AnimState.LANDING_RUNNING:
			anim_player.play("landing_running")
		AnimState.LANDING_RUNNING_STANDING:
			anim_player.play("landing_running_standing")
		AnimState.CAST0:
			anim_player.play("cast0")
		AnimState.CAST1:
			anim_player.play("cast1")
		AnimState.CAST_AREA:
			anim_player.play("cast_area")
		AnimState.CAST_CHARGE0:
			anim_player.play("cast_charge0")
		AnimState.CAST_CHARGE1:
			anim_player.play("cast_charge1")
		AnimState.CAST_CHARGE2:
			anim_player.play("cast_charge2")
		AnimState.CAST_GROUND:
			anim_player.play("cast_ground")
		AnimState.CAST_UPWARD0:
			anim_player.play("cast_upward0")
		AnimState.IMPACT0:
			anim_player.play("impact0")
		AnimState.IMPACT1:
			anim_player.play("impact1")
		AnimState.IMPACT2:
			anim_player.play("impact2")
		AnimState.DEATH_STANDING:
			anim_player.play("death_standing")
		AnimState.CROUCH:
			anim_player.play("crouch")
		AnimState.CROUCH_IDLE:
			anim_player.play("crouch_idle")
		AnimState.CROUCH_FORWARD:
			anim_player.play("crouch_forward")
		AnimState.CROUCH_BACKWARD:
			anim_player.play("crouch_backward")
		AnimState.CROUCH_LEFT:
			anim_player.play("crouch_left")
		AnimState.CROUCH_RIGHT:
			anim_player.play("crouch_right")
		AnimState.UNCROUCH:
			anim_player.play("uncrouch")
		AnimState.BLOCK:
			anim_player.play("block")
		AnimState.BLOCK_IDLE:
			anim_player.play("block_idle")
		AnimState.BLOCK_STAGGER:
			anim_player.play("block_stagger")
		AnimState.UNBLOCK:
			anim_player.play("unblock")

func can_interrupt_current_animation() -> bool:
	# List of animations that can be interrupted
	var interruptible_states = [
		AnimState.IDLE0,
		AnimState.IDLE1,
		AnimState.IDLE2,
		AnimState.WALK_FORWARD,
		AnimState.WALK_BACKWARD,
		AnimState.WALK_RIGHT,
		AnimState.WALK_LEFT,
		AnimState.RUN_FORWARD,
		AnimState.RUN_BACKWARD,
		AnimState.RUN_RIGHT,
		AnimState.RUN_LEFT,
		AnimState.SPRINT_FORWARD,
		AnimState.CROUCH_IDLE,
		AnimState.CROUCH_FORWARD,
		AnimState.CROUCH_BACKWARD,
		AnimState.CROUCH_LEFT,
		AnimState.CROUCH_RIGHT,
		AnimState.BLOCK_IDLE
	]
	
	return current_state in interruptible_states

func _on_animation_player_animation_finished(anim_name: String):
	# Handle transitions back to idle state for non-interruptible animations
	match anim_name:
		"idle0", "idle1":
			anim_player.play("idle0")
		
		# Jump animations
		"jump_standing", "jump_running":
			if is_on_floor():
				play_animation(AnimState.IDLE0)
		"landing_running", "landing_running_standing":
			play_animation(AnimState.IDLE0)
		
		# Combat animations
		"cast0", "cast1", "cast_area", "cast_charge0", "cast_charge1", \
		"cast_charge2", "cast_ground", "cast_upward0":
			is_casting = false
			anim_player.play("idle0")
		
		# Impact animations
		"impact0", "impact1", "impact2":
			if health > 0:  # Only transition to idle if not dead
				play_animation(AnimState.IDLE0)
		
		# Crouch transitions
		"crouch":
			if is_crouching:
				play_animation(AnimState.CROUCH_IDLE)
		"uncrouch":
			if !is_crouching:
				play_animation(AnimState.IDLE0)
		
		# Block transitions
		"block":
			if is_blocking:
				play_animation(AnimState.BLOCK_IDLE)
		"unblock":
			if !is_blocking:
				play_animation(AnimState.IDLE0)
		"block_stagger":
			if is_blocking:
				play_animation(AnimState.BLOCK_IDLE)
			else:
				play_animation(AnimState.IDLE0)
		
		# Death animation (no transition)
		"death_standing":
			pass  # Stay in death animation

	# Reset idle timer when transitioning back to idle
	if anim_name != "idle0" and anim_name != "idle1" and anim_name != "idle2":
		idle_timer = 0.0
