extends Node3D

const ROAD_LENGTH := 3200.0
const ROAD_WIDTH := 13.0
const SEGMENT_LENGTH := 12.0
const START_Z := 25.0
const SAVE_PATH := "user://mountain_driver_3d.cfg"

enum GameState { MENU, PLAYING, PAUSED, RESULT }

var state := GameState.MENU
var difficulty := "Medium"
var weather := "Clear"
var player: CharacterBody3D
var car_visual: Node3D
var camera: Camera3D
var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var speed := 0.0
var steering := 0.0
var fuel := 100.0
var damage := 0.0
var coins_run := 0
var total_coins := 0
var distance := 0.0
var checkpoint_z := START_Z
var crash_cooldown := 0.0
var camera_mode := 0
var mission_target := 3
var mission_progress := 0
var mission_text := "Collect 3 fuel cans"
var traffic: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var checkpoints: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var bad_zones: Array[Vector2] = []
var wheel_nodes: Array[Node3D] = []
var front_wheel_nodes: Array[Node3D] = []
var touch := {"gas": false, "brake": false, "left": false, "right": false}
var upgrades := {"engine": 0, "tyres": 0, "tank": 0, "suspension": 0}
var rng := RandomNumberGenerator.new()

var current_gear := "D"
var camera_snapped := false
var camera_shake := 0.0
var prev_speed := 0.0
var tail_lights: MeshInstance3D
var head_lights: MeshInstance3D
var head_spotlight: SpotLight3D
var garage_panel: Panel
var pause_panel: Panel
var floating_texts: Array[Dictionary] = []

var ui: CanvasLayer
var menu_root: Control
var hud_root: Control
var result_panel: Panel
var result_title: Label
var result_detail: Label
var speed_label: Label
var status_label: Label
var coin_label: Label
var mission_label: Label
var fuel_bar: ProgressBar
var damage_bar: ProgressBar
var progress_bar: ProgressBar
var weather_label: Label
var engine_audio: AudioStreamPlayer
var wind_audio: AudioStreamPlayer
var menu_music_audio: AudioStreamPlayer
var music_audio: AudioStreamPlayer
var horn_audio: AudioStreamPlayer
var crash_audio: AudioStreamPlayer
var pickup_audio: AudioStreamPlayer
var checkpoint_audio: AudioStreamPlayer
var repair_audio: AudioStreamPlayer
var audio_muted := false
var firebase_analytics: Object = null

var modes := {
	"Easy": {"max_speed": 36.0, "fuel": 0.36, "traffic": 11, "damage": 0.62},
	"Medium": {"max_speed": 43.0, "fuel": 0.52, "traffic": 17, "damage": 1.0},
	"Hard": {"max_speed": 50.0, "fuel": 0.72, "traffic": 24, "damage": 1.38}
}


func _ready() -> void:
	rng.seed = 25062026
	load_progress()
	build_environment()
	build_road_and_scenery()
	build_player()
	build_ui()
	build_audio()
	
	if Engine.has_singleton("FirebaseAnalyticsBridge"):
		firebase_analytics = Engine.get_singleton("FirebaseAnalyticsBridge")
		log_firebase_event("app_start")
		
	show_menu()


func build_environment() -> void:
	world_environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#79add0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#bfd7e1")
	env.ambient_light_energy = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	env.tonemap_white = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.28
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color("#c9dde5")
	env.fog_density = 0.002
	env.fog_sky_affect = 0.45
	world_environment.environment = env
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_color = Color("#ffe2ab")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)

	add_box(self, Vector3(0, -11, ROAD_LENGTH * 0.5), Vector3(340, 14, ROAD_LENGTH + 500), Color("#385e47"))


func build_road_and_scenery() -> void:
	var root := Node3D.new()
	root.name = "MountainWorld"
	add_child(root)

	for zone_start in range(360, int(ROAD_LENGTH - 200), 470):
		bad_zones.append(Vector2(zone_start, zone_start + rng.randi_range(70, 145)))

	for index in range(int(ROAD_LENGTH / SEGMENT_LENGTH)):
		var z := float(index) * SEGMENT_LENGTH
		var next_z := z + SEGMENT_LENGTH
		var a := Vector3(road_x(z), road_y(z), z)
		var b := Vector3(road_x(next_z), road_y(next_z), next_z)
		var delta := b - a
		var yaw := atan2(delta.x, delta.z)
		var pitch := -atan2(delta.y, Vector2(delta.x, delta.z).length())
		var broken := is_bad_road(z)
		var piece := add_box(
			root,
			(a + b) * 0.5 - Vector3(0, 0.4, 0),
			Vector3(ROAD_WIDTH, 0.75, delta.length() + 0.6),
			Color("#69584d") if broken else Color("#32363b")
		)
		piece.rotation = Vector3(pitch, yaw, 0)

		if not broken:
			add_road_mark(root, (a + b) * 0.5, delta.length(), pitch, yaw)
		else:
			add_broken_road_details(root, (a + b) * 0.5, pitch, yaw)

		if index % 3 == 0:
			add_roadside_terrain(root, z, -1.0)
			add_roadside_terrain(root, z, 1.0)
		if index % 4 == 0:
			add_guardrail(root, a, yaw, -1.0)
			if index % 12 != 0:
				add_guardrail(root, a, yaw, 1.0)
		if index % 18 == 0 and index > 2:
			add_road_sign(root, z)

	build_bridge(root, 1420.0)
	build_finish(root)


func add_road_mark(parent: Node3D, center: Vector3, length: float, pitch: float, yaw: float) -> void:
	var line := add_box(parent, center + Vector3(0, 0.04, 0), Vector3(0.18, 0.05, length * 0.56), Color("#f7d968"))
	line.rotation = Vector3(pitch, yaw, 0)
	for side in [-1.0, 1.0]:
		var edge := add_box(parent, center + Vector3(cos(yaw) * side * 5.75, 0.04, -sin(yaw) * side * 5.75), Vector3(0.12, 0.04, length), Color(1, 1, 1, 0.75))
		edge.rotation = Vector3(pitch, yaw, 0)


func add_broken_road_details(parent: Node3D, center: Vector3, pitch: float, yaw: float) -> void:
	for index in range(3):
		var crack := add_box(parent, center + Vector3(rng.randf_range(-4.1, 4.1), 0.06, rng.randf_range(-4.0, 4.0)), Vector3(rng.randf_range(0.4, 1.5), 0.08, rng.randf_range(1.6, 4.5)), Color("#17191b"))
		crack.rotation = Vector3(pitch, yaw + rng.randf_range(-0.6, 0.6), 0)


func add_roadside_terrain(parent: Node3D, z: float, side: float) -> void:
	var center_x := road_x(z)
	var height := rng.randf_range(12.0, 38.0)
	var mountain := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = rng.randf_range(0.4, 2.0)
	cone.bottom_radius = rng.randf_range(8.0, 17.0)
	cone.height = height
	cone.radial_segments = 8
	mountain.mesh = cone
	mountain.position = Vector3(center_x + side * rng.randf_range(28.0, 54.0), road_y(z) - 4.0 + height * 0.5, z + rng.randf_range(-7, 7))
	mountain.rotation_degrees = Vector3(rng.randf_range(-5, 5), rng.randf_range(0, 90), rng.randf_range(-4, 4))
	mountain.material_override = make_material([Color("#465149"), Color("#5c594f"), Color("#3f4b44")].pick_random(), 0.96)
	parent.add_child(mountain)
	for tree_index in range(rng.randi_range(1, 3)):
		add_tree(parent, Vector3(center_x + side * rng.randf_range(15.0, 28.0), road_y(z) - 1.0, z + rng.randf_range(-10, 10)))


