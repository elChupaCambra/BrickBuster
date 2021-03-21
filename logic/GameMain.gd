extends Node2D

# Declare member variables here. Examples:
# var a = 2
# var b = "text"
var paused = false
# These variables are used to keep track of what stage of the round we are in
# This is used to decide input state and acceptance
var drag_enabled = false
var mouse_in_controlarea = false
# launched is used to differentiate between states when there are no live balls
# i.e. idling vs just after all balls have returned to bottom of screen
var launched = false
var round_in_progress = false
var live_balls = []
var live_destroyables = []
var score = 0
var ammo = 1
var first_click_position = Vector2(0,0)
var rng = RandomNumberGenerator.new()

onready var score_label = $MetaArea/MarginContainer/HBoxContainer/ScoreLabel
onready var ball_scene = load("res://scenes/Ball.tscn")
onready var brick_scene = load("res://scenes/Brick.tscn")
onready var slanted_brick_scene = load("res://scenes/SlantedBrick.tscn")
onready var specials_scene = load("res://scenes/Specials.tscn")
onready var ball = ball_scene.instance()
onready var line = $LaunchLine
onready var wait = $LaunchTimer
onready var columns = [
	$Column0,
	$Column1,
	$Column2,
	$Column3,
	$Column4,
	$Column5,
	$Column6
]

func launch_balls(direction, amount):
	for i in amount:
		var next_ball = ball_scene.instance()
		add_child(next_ball)
		next_ball.launch(direction)
		live_balls.append(next_ball)
		wait.start()
		yield(wait, "timeout")

func new_destroyable(health, vert_position, column, type):
	var next_destroyable
	if "Brick" in type:
		if type == "Brick":
			next_destroyable = brick_scene.instance()
		elif type == "Slanted Brick":
			next_destroyable = slanted_brick_scene.instance()
			rng.randomize()
			next_destroyable.rotation_degrees = rng.randi_range(0,3) * 90
		next_destroyable.health = health
		next_destroyable.max_possible_health = health
	elif "Special" in type:
		next_destroyable = specials_scene.instance()
		if type == "Add-Ball Special":
			next_destroyable.mode = "add-ball"
		next_destroyable.connect("special_area_entered", self, "specialarea_signal_received")
	
	next_destroyable.hor_position = columns.find(column)
	next_destroyable.current_vert_position = vert_position
	add_child(next_destroyable)
	# We set it at 0 and then add 1 to vert position to get swanky movement down
	next_destroyable.set_position(column.get_point_position(vert_position))
	next_destroyable.current_vert_position += 1
	live_destroyables.append(next_destroyable)
	

func new_destroyable_line(health, vert_position = 0):
	var free_columns = columns.duplicate()
	for column in columns:
		rng.randomize()
		if rng.randi_range(0,2) > 0 && free_columns.size() > 1: 
			free_columns.erase(column)
			if rng.randi_range(0,3) == 3:
				new_destroyable(health, vert_position, column, "Slanted Brick")
			else:
				new_destroyable(health, vert_position, column, "Brick")
	
	rng.randomize()
	var random_free_column = rng.randi_range(0, (free_columns.size() - 1))
	var column_for_add_ball_special = free_columns[random_free_column]
	new_destroyable(health, vert_position, column_for_add_ball_special, "Add-Ball Special")
	free_columns.erase(column_for_add_ball_special)
	print(free_columns)

func pause_signal_received():
	paused = !paused
	get_tree().paused = paused

func restart_signal_received():
	get_tree().reload_current_scene()

func specialarea_signal_received(type):
	if type == "add-ball":
		ammo += 1

# Called when the node enters the scene tree for the first time.
func _ready():
	$MetaArea.connect("pause_menu_toggled", self, "pause_signal_received")
	$MetaArea.pause_mode = Node.PAUSE_MODE_PROCESS
	$MetaArea.connect("restart_button_clicked", self, "restart_signal_received")
	line.add_point(Vector2(0,0), 0)
	line.add_point(Vector2(0,0), 1)
	add_child(ball)
	wait.wait_time = 0.1
	rng.randomize()
	self.new_destroyable_line(score + 1)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	score_label.text = String(score)
	
	var ball_center = ball.position
	var mouse_position = get_global_mouse_position()
	var line_direction = first_click_position - mouse_position
	
	for live_ball in live_balls:
		if !is_instance_valid(live_ball):
			live_balls.erase(live_ball)
	
	# "click" is defined in input map
	if Input.is_action_just_pressed("click") && mouse_in_controlarea && !round_in_progress:
		first_click_position = get_global_mouse_position()
		drag_enabled = true
	
	# Line drawing and touch place responsibilities
	update() # Updates _draw func
	line.visible = false
	if drag_enabled && !round_in_progress:
		line.visible = true
		line.set_point_position(0, ball_center)
		line.set_point_position(1, line_direction.normalized()*100000)
	
	# Launch handling
	if Input.is_action_just_released("click") && !round_in_progress && drag_enabled: 
		drag_enabled = false
		self.launch_balls(line_direction.normalized(), ammo)
		print(line_direction.normalized())
		launched = true
	
	# Round progress checking section
	var inv_live_destroyables = live_destroyables.duplicate()
	# We have an inverted array so blocks don't get superimposed when newer blocks moved down
	#inv_live_destroyables.invert()
	if !live_balls.empty():
		round_in_progress = true
	elif launched:
		score += 1
		launched = false
		round_in_progress = false
		for live_destroyable in inv_live_destroyables:
			if !is_instance_valid(live_destroyable):
				live_destroyables.erase(live_destroyable)
			else:
				live_destroyable.current_vert_position += 1
				if "Brick" in live_destroyable.name:
					live_destroyable.max_possible_health += 1
				if live_destroyable.current_vert_position == 8:
					get_tree().reload_current_scene()
		self.new_destroyable_line(score + 1)
	else:
		var num_incorrect_brick_position = 0
		for live_destroyable in inv_live_destroyables:
			var destination = columns[live_destroyable.hor_position].get_point_position(live_destroyable.current_vert_position)
			if live_destroyable.position != destination:
				num_incorrect_brick_position += 1
				var reposition = live_destroyable.position - destination
				# Snap blocks into position when they are imperceptibly close
				# Otherwise they will never reach the intended position
				if reposition.y > -2:
					live_destroyable.position = destination
				else:
					var reposition_velocity = reposition * 6 * delta
					live_destroyable.position -= reposition_velocity
		if num_incorrect_brick_position == 0:
			round_in_progress = false
		else:
			round_in_progress= true

func _draw():
	if drag_enabled && !round_in_progress:
		draw_circle(first_click_position, 25, ColorN("black", 0.5))

func _on_ControlArea_mouse_entered():
	mouse_in_controlarea = true

func _on_ControlArea_mouse_exited():
	mouse_in_controlarea = false