func add_tree(parent: Node3D, position: Vector3) -> void:
	add_cylinder(parent, position + Vector3(0, 1.8, 0), 0.24, 3.6, Color("#68442d"))
	for layer in range(3):
		var foliage := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 2.2 - layer * 0.35
		cone.height = 3.2
		foliage.mesh = cone
		foliage.position = position + Vector3(0, 3.5 + layer * 1.7, 0)
		foliage.material_override = make_material(Color("#174d35").lightened(layer * 0.035), 1.0)
		parent.add_child(foliage)


func add_guardrail(parent: Node3D, center: Vector3, yaw: float, side: float) -> void:
	var offset := Vector3(cos(yaw) * side * ROAD_WIDTH * 0.51, 0.72, -sin(yaw) * side * ROAD_WIDTH * 0.51)
	var rail := add_box(parent, center + offset, Vector3(0.16, 0.38, SEGMENT_LENGTH * 0.9), Color("#d6dadd"))
	rail.rotation.y = yaw
	for post_offset in [-4.5, 4.5]:
		var post := add_box(parent, center + offset + Vector3(sin(yaw) * post_offset, -0.45, cos(yaw) * post_offset), Vector3(0.2, 1.25, 0.2), Color("#9aa0a5"))
		post.rotation.y = yaw


func add_road_sign(parent: Node3D, z: float) -> void:
	var yaw := road_yaw(z)
	var side := -1.0 if int(z / SEGMENT_LENGTH) % 2 == 0 else 1.0
	var base := Vector3(road_x(z) + cos(yaw) * side * 8.0, road_y(z), z - sin(yaw) * side * 8.0)
	add_box(parent, base + Vector3(0, 1.7, 0), Vector3(0.16, 3.4, 0.16), Color("#bfc5c8"))
	var board := add_box(parent, base + Vector3(0, 3.25, 0), Vector3(2.2, 1.1, 0.16), Color("#f2b53d"))
	board.rotation.y = yaw


func build_bridge(parent: Node3D, z: float) -> void:
	var x := road_x(z)
	var y := road_y(z)
	for side in [-1.0, 1.0]:
		add_box(parent, Vector3(x + side * 6.2, y + 1.1, z), Vector3(0.4, 2.2, 52), Color("#aeb4b8"))


func build_finish(parent: Node3D) -> void:
	var z := ROAD_LENGTH - 55.0
	var x := road_x(z)
	var y := road_y(z)
	add_box(parent, Vector3(x - 6.2, y + 3.2, z), Vector3(0.5, 6.4, 0.5), Color.WHITE)
	add_box(parent, Vector3(x + 6.2, y + 3.2, z), Vector3(0.5, 6.4, 0.5), Color.WHITE)
	add_box(parent, Vector3(x, y + 6.1, z), Vector3(12.8, 0.7, 0.7), Color("#ff9a31"))


func build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "PlayerSUV"
	add_child(player)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.25, 1.25, 4.45)
	collision.shape = box
	player.add_child(collision)
	
	front_wheel_nodes.clear()
	wheel_nodes.clear()
	
	car_visual = create_vehicle(Color("#f38b2d"), "suv", true)
	player.add_child(car_visual)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 69
	camera.top_level = true
	player.add_child(camera)
	reset_player()


func build_audio() -> void:
	engine_audio = make_audio_player("res://assets/audio/engine-loop.wav", -6.0, true)
	wind_audio = make_audio_player("res://assets/audio/mountain-wind.wav", -14.0, true)
	menu_music_audio = make_audio_player("res://assets/audio/alexgrohl-energetic-action-sport-500409.mp3", -4.0, true)
	music_audio = make_audio_player("res://assets/audio/nastelbom-driving-439500.mp3", -6.0, true)
	if not menu_music_audio.stream:
		menu_music_audio.stream = load("res://assets/audio/driving-music.ogg")
	if not music_audio.stream:
		music_audio.stream = load("res://assets/audio/driving-music.ogg")
	horn_audio = make_audio_player("res://assets/audio/horn.wav", -2.0)
	crash_audio = make_audio_player("res://assets/audio/crash.wav", -1.0)
	pickup_audio = make_audio_player("res://assets/audio/pickup.wav", -2.0)
	checkpoint_audio = make_audio_player("res://assets/audio/checkpoint.wav", -2.0)
	repair_audio = make_audio_player("res://assets/audio/repair.wav", -2.0)

	set_audio_loop(menu_music_audio.stream)
	set_audio_loop(music_audio.stream)
	wind_audio.play()
	menu_music_audio.play()


func set_audio_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


func make_audio_player(path: String, volume_db: float, loop := false) -> AudioStreamPlayer:
	var player_node := AudioStreamPlayer.new()
	player_node.stream = load(path)
	player_node.volume_db = volume_db
	if loop:
		player_node.finished.connect(func() -> void:
			if player_node == wind_audio:
				player_node.play()
			elif player_node == menu_music_audio:
				if state == GameState.MENU:
					player_node.play()
			elif player_node == music_audio or player_node == engine_audio:
				if state == GameState.PLAYING or state == GameState.PAUSED:
					player_node.play()
		)
	add_child(player_node)
	return player_node


func create_vehicle(color: Color, vehicle_type: String, is_player := false) -> Node3D:
	var root := Node3D.new()
	var length := 4.5
	var width := 2.2
	var height := 0.75
	if vehicle_type == "truck":
		length = 6.6
		width = 2.35
		height = 1.2
	add_box(root, Vector3(0, 0.18, 0), Vector3(width, height, length), color)
	add_box(root, Vector3(0, 0.92, -0.45), Vector3(width * 0.82, 0.85, length * 0.46), color.lightened(0.06))
	add_box(root, Vector3(0, 1.02, -0.62), Vector3(width * 0.7, 0.45, length * 0.28), Color("#8ec9df"))
	if vehicle_type == "truck":
		add_box(root, Vector3(0, 1.0, 1.45), Vector3(width * 0.94, 1.85, 3.0), color.darkened(0.12))
	for x in [-width * 0.53, width * 0.53]:
		for z in [-length * 0.32, length * 0.32]:
			var wheel_holder := Node3D.new()
			wheel_holder.position = Vector3(x, -0.3, z)
			root.add_child(wheel_holder)
			var wheel := add_cylinder(wheel_holder, Vector3.ZERO, 0.43, 0.36, Color("#101214"))
			wheel.rotation_degrees.z = 90
			if is_player:
				wheel_nodes.append(wheel_holder)
				if z > 0:
					front_wheel_nodes.append(wheel_holder)
	if is_player:
		var front_lights := add_box(root, Vector3(0, 0.58, length * 0.51), Vector3(width * 0.72, 0.18, 0.11), Color("#fff0ae"))
		var rear_lights := add_box(root, Vector3(0, 0.44, -length * 0.51), Vector3(width * 0.68, 0.16, 0.1), Color("#e94d45"))
		head_lights = front_lights
		tail_lights = rear_lights
		
		var light := SpotLight3D.new()
		light.position = Vector3(0, 0.58, length * 0.55)
		light.rotation_degrees = Vector3(0, 0, 0)
		light.light_color = Color("#fff4d0")
		light.light_energy = 0.0
		light.spot_range = 35.0
		light.spot_angle = 38.0
		light.shadow_enabled = true
		root.add_child(light)
		head_spotlight = light
	return root


func populate_run() -> void:
	clear_dynamic_nodes()
	var settings: Dictionary = modes[difficulty]
	var count: int = settings.traffic
	for index in range(count):
		var z := 210.0 + index * (ROAD_LENGTH - 400.0) / count + rng.randf_range(-35, 45)
		var direction := -1.0 if index % 5 == 0 else 1.0
		var lane := -3.1 if direction > 0 else 3.1
		var kind := "truck" if index % 6 == 0 else "car"
		var body := CharacterBody3D.new()
		body.add_child(create_vehicle([Color("#d94b50"), Color("#3f9dcf"), Color("#e6bc45"), Color("#eceff0"), Color("#6d73c9")].pick_random(), kind))
		add_child(body)
		traffic.append({"node": body, "z": z, "lane": lane, "direction": direction, "speed": rng.randf_range(11.0, 24.0), "target_speed": rng.randf_range(15.0, 26.0), "kind": kind, "hit": false})

	for index in range(10):
		var z := 280.0 + index * 280.0
		var type := "fuel" if index % 3 != 2 else "repair"
		create_pickup(z, type, [-3.0, 3.0].pick_random())
	for index in range(18):
		create_pickup(190.0 + index * 155.0, "coin", [-2.6, 0.0, 2.6].pick_random())

	for index in range(15):
		var z := 330.0 + index * 180.0 + rng.randf_range(-40, 40)
		create_hazard(z, ["rock", "pothole", "barrier", "mud"].pick_random(), [-3.0, 0.0, 3.0].pick_random())

	for z in [650.0, 1250.0, 1900.0, 2550.0]:
		create_checkpoint(z)


func clear_dynamic_nodes() -> void:
	for list in [traffic, pickups, hazards, checkpoints, effects]:
		for entry in list:
			var node: Node = entry.get("node")
			if is_instance_valid(node):
				node.queue_free()
		list.clear()


func create_pickup(z: float, type: String, lane: float) -> void:
	var node := Node3D.new()
	node.position = Vector3(road_x(z) + lane, road_y(z) + 1.25, z)
	if type == "fuel":
		add_box(node, Vector3.ZERO, Vector3(0.85, 1.25, 0.62), Color("#48d77e"))
		add_box(node, Vector3(0.18, 0.74, 0), Vector3(0.35, 0.2, 0.45), Color("#18232a"))
	elif type == "repair":
		add_box(node, Vector3.ZERO, Vector3(1.05, 1.05, 0.45), Color("#f0f3f4"))
		add_box(node, Vector3.ZERO, Vector3(0.23, 0.75, 0.52), Color("#e64f4f"))
		add_box(node, Vector3.ZERO, Vector3(0.75, 0.23, 0.52), Color("#e64f4f"))
	else:
		add_cylinder(node, Vector3.ZERO, 0.48, 0.14, Color("#ffd34f")).rotation_degrees.x = 90
	add_child(node)
	pickups.append({"node": node, "type": type, "taken": false})


func create_hazard(z: float, type: String, lane: float) -> void:
	var node := Node3D.new()
	node.position = Vector3(road_x(z) + lane, road_y(z) + 0.18, z)
	if type == "rock":
		var rock := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.95
		sphere.height = 1.55
		rock.mesh = sphere
		rock.scale = Vector3(1.2, 0.8, 1.0)
		rock.material_override = make_material(Color("#5b5650"), 1.0)
		node.add_child(rock)
	elif type == "pothole":
		add_cylinder(node, Vector3(0, -0.05, 0), 0.95, 0.08, Color("#111416"))
	elif type == "barrier":
		add_box(node, Vector3(0, 0.55, 0), Vector3(2.8, 1.1, 0.42), Color("#e75a42"))
		for stripe in [-0.7, 0.7]:
			add_box(node, Vector3(stripe, 0.55, -0.23), Vector3(0.32, 0.85, 0.04), Color.WHITE).rotation_degrees.z = 25
	else:
		add_box(node, Vector3(0, 0.02, 0), Vector3(3.2, 0.06, 5.4), Color("#5e432d"))
	add_child(node)
	hazards.append({"node": node, "type": type, "hit": false})


func create_checkpoint(z: float) -> void:
	var node := Node3D.new()
	node.position = Vector3(road_x(z), road_y(z), z)
	add_box(node, Vector3(-6.0, 2.8, 0), Vector3(0.35, 5.6, 0.35), Color("#62c9ff"))
	add_box(node, Vector3(6.0, 2.8, 0), Vector3(0.35, 5.6, 0.35), Color("#62c9ff"))
	add_box(node, Vector3(0, 5.45, 0), Vector3(12.3, 0.45, 0.45), Color("#62c9ff"))
	add_child(node)
	checkpoints.append({"node": node, "z": z, "passed": false})


func start_game(mode: String) -> void:
	difficulty = mode
	state = GameState.PLAYING
	speed = 0.0
	fuel = 100.0 + upgrades.tank * 14.0
	damage = 0.0
	coins_run = 0
	mission_progress = 0
	checkpoint_z = START_Z
	crash_cooldown = 0.0
	camera_mode = 0
	current_gear = "D"
	update_gear_ui()
	reset_player()
	populate_run()
	apply_weather(["Clear", "Fog", "Rain"].pick_random())
	show_game_ui()
	menu_music_audio.stop()
	music_audio.volume_db = -6.0
	if not music_audio.playing:
		music_audio.play()
	if not engine_audio.playing:
		engine_audio.play()
	log_firebase_event("game_start", {"difficulty": mode})


func reset_player() -> void:
	player.position = Vector3(road_x(checkpoint_z), road_y(checkpoint_z) + 1.08, checkpoint_z)
	player.rotation = Vector3.ZERO
	car_visual.rotation = Vector3.ZERO
	speed = 0.0
	camera_snapped = false
	update_camera_transform()


func _physics_process(delta: float) -> void:
	update_effects(delta)
	if state != GameState.PLAYING:
		return
	var settings: Dictionary = modes[difficulty]
	var gas: bool = Input.is_action_pressed("accelerate") or bool(touch.gas)
	var brake: bool = Input.is_action_pressed("brake") or bool(touch.brake)
	var steer_input: float = Input.get_axis("steer_left", "steer_right")
	if touch.left: steer_input -= 1.0
	if touch.right: steer_input += 1.0
	steer_input = clampf(steer_input, -1.0, 1.0)

	var engine_bonus: float = 1.0 + int(upgrades.engine) * 0.12
	var grip: float = 1.0 + int(upgrades.tyres) * 0.14
	var suspension: float = 1.0 + int(upgrades.suspension) * 0.18
	var max_speed: float = settings.max_speed * engine_bonus
	engine_audio.pitch_scale = lerpf(0.72, 1.85, clampf(absf(speed) / max_speed, 0.0, 1.0))
	engine_audio.volume_db = lerpf(-8.0, -2.0, clampf(absf(speed) / max_speed, 0.0, 1.0))
	wind_audio.volume_db = lerpf(-20.0, -10.0, clampf(absf(speed) / max_speed, 0.0, 1.0))
	if Input.is_action_just_pressed("horn"):
		play_horn()
	steering = move_toward(steering, steer_input, delta * (4.6 * grip))
	
	if current_gear == "D":
		if gas and fuel > 0:
			speed += 14.5 * engine_bonus * delta
			fuel -= settings.fuel * delta
		if brake:
			speed = move_toward(speed, 0.0, 25.0 * delta)
	else: # Reverse
		if gas and fuel > 0:
			speed -= 10.0 * engine_bonus * delta
			fuel -= settings.fuel * delta
		if brake:
			speed = move_toward(speed, 0.0, 25.0 * delta)

	if Input.is_action_pressed("handbrake"):
		speed = move_toward(speed, 0.0, 38.0 * delta)
		steering *= 1.18
	speed -= road_slope(player.position.z) * 5.2 * delta
	speed = move_toward(speed, 0.0, 2.2 * delta)
	
	# Hill-hold / prevent rolling backwards in Drive and forward in Reverse when no gas/brake is active
	if not gas and not brake:
		if current_gear == "D" and speed < 0.0 and crash_cooldown <= 0.0:
			speed = 0.0
		elif current_gear == "R" and speed > 0.0 and crash_cooldown <= 0.0:
			speed = 0.0
			
	speed = clampf(speed, -12.0, max_speed)

	var broken := is_bad_road(player.position.z)
	if broken:
		camera_shake = maxf(camera_shake, 0.06)
	
	# The chase camera faces +Z, which mirrors world X on screen.
	# Invert lateral movement so the visible controls match left and right.
	var lateral_speed: float = -steering * (4.4 + absf(speed) * 0.075) * grip
	if broken:
		speed = move_toward(speed, 0.0, 3.8 * delta / suspension)
	player.position.z += speed * delta
	player.position.x += lateral_speed * delta

	var center := road_x(player.position.z)
	var offset := player.position.x - center
	var driveable_half_width := ROAD_WIDTH * 0.41
	if absf(offset) > driveable_half_width:
		speed = move_toward(speed, 0.0, 15.0 * delta)
		damage = minf(100.0, damage + 1.4 * delta / suspension)
		spawn_dust(Color("#b28b61"))
		# Push the vehicle back onto the asphalt instead of allowing it to
		# travel through roadside terrain or below curved road segments.
		player.position.x = move_toward(
			player.position.x,
			center + signf(offset) * driveable_half_width,
			delta * 9.0
		)
	player.position.x = clampf(
		player.position.x,
		center - driveable_half_width,
		center + driveable_half_width
	)
	var road_surface_y := road_y(player.position.z) + 1.16
	player.position.y = lerpf(player.position.y, road_surface_y, delta * 14.0 * suspension)
	player.position.y = maxf(player.position.y, road_surface_y - 0.04)
	player.rotation.y = lerp_angle(player.rotation.y, road_yaw(player.position.z) - steering * 0.17, delta * 6.0)
	if is_instance_valid(tail_lights):
		if brake:
			tail_lights.material_override = make_material(Color("#ff3b30"), 0.1, 4.5)
		else:
			tail_lights.material_override = make_material(Color("#e94d45"), 0.5, 0.5)
			
	if is_instance_valid(head_lights) and is_instance_valid(head_spotlight):
		if weather == "Rain" or weather == "Fog":
			head_spotlight.light_energy = 4.2
			head_lights.material_override = make_material(Color("#fffaa0"), 0.1, 3.5)
		else:
			head_spotlight.light_energy = 0.0
			head_lights.material_override = make_material(Color("#fff0ae"))

	var acceleration := (speed - prev_speed) / delta
	prev_speed = speed
	var target_chassis_pitch := -acceleration * 0.008
	target_chassis_pitch = clampf(target_chassis_pitch, -0.15, 0.12)
	var target_chassis_roll := -steering * clampf(absf(speed) / 22.0, 0.0, 1.2) * 0.16

	car_visual.rotation.z = lerpf(car_visual.rotation.z, target_chassis_roll, delta * 5.0)
	car_visual.rotation.x = lerpf(car_visual.rotation.x, -road_slope(player.position.z) * 0.7 + target_chassis_pitch, delta * 6.0)
	car_visual.position.y = sin(Time.get_ticks_msec() * (0.04 if broken else 0.014)) * (0.08 if broken else 0.018) / suspension
	
	spawn_exhaust_smoke(delta)
	
	for wheel in front_wheel_nodes:
		wheel.rotation.y = steering * 0.45
	for wheel in wheel_nodes:
		wheel.rotation.x += speed * delta * 2.325

	update_traffic(delta)
	check_interactions()
	distance = maxf(0.0, player.position.z - START_Z)
	crash_cooldown = maxf(0.0, crash_cooldown - delta)
	update_hud()

	if player.position.z >= ROAD_LENGTH - 60.0:
		finish_run(true, "DESTINATION REACHED")
	elif damage >= 100.0:
		finish_run(false, "VEHICLE DESTROYED")
	elif fuel <= 0.0 and absf(speed) < 0.5:
		finish_run(false, "OUT OF FUEL")


func update_traffic(delta: float) -> void:
	for entry in traffic:
		var body: CharacterBody3D = entry.node
		if not is_instance_valid(body):
			continue
		var desired: float = entry.target_speed
		var gap := body.position.z - player.position.z
		if entry.direction > 0 and gap > 0 and gap < 18 and absf(body.position.x - player.position.x) < 2.4:
			desired *= 0.55
			if gap < 10:
				entry.lane = 3.1 if entry.lane < 0 else -3.1
		entry.speed = move_toward(entry.speed, desired, delta * 4.0)
		entry.z += entry.speed * entry.direction * delta
		if entry.z < 80:
			entry.z = ROAD_LENGTH - 100
		elif entry.z > ROAD_LENGTH - 60:
			entry.z = 100
		body.position = Vector3(road_x(entry.z) + entry.lane, road_y(entry.z) + 0.93, entry.z)
		body.rotation.y = road_yaw(entry.z) + (PI if entry.direction < 0 else 0.0)
		body.rotation.x = -road_slope(entry.z) * entry.direction * 0.8


func check_interactions() -> void:
	for pickup in pickups:
		if pickup.taken:
			continue
		var node: Node3D = pickup.node
		node.rotation.y += 0.035
		node.position.y = road_y(node.position.z) + 1.25 + sin(Time.get_ticks_msec() * 0.004 + node.position.z) * 0.15
		if player.global_position.distance_to(node.global_position) < 2.3:
			pickup.taken = true
			node.visible = false
			if pickup.type == "fuel":
				fuel = minf(100.0 + upgrades.tank * 14.0, fuel + 35.0)
				mission_progress += 1
				pickup_audio.play()
				spawn_floating_text("+35 FUEL", Color("#48d77e"), node.global_position)
				log_firebase_event("player_pickup", {"type": "fuel"})
			elif pickup.type == "repair":
				damage = maxf(0.0, damage - 38.0)
				repair_audio.play()
				spawn_floating_text("REPAIRED!", Color("#f0f3f4"), node.global_position)
				log_firebase_event("player_pickup", {"type": "repair"})
			else:
				coins_run += 10
				pickup_audio.play()
				spawn_floating_text("+10 COINS", Color("#ffd34f"), node.global_position)
				log_firebase_event("player_pickup", {"type": "coin"})

	for hazard in hazards:
		if hazard.hit:
			continue
		var node: Node3D = hazard.node
		if player.global_position.distance_to(node.global_position) < 2.4:
			hazard.hit = true
			var hit_damage: float = {"rock": 24.0, "barrier": 18.0, "pothole": 10.0, "mud": 4.0}[hazard.type]
			var final_damage: float = hit_damage / (1.0 + upgrades.suspension * 0.2)
			damage = minf(100.0, damage + final_damage)
			speed *= 0.38 if hazard.type != "mud" else 0.68
			spawn_impact_effect()
			crash_audio.play()
			camera_shake = 0.35 if hazard.type != "mud" else 0.12
			spawn_floating_text("-%d HP" % int(final_damage), Color("#e64f4f"), player.global_position + Vector3(0, 1.8, 0))
			log_firebase_event("player_damage", {"type": hazard.type, "hp_lost": int(final_damage)})

	for entry in traffic:
		var other: Node3D = entry.node
		if crash_cooldown <= 0.0 and player.global_position.distance_to(other.global_position) < (3.5 if entry.kind == "truck" else 3.0):
			var impact := maxf(10.0, absf(speed - entry.speed * entry.direction))
			var damage_multiplier: float = modes[difficulty].damage
			var final_damage: float = impact * damage_multiplier
			damage = minf(100.0, damage + final_damage)
			speed *= -0.24
			player.position.x += signf(player.position.x - other.position.x) * 1.8
			crash_cooldown = 1.15
			spawn_impact_effect()
			crash_audio.play()
			camera_shake = clampf(impact * 0.04, 0.25, 0.75)
			spawn_floating_text("-%d HP" % int(final_damage), Color("#e64f4f"), player.global_position + Vector3(0, 1.8, 0))
			log_firebase_event("player_damage", {"type": "traffic", "hp_lost": int(final_damage)})

	for checkpoint in checkpoints:
		if not checkpoint.passed and player.position.z >= checkpoint.z:
			checkpoint.passed = true
			checkpoint_z = checkpoint.z + 8.0
			coins_run += 35
			status_label.text = "CHECKPOINT SAVED"
			checkpoint_audio.play()
			spawn_floating_text("CHECKPOINT!", Color("#62c9ff"), player.global_position + Vector3(0, 1.8, 0))
			log_firebase_event("player_checkpoint", {"id": int(checkpoint.z)})


func spawn_impact_effect() -> void:
	for index in range(9):
		var spark := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.08
		sphere.height = 0.16
		spark.mesh = sphere
		spark.position = player.position + Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.1), rng.randf_range(-1, 1))
		spark.material_override = make_material(Color("#ffb13b"), 0.25, 3.0)
		add_child(spark)
		effects.append({"node": spark, "velocity": Vector3(rng.randf_range(-4, 4), rng.randf_range(2, 7), rng.randf_range(-4, 4)), "life": 0.65})


func spawn_dust(color: Color) -> void:
	if rng.randf() > 0.18:
		return
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.5
	puff.mesh = sphere
	puff.position = player.position - Vector3(0, 0.4, 1.8)
	puff.material_override = make_material(Color(color, 0.6), 1.0)
	add_child(puff)
	effects.append({"node": puff, "velocity": Vector3(rng.randf_range(-0.5, 0.5), 0.65, -1.0), "life": 0.8})


func update_effects(delta: float) -> void:
	for effect in effects:
		if not is_instance_valid(effect.node):
			continue
		effect.node.position += effect.velocity * delta
		effect.life -= delta
		
		if effect.get("is_smoke", false):
			effect.node.scale += Vector3.ONE * delta * 1.6
			var mat := effect.node.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = clampf(effect.life / 0.75 * 0.46, 0.0, 1.0)
		else:
			effect.node.scale += Vector3.ONE * delta * 0.3
			
	for effect in effects.filter(func(item: Dictionary) -> bool: return item.life <= 0.0):
		if is_instance_valid(effect.node):
			effect.node.queue_free()
	effects = effects.filter(func(item: Dictionary) -> bool: return item.life > 0.0)


func finish_run(won: bool, title: String) -> void:
	state = GameState.RESULT
	var final_coins := coins_run + (150 if won else 0)
	total_coins += final_coins
	if mission_progress >= mission_target:
		total_coins += 120
	save_progress()
	result_title.text = title
	result_detail.text = "Distance %dm   Coins +%d\nMission %d/%d   Press R to retry" % [int(distance), final_coins, mission_progress, mission_target]
	result_panel.visible = true
	engine_audio.stop()
	music_audio.volume_db = -4.0
	log_firebase_event("game_finish", {"won": won, "distance": int(distance), "coins": final_coins})


func recover_car() -> void:
	if state != GameState.PLAYING:
		return
	damage = minf(100.0, damage + 8.0)
	reset_player()
	status_label.text = "RECOVERED AT CHECKPOINT"
	repair_audio.play()


func play_horn() -> void:
	if state == GameState.PLAYING:
		horn_audio.play()


func toggle_audio() -> void:
	audio_muted = not audio_muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), audio_muted)
	var btn := hud_root.find_child("AudioButton", true, false) as Button
	if btn:
		btn.text = "🔇 OFF" if audio_muted else "🔊 ON"
		var style := btn.get_theme_stylebox("normal") as StyleBoxFlat
		if style:
			style.bg_color = Color(0.3, 0.1, 0.1, 0.6) if audio_muted else Color(0.1, 0.15, 0.2, 0.6)


func cycle_camera() -> void:
	camera_mode = (camera_mode + 1) % 3
	camera_snapped = false
	update_camera_transform()


func update_camera_transform() -> void:
	match camera_mode:
		0:
			camera.position = Vector3(0, 5.5, -12.5)
			camera.rotation_degrees = Vector3(-12, 180, 0)
			camera.fov = 69
		1:
			camera.position = Vector3(0, 2.05, -0.4)
			camera.rotation_degrees = Vector3(-3, 180, 0)
			camera.fov = 76
		2:
			camera.position = Vector3(0, 9.5, -17.0)
			camera.rotation_degrees = Vector3(-22, 180, 0)
			camera.fov = 64


func _process(delta: float) -> void:
	if state == GameState.PLAYING:
		update_camera_smooth(delta)
	update_floating_texts(delta)


func update_camera_smooth(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return
	
	var player_transform := player.global_transform
	var target_pos: Vector3
	var look_target: Vector3
	var fov_target: float
	
	match camera_mode:
		0: # Close Chase
			var offset := player_transform.basis * Vector3(0, 5.5, -12.5)
			target_pos = player.global_position + offset
			look_target = player.global_position + player_transform.basis * Vector3(0, 1.2, 2.0)
			fov_target = 69.0
		1: # Hood Cam
			target_pos = player.global_position + player_transform.basis * Vector3(0, 2.05, -0.4)
			look_target = target_pos + player_transform.basis * Vector3(0, -0.05, 1.0)
			fov_target = 76.0
		2: # Far Chase
			var offset := player_transform.basis * Vector3(0, 9.5, -17.0)
			target_pos = player.global_position + offset
			look_target = player.global_position + player_transform.basis * Vector3(0, 1.5, 3.0)
			fov_target = 64.0
			
	if not camera_snapped:
		camera.global_position = target_pos
		camera.look_at(look_target, Vector3.UP)
		camera.fov = fov_target
		camera_snapped = true
	else:
		if camera_mode == 1: # Hood cam stays locked to the car
			camera.global_position = target_pos
			camera.look_at(look_target, Vector3.UP)
		else:
			camera.global_position = camera.global_position.lerp(target_pos, delta * (8.0 if camera_mode == 0 else 5.0))
			camera.look_at(look_target, Vector3.UP)
		camera.fov = lerpf(camera.fov, fov_target, delta * 5.0)

	# Apply screenshake
	if camera_shake > 0.0:
		camera.global_position += Vector3(
			rng.randf_range(-camera_shake, camera_shake),
			rng.randf_range(-camera_shake, camera_shake),
			rng.randf_range(-camera_shake, camera_shake)
		)
		camera_shake = move_toward(camera_shake, 0.0, delta * 2.0)


func apply_weather(value: String) -> void:
	weather = value
	weather_label.text = weather.to_upper()
	var env := world_environment.environment
	if weather == "Fog":
		env.fog_density = 0.009
		env.background_color = Color("#9aaeb5")
		sun.light_energy = 0.75
	elif weather == "Rain":
		env.fog_density = 0.004
		env.background_color = Color("#526b79")
		env.ambient_light_energy = 0.45
		sun.light_energy = 0.55
	else:
		env.fog_density = 0.002
		env.background_color = Color("#79add0")
		env.ambient_light_energy = 0.78
		sun.light_energy = 1.45


func is_bad_road(z: float) -> bool:
	for zone in bad_zones:
		if z >= zone.x and z <= zone.y:
			return true
	return false


func road_x(z: float) -> float:
	return sin(z * 0.0067) * 17.0 + sin(z * 0.0022 + 0.5) * 25.0


func road_y(z: float) -> float:
	return 3.0 + z * 0.021 + sin(z * 0.0105) * 7.5 + sin(z * 0.0037 + 1.1) * 11.0


func road_yaw(z: float) -> float:
	return atan2(road_x(z + 2.0) - road_x(z - 2.0), 4.0)


func road_slope(z: float) -> float:
	return (road_y(z + 2.0) - road_y(z - 2.0)) / 4.0


func build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu_root)
	var art := TextureRect.new()
	art.texture = load("res://assets/menu-key-art.png")
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	menu_root.add_child(art)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.035, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(shade)
	var panel := make_panel(menu_root, Vector2(72, 85), Vector2(500, 555), Color(0.025, 0.055, 0.075, 0.92))
	var logo := make_label(panel, "MOUNTAIN\nDRIVER 3D", Vector2(42, 35), 52)
	logo.add_theme_color_override("font_color", Color("#ffae50"))
	make_label(panel, "CONQUER THE IMPOSSIBLE ROAD", Vector2(45, 165), 17)
	make_button(panel, "EASY DRIVE", Vector2(42, 215), Vector2(416, 62), func() -> void: start_game("Easy"), Color("#4fd783"))
	make_button(panel, "MOUNTAIN TOUR", Vector2(42, 291), Vector2(416, 62), func() -> void: start_game("Medium"), Color("#ff9b31"))
	make_button(panel, "DEATH ROAD", Vector2(42, 367), Vector2(416, 62), func() -> void: start_game("Hard"), Color("#eb5353"))
	make_button(panel, "GARAGE / UPGRADES", Vector2(42, 451), Vector2(416, 52), toggle_garage, Color("#4b6575"))
	var wallet := make_label(panel, "COINS  %d" % total_coins, Vector2(43, 520), 19)
	wallet.name = "Wallet"
	var credit := make_label(menu_root, "Music: AlexGrohl, NastelBom (Pixabay) • Kevin MacLeod (CC BY 3.0 fallback)", Vector2(620, 678), 13)
	credit.modulate = Color(1, 1, 1, 0.72)

	garage_panel = make_panel(menu_root, Vector2(620, 85), Vector2(580, 555), Color(0.025, 0.055, 0.075, 0.95))
	var g_title := make_label(garage_panel, "GARAGE & UPGRADES", Vector2(45, 30), 28)
	g_title.add_theme_color_override("font_color", Color("#ffae50"))
	
	var y_offset := 105.0
	for key in ["engine", "tyres", "tank", "suspension"]:
		var category_name: String = key.to_upper()
		if key == "tyres": category_name = "TYRES (GRIP)"
		elif key == "tank": category_name = "FUEL TANK"
		
		make_label(garage_panel, category_name, Vector2(45, y_offset), 16)
		var bar := make_bar(garage_panel, Vector2(45, y_offset + 32), Color("#ff9b31"), Vector2(250, 14))
		bar.name = key + "_bar"
		var price_lbl := make_label(garage_panel, "MAX LEVEL", Vector2(310, y_offset + 5), 15)
		price_lbl.name = key + "_price"
		var btn := make_button(garage_panel, "UPGRADE", Vector2(420, y_offset - 5), Vector2(115, 45), func() -> void: buy_upgrade(key), Color("#4fd783"))
		btn.name = key + "_button"
		y_offset += 95.0
		
	make_button(garage_panel, "CLOSE", Vector2(215, 485), Vector2(150, 48), func() -> void: garage_panel.visible = false, Color("#526b78"))
	garage_panel.visible = false

	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(hud_root)

	# Consolidated Premium Glass Dashboard Top Bar
	var dashboard = make_panel(hud_root, Vector2(15, 15), Vector2(1250, 100), Color(0.02, 0.05, 0.08, 0.8))
	var dash_style = dashboard.get_theme_stylebox("panel") as StyleBoxFlat
	if dash_style:
		dash_style.corner_radius_top_left = 18
		dash_style.corner_radius_top_right = 18
		dash_style.corner_radius_bottom_left = 18
		dash_style.corner_radius_bottom_right = 18
		dash_style.border_width_left = 1
		dash_style.border_width_top = 1
		dash_style.border_width_right = 1
		dash_style.border_width_bottom = 1
		dash_style.border_color = Color(1, 1, 1, 0.18)

	# Dashboard Info
	speed_label = make_label(dashboard, "000 KM/H", Vector2(25, 20), 32)
	speed_label.add_theme_color_override("font_color", Color("#8ec9df"))
	
	# Fuel Section
	make_label(dashboard, "FUEL", Vector2(240, 21), 14)
	fuel_bar = make_bar(dashboard, Vector2(320, 24), Color("#4fd783"), Vector2(180, 14))
	
	# Damage Section
	make_label(dashboard, "DAMAGE", Vector2(240, 55), 14)
	damage_bar = make_bar(dashboard, Vector2(320, 58), Color("#eb5353"), Vector2(180, 14))

	# Mission and Progress Section
	make_label(dashboard, "ROUTE PROGRESS", Vector2(535, 15), 13)
	progress_bar = make_bar(dashboard, Vector2(535, 38), Color("#ff9b31"), Vector2(260, 10))
	mission_label = make_label(dashboard, mission_text, Vector2(535, 58), 15)

	# Stats Section
	coin_label = make_label(dashboard, "COINS 0", Vector2(835, 22), 22)
	coin_label.add_theme_color_override("font_color", Color("#ffd34f"))
	weather_label = make_label(dashboard, "CLEAR", Vector2(835, 58), 16)
	
	# Status Display
	status_label = make_label(dashboard, "MEDIUM", Vector2(1040, 36), 20)

	# Top Right Mini Game Buttons (CAM, RESET, AUDIO)
	var audio_btn := make_button(hud_root, "🔊 ON", Vector2(950, 130), Vector2(90, 42), toggle_audio, Color(0.1, 0.15, 0.2, 0.6))
	audio_btn.name = "AudioButton"
	make_button(hud_root, "🎥 CAM", Vector2(1060, 130), Vector2(90, 42), cycle_camera, Color(0.1, 0.15, 0.2, 0.6))
	make_button(hud_root, "🔄 RESET", Vector2(1170, 130), Vector2(90, 42), recover_car, Color(0.2, 0.1, 0.1, 0.6))

	# Left side: Premium Circular Steering Touch Buttons
	make_touch_button(hud_root, "◀", Vector2(30, 560), Vector2(90, 90), "left", 45)
	make_touch_button(hud_root, "▶", Vector2(140, 560), Vector2(90, 90), "right", 45)
	make_button(hud_root, "📢", Vector2(250, 560), Vector2(90, 90), play_horn, Color(0.18, 0.15, 0.1, 0.72), 45)

	# Right side: Premium Shift Gate (D / R Buttons) and Car Pedals (GAS / BRAKE)
	var gear_bezel := make_panel(hud_root, Vector2(905, 530), Vector2(110, 130), Color(0.02, 0.04, 0.06, 0.8))
	var gear_bezel_style := gear_bezel.get_theme_stylebox("panel") as StyleBoxFlat
	if gear_bezel_style:
		gear_bezel_style.corner_radius_top_left = 16
		gear_bezel_style.corner_radius_top_right = 16
		gear_bezel_style.corner_radius_bottom_left = 16
		gear_bezel_style.corner_radius_bottom_right = 16
		gear_bezel_style.border_color = Color(1, 1, 1, 0.15)
		
	var btn_d := make_button(gear_bezel, "D", Vector2(10, 10), Vector2(90, 50), func() -> void: set_gear("D"), Color(0.04, 0.08, 0.1, 0.72), 8)
	btn_d.name = "GearButtonD"
	var btn_r := make_button(gear_bezel, "R", Vector2(10, 70), Vector2(90, 50), func() -> void: set_gear("R"), Color(0.04, 0.08, 0.1, 0.72), 8)
	btn_r.name = "GearButtonR"

	var brake_btn := make_touch_button(hud_root, "BRAKE", Vector2(1040, 540), Vector2(95, 120), "brake", 18)
	var brake_style := brake_btn.get_theme_stylebox("normal") as StyleBoxFlat
	if brake_style:
		brake_style.border_color = Color("#eb5353")
		brake_style.border_width_left = 2
		brake_style.border_width_top = 2
		brake_style.border_width_right = 2
		brake_style.border_width_bottom = 2
		
	var gas_btn := make_touch_button(hud_root, "GAS", Vector2(1160, 510), Vector2(85, 150), "gas", 18)
	var gas_style := gas_btn.get_theme_stylebox("normal") as StyleBoxFlat
	if gas_style:
		gas_style.border_color = Color("#4fd783")
		gas_style.border_width_left = 2
		gas_style.border_width_top = 2
		gas_style.border_width_right = 2
		gas_style.border_width_bottom = 2

	pause_panel = make_panel(hud_root, Vector2(440, 180), Vector2(400, 360), Color(0.02, 0.04, 0.06, 0.96))
	var p_title := make_label(pause_panel, "GAME PAUSED", Vector2(78, 45), 32)
	p_title.add_theme_color_override("font_color", Color("#ffae50"))
	make_button(pause_panel, "RESUME GAME", Vector2(75, 125), Vector2(250, 52), resume_game, Color("#3f5969"))
	make_button(pause_panel, "RETRY MISSION", Vector2(75, 195), Vector2(250, 52), func() -> void: start_game(difficulty), Color("#83642f"))
	make_button(pause_panel, "QUIT TO MENU", Vector2(75, 265), Vector2(250, 52), show_menu, Color("#6a4e49"))
	pause_panel.visible = false

	result_panel = make_panel(hud_root, Vector2(385, 190), Vector2(510, 310), Color(0.025, 0.055, 0.075, 0.95))
	result_title = make_label(result_panel, "RESULT", Vector2(55, 48), 38)
	result_detail = make_label(result_panel, "", Vector2(55, 115), 20)
	make_button(result_panel, "DRIVE AGAIN", Vector2(55, 210), Vector2(190, 58), func() -> void: start_game(difficulty), Color("#ff9b31"))
	make_button(result_panel, "MAIN MENU", Vector2(265, 210), Vector2(190, 58), show_menu, Color("#526b78"))
	result_panel.visible = false


func show_menu() -> void:
	state = GameState.MENU
	menu_root.visible = true
	hud_root.visible = false
	if is_instance_valid(pause_panel):
		pause_panel.visible = false
	if is_instance_valid(garage_panel):
		garage_panel.visible = false
	var wallet := menu_root.find_child("Wallet", true, false) as Label
	if wallet:
		wallet.text = "COINS  %d" % total_coins
	if is_instance_valid(engine_audio):
		engine_audio.stop()
	if is_instance_valid(menu_music_audio) and not menu_music_audio.playing:
		menu_music_audio.play()
	if is_instance_valid(music_audio):
		music_audio.stop()


func show_game_ui() -> void:
	menu_root.visible = false
	hud_root.visible = true
	result_panel.visible = false
	if is_instance_valid(pause_panel):
		pause_panel.visible = false
	if is_instance_valid(garage_panel):
		garage_panel.visible = false
	status_label.text = difficulty.to_upper()


func toggle_garage() -> void:
	if is_instance_valid(garage_panel):
		garage_panel.visible = not garage_panel.visible
		if garage_panel.visible:
			update_garage_ui()


func buy_upgrade(key: String) -> void:
	var costs: Array[int] = [120, 220, 360]
	var level: int = upgrades[key]
	if level < 3 and total_coins >= costs[level]:
		total_coins -= costs[level]
		upgrades[key] = level + 1
		save_progress()
		update_garage_ui()
		var wallet := menu_root.find_child("Wallet", true, false) as Label
		if wallet:
			wallet.text = "COINS  %d" % total_coins
		repair_audio.play()
		log_firebase_event("garage_upgrade", {"item": key, "level": upgrades[key]})


func update_garage_ui() -> void:
	if not is_instance_valid(garage_panel):
		return
	var costs: Array[int] = [120, 220, 360]
	for key in ["engine", "tyres", "tank", "suspension"]:
		var level: int = upgrades[key]
		var bar := garage_panel.find_child(key + "_bar", true, false) as ProgressBar
		if bar:
			bar.max_value = 3.0
			bar.value = float(level)
		var price_lbl := garage_panel.find_child(key + "_price", true, false) as Label
		var btn := garage_panel.find_child(key + "_button", true, false) as Button
		if price_lbl and btn:
			if level >= 3:
				price_lbl.text = "MAX LEVEL"
				btn.disabled = true
				btn.text = "MAXED"
			else:
				var cost: int = costs[level]
				price_lbl.text = "%d COINS" % cost
				btn.disabled = total_coins < cost
				btn.text = "BUY"


func resume_game() -> void:
	state = GameState.PLAYING
	status_label.text = difficulty.to_upper()
	if is_instance_valid(pause_panel):
		pause_panel.visible = false
	if is_instance_valid(engine_audio) and not engine_audio.playing:
		engine_audio.play()


func update_hud() -> void:
	speed_label.text = "%03d KM/H [%s]" % [int(absf(speed) * 3.6), current_gear]
	coin_label.text = "COINS %d" % coins_run
	mission_label.text = "%s  %d/%d" % [mission_text, mission_progress, mission_target]
	fuel_bar.max_value = 100.0 + upgrades.tank * 14.0
	fuel_bar.value = fuel
	damage_bar.value = damage
	progress_bar.value = distance / (ROAD_LENGTH - START_Z) * 100.0


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if state == GameState.PLAYING:
		if event.keycode == KEY_ESCAPE:
			state = GameState.PAUSED
			status_label.text = "PAUSED"
			if is_instance_valid(pause_panel):
				pause_panel.visible = true
			if is_instance_valid(engine_audio):
				engine_audio.stop()
		elif event.keycode == KEY_C:
			cycle_camera()
		elif event.keycode == KEY_R:
			recover_car()
		elif event.keycode == KEY_M:
			toggle_audio()
		elif event.keycode == KEY_SHIFT or event.keycode == KEY_G:
			toggle_gear()
	elif state == GameState.PAUSED and event.keycode == KEY_ESCAPE:
		resume_game()
	elif state == GameState.RESULT:
		if event.keycode == KEY_R:
			start_game(difficulty)
		elif event.keycode == KEY_M:
			show_menu()


func set_gear(new_gear: String) -> void:
	if state != GameState.PLAYING:
		return
	current_gear = new_gear
	update_gear_ui()


func toggle_gear() -> void:
	if current_gear == "D":
		set_gear("R")
	else:
		set_gear("D")


func update_gear_ui() -> void:
	var btn_d := hud_root.find_child("GearButtonD", true, false) as Button
	var btn_r := hud_root.find_child("GearButtonR", true, false) as Button
	if btn_d and btn_r:
		var style_d := btn_d.get_theme_stylebox("normal") as StyleBoxFlat
		var style_r := btn_r.get_theme_stylebox("normal") as StyleBoxFlat
		if current_gear == "D":
			btn_d.modulate = Color(1.0, 1.0, 1.0, 1.0)
			btn_r.modulate = Color(1.0, 1.0, 1.0, 0.45)
			if style_d:
				style_d.bg_color = Color("#4fd783")
				style_d.border_color = Color("#4fd783").lightened(0.2)
			if style_r:
				style_r.bg_color = Color(0.04, 0.08, 0.1, 0.72)
				style_r.border_color = Color(1, 1, 1, 0.25)
		else:
			btn_d.modulate = Color(1.0, 1.0, 1.0, 0.45)
			btn_r.modulate = Color(1.0, 1.0, 1.0, 1.0)
			if style_d:
				style_d.bg_color = Color(0.04, 0.08, 0.1, 0.72)
				style_d.border_color = Color(1, 1, 1, 0.25)
			if style_r:
				style_r.bg_color = Color("#eb5353")
				style_r.border_color = Color("#eb5353").lightened(0.2)


func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "coins", total_coins)
	for key in upgrades:
		config.set_value("upgrades", key, upgrades[key])
	config.save(SAVE_PATH)


func load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	total_coins = int(config.get_value("player", "coins", 0))
	for key in upgrades:
		upgrades[key] = int(config.get_value("upgrades", key, 0))


func make_panel(parent: Control, position: Vector2, size: Vector2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = position
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.22)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func make_label(parent: Control, text: String, position: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.88))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label


func make_button(parent: Control, text: String, position: Vector2, size: Vector2, callback: Callable, color: Color, corner_radius := 12) -> Button:
	var button := Button.new()
	button.text = text
	button.position = position
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.corner_radius_top_left = corner_radius
	normal.corner_radius_top_right = corner_radius
	normal.corner_radius_bottom_left = corner_radius
	normal.corner_radius_bottom_right = corner_radius
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(1, 1, 1, 0.25)
	normal.shadow_color = Color(0, 0, 0, 0.25)
	normal.shadow_size = 4
	
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.12)
	hover.border_color = Color(1, 1, 1, 0.5)
	
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.12)
	pressed.border_color = Color(1, 1, 1, 0.8)
	
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.2, 0.2, 0.2, 0.5)
	disabled.border_color = Color(0.4, 0.4, 0.4, 0.3)
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
	button.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.6))
	
	if callback.is_valid():
		button.pressed.connect(callback)
		
	parent.add_child(button)
	return button


func make_touch_button(parent: Control, text: String, position: Vector2, size: Vector2, action: String, corner_radius := 12) -> Button:
	var button := make_button(parent, text, position, size, func() -> void: pass, Color(0.04, 0.08, 0.1, 0.72), corner_radius)
	button.button_down.connect(func() -> void: touch[action] = true)
	button.button_up.connect(func() -> void: touch[action] = false)
	return button


func make_bar(parent: Control, position: Vector2, fill: Color, size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = position
	bar.size = size
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.02, 0.04, 0.06, 0.75)
	background.corner_radius_top_left = 6
	background.corner_radius_top_right = 6
	background.corner_radius_bottom_left = 6
	background.corner_radius_bottom_right = 6
	background.border_width_left = 1
	background.border_width_top = 1
	background.border_width_right = 1
	background.border_width_bottom = 1
	background.border_color = Color(1, 1, 1, 0.12)
	
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = fill
	foreground.corner_radius_top_left = 5
	foreground.corner_radius_top_right = 5
	foreground.corner_radius_bottom_left = 5
	foreground.corner_radius_bottom_right = 5
	
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", foreground)
	parent.add_child(bar)
	return bar


func add_box(parent: Node, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	node.material_override = make_material(color)
	parent.add_child(node)
	return node


func add_cylinder(parent: Node, position: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	node.mesh = mesh
	node.position = position
	node.material_override = make_material(color)
	parent.add_child(node)
	return node


func make_material(color: Color, roughness := 0.78, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func spawn_exhaust_smoke(delta: float) -> void:
	if state != GameState.PLAYING:
		return
	var gas: bool = Input.is_action_pressed("accelerate") or bool(touch.gas)
	var spawn_chance := 0.25 if gas else 0.08
	if rng.randf() > spawn_chance:
		return
		
	var pipe_offset := Vector3(-0.7, -0.15, -2.2)
	var world_pipe_pos := player.global_position + player.global_transform.basis * pipe_offset
	
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.22
	puff.mesh = sphere
	puff.position = world_pipe_pos
	puff.material_override = make_material(Color(0.68, 0.72, 0.75, 0.46), 1.0)
	add_child(puff)
	
	var back_dir := -player.global_transform.basis.z
	var smoke_vel := back_dir * (speed * 0.3 + 1.2) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.4, 0.8), rng.randf_range(-0.3, 0.3))
	
	effects.append({
		"node": puff, 
		"velocity": smoke_vel, 
		"life": 0.75, 
		"is_smoke": true
	})


func spawn_floating_text(text: String, color: Color, world_pos: Vector3) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(label)
	
	floating_texts.append({
		"label": label,
		"world_pos": world_pos,
		"life": 1.0,
		"y_offset": 0.0
	})


func update_floating_texts(delta: float) -> void:
	for entry in floating_texts:
		var label: Label = entry.label
		if not is_instance_valid(label):
			continue
		entry.life -= delta
		entry.y_offset += delta * 72.0
		
		if is_instance_valid(camera) and not camera.is_position_behind(entry.world_pos):
			label.visible = true
			var screen_pos := camera.unproject_position(entry.world_pos)
			screen_pos.y -= entry.y_offset
			label.position = screen_pos - label.size * 0.5
			label.modulate.a = clampf(entry.life, 0.0, 1.0)
		else:
			label.visible = false
			
	for entry in floating_texts.filter(func(x): return x.life <= 0.0):
		if is_instance_valid(entry.label):
			entry.label.queue_free()
	floating_texts = floating_texts.filter(func(x): return x.life > 0.0)


func log_firebase_event(event_name: String, params: Dictionary = {}) -> void:
	if firebase_analytics:
		firebase_analytics.log_event(event_name, params)
