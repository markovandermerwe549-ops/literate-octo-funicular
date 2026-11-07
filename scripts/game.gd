extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const MAPS = ["Emerald Canopy", "Sunstone Canyon", "Glacier Hollow", "Neon Overgrowth"]
const MODES = ["Free roam", "Bot tag", "Infection", "Time trial", "Crystal hunt"]
const COLORS = [Color("b3f46f"),Color("66dbef"),Color("ffb868"),Color("e3a0ff"),Color("ff6c8a")]
const TRACKS = [preload("res://audio/canopy.wav"),preload("res://audio/canyon.wav"),preload("res://audio/glacier.wav"),preload("res://audio/neon.wav")]
var player: CharacterBody3D
var world: Node3D
var panel: Node3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var music: AudioStreamPlayer
var map_index = 0
var mode = 0
var menu_open = false
var focused = true
var night = false
var muted = false
var bots: Array = []
var crystals: Array = []
var gates: Array = []
var elapsed = 0.0
var round_time = 0.0
var round_length = 90.0
var playing = false
var player_it = true
var cooldown = 0.0
var score = 0
var gate_index = 0
var found = 0
var currency = 0
var total_tags = 0
var best_times: Dictionary = {}
var owned = [0]
var cosmetic = 0
var desktop_label: Label
var desktop_menu: PanelContainer
var notice = "Welcome! Open the menu to choose your adventure."
var notice_time = 10.0
var status_label: Label3D
var rng = RandomNumberGenerator.new()

func _ready():
	rng.seed = 4771
	load_progress()
	environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("153f50")
	sky_mat.sky_horizon_color = Color("a2c6b5")
	sky_mat.ground_horizon_color = Color("a2c6b5")
	sky_mat.ground_bottom_color = Color("1c3439")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c6e9e0")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_color = Color("ffe6b3")
	sun.light_energy = 1.2
	sun.shadow_enabled = false
	add_child(sun)
	player = CharacterBody3D.new()
	player.set_script(PlayerScript)
	add_child(player)
	player.set_color(COLORS[cosmetic])
	music = AudioStreamPlayer.new()
	music.volume_db = -13
	add_child(music)
	music.finished.connect(func(): music.play())
	build_map()
	build_panel()
	build_desktop_ui()
	if "--smoke-test" in OS.get_cmdline_user_args():
		call_deferred("smoke_test")
	if "--capture-preview" in OS.get_cmdline_user_args():
		call_deferred("capture_preview")

func mat(color: Color, glow = false) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if glow:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid = true) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	parent.add_child(root)
	root.position = pos
	var mesh = MeshInstance3D.new()
	var cube = BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.material_override = mat(color)
	root.add_child(mesh)
	if solid:
		var collider = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		root.add_child(collider)
	return root

func orb(parent: Node3D, pos: Vector3, radius: float, color: Color, glow = false) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var ball = SphereMesh.new()
	ball.radius = radius
	ball.height = radius*2
	ball.radial_segments = 12
	ball.rings = 6
	mesh.mesh = ball
	mesh.position = pos
	mesh.material_override = mat(color,glow)
	parent.add_child(mesh)
	return mesh

func text3(parent: Node3D, value: String, pos: Vector3, font_size = 40, pixel = 0.007) -> Label3D:
	var label = Label3D.new()
	label.text = value
	label.font_size = font_size
	label.pixel_size = pixel
	label.position = pos
	label.modulate = Color("edf7df")
	label.outline_size = 5
	parent.add_child(label)
	return label

func build_map():
	if world:
		remove_child(world)
		world.queue_free()
	world = Node3D.new()
	add_child(world)
	bots.clear()
	crystals.clear()
	gates.clear()
	var floors = [Color("345c46"),Color("a56d44"),Color("799dab"),Color("1a2d44")]
	var rock = [Color("436d58"),Color("ce925e"),Color("b0d8df"),Color("37405e")][map_index]
	box(world,Vector3(0,-0.6,0),Vector3(58,1.2,58),floors[map_index])
	for i in range(4):
		var border = box(world,Vector3(0,4,-29) if i<2 else Vector3(-29,4,0),Vector3(60,10,2) if i<2 else Vector3(2,10,60),rock.darkened(.25))
		if i==1: border.position.z=29
		if i==3: border.position.x=29
	for i in range(20):
		var angle = i*TAU/20
		var radius = 18.0+sin(i*3.7)*4
		var pos = Vector3(sin(angle)*radius,0,cos(angle)*radius)
		if map_index == 0:
			box(world,pos+Vector3(0,4,0),Vector3(1.2,8,1.2),Color("594d37"))
			orb(world,pos+Vector3(0,8,0),3.5,Color("39765a"))
			orb(world,pos+Vector3(1.6,7,0),2.6,Color("55915d"))
			box(world,pos+Vector3(0,2.1,0),Vector3(4,0.3,2),Color("ae8e61"))
			box(world,pos+Vector3(0,4.5,0),Vector3(3,0.3,3),Color("ae8e61"))
		else:
			var height = 3.0+fmod(i*1.7,5)
			var pillar = box(world,pos+Vector3(0,height/2,0),Vector3(3,height,3),rock)
			pillar.rotation.y = i*.3
			box(world,pos+Vector3(0,height+.1,0),Vector3(3.4,.2,3.4),COLORS[map_index],false)
	# Climbable steps, launch pads and bridges lead into an elevated loop.
	for i in range(7):
		box(world,Vector3(-11+i*1.7,0.3+i*.34,-5),Vector3(2.1,.6+i*.68,2.5),rock.lightened(.08))
	box(world,Vector3(5,3,-5),Vector3(10,.4,2.5),rock)
	box(world,Vector3(10,2.5,0),Vector3(2.5,.4,10),rock)
	box(world,Vector3(-8,1.2,4),Vector3(2,2.4,2),rock)
	box(world,Vector3(-8,2.2,0),Vector3(2,4.4,2),rock)
	box(world,Vector3(-8,3.4,-4),Vector3(2,6.8,2),rock)
	box(world,Vector3(0,.08,8),Vector3(5,.16,4),Color("e0e9c0"))
	text3(world,"CANOPY CHASE",Vector3(0,3.5,12),64).rotation.y = PI
	text3(world,MAPS[map_index]+"  /  BASE CAMP",Vector3(0,2.9,12),24).rotation.y = PI
	var board = box(world,Vector3(0,2,-10),Vector3(7,3,.25),Color("143a3d"))
	text3(board,"MOVE WITH YOUR HANDS\nPush the ground • grip to climb • release to leap\nX / B: menu     Y: return to camp\nTag with either hand. Explore every route.",Vector3(0,0,.15),30,.0045)
	for i in range(30):
		var angle = i*2.4
		var radius = 5.0+fmod(i*3.3,18)
		var pos = Vector3(sin(angle)*radius,1.0+float(i%3)*.4,cos(angle)*radius)
		var crystal = MeshInstance3D.new()
		var gem = PrismMesh.new()
		gem.size = Vector3(.3,.6,.3)
		crystal.mesh = gem
		crystal.material_override = mat(COLORS[map_index],true)
		crystal.position = pos
		world.add_child(crystal)
		crystals.append({"node":crystal,"base":pos,"taken":false})
	var route = [Vector3(0,1.4,3),Vector3(-8,1.4,4),Vector3(-11,1.4,-5),Vector3(-6,2.4,-5),Vector3(0,4,-5),Vector3(8,4,-5),Vector3(10,3.7,2),Vector3(4,1.4,6),Vector3(0,1.4,8)]
	for pos in route:
		var gate = Node3D.new()
		world.add_child(gate)
		gate.position = pos
		var torus = MeshInstance3D.new()
		var ring = TorusMesh.new()
		ring.inner_radius = .88
		ring.outer_radius = 1.0
		ring.rings = 16
		ring.ring_segments = 12
		torus.mesh = ring
		torus.rotation.x = PI/2
		torus.material_override = mat(Color("b3f46f"),true)
		gate.add_child(torus)
		text3(gate,str(gates.size()+1),Vector3(0,1.2,0),32)
		gates.append(gate)
	for i in range(5):
		var bot = Node3D.new()
		world.add_child(bot)
		bot.position = Vector3(sin(i*1.25)*12,0,cos(i*1.25)*12)
		var color = COLORS[i]
		orb(bot,Vector3(0,.85,0),.43,color)
		orb(bot,Vector3(0,1.42,0),.32,color)
		orb(bot,Vector3(0,1.4,.25),.23,Color("e7edcc"))
		orb(bot,Vector3(-.11,1.48,.43),.045,Color("193334"))
		orb(bot,Vector3(.11,1.48,.43),.045,Color("193334"))
		orb(bot,Vector3(-.55,.55,0),.15,color)
		orb(bot,Vector3(.55,.55,0),.15,color)
		var tag = text3(bot,["MOSS","PEBBLE","FROST","SPARK","BLOOM"][i],Vector3(0,2.05,0),24,.003)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bots.append({"node":bot,"infected":false,"name":tag,"phase":i*1.3,"speed":2.2+i*.22})
	player.reset_at(Vector3(0,.2,8))
	music.stream = TRACKS[map_index]
	music.play()
	start_round()

func start_round():
	playing = mode != 0
	round_time = 0
	score = 0
	gate_index = 0
	found = 0
	player_it = true
	cooldown = 3
	for bot in bots:
		bot.infected = false
		bot.node.visible = mode in [1,2]
		bot.name.modulate = Color.WHITE
	for crystal in crystals:
		crystal.taken = false
		crystal.node.visible = mode in [0,4]
	for i in range(gates.size()):
		gates[i].visible = mode==3 and i==0
	toast(MODES[mode]+" ready. "+("Catch every runner!" if mode in [1,2] else "Explore and climb!"))

func _process(delta):
	if not focused:
		return
	elapsed += delta
	notice_time -= delta
	if not menu_open:
		round_time += delta if playing else 0.0
		cooldown -= delta
		update_bots(delta)
		update_collectibles(delta)
		if playing and mode in [1,2,4] and round_time>=round_length:
			finish_round("Time! Score: "+str(score))
	var summary = MAPS[map_index]+"  /  "+MODES[mode]
	var details = "Shards %d   |   Tags %d" % [currency,total_tags]
	if mode in [1,2,4]:
		details = "Score %d  |  %ds  |  Shards %d" % [score,maxi(0,int(round_length-round_time)),currency]
	if mode==3:
		details = "Gate %d / %d  |  %.1fs  |  Best %s" % [mini(gate_index+1,gates.size()),gates.size(),round_time,str(best_times.get(str(map_index),"—"))]
	var message = notice if notice_time>0 else ("YOU ARE IT" if mode==1 and player_it else "X / B: menu   •   Y: camp")
	player.status.text = details+"\n"+message
	if is_instance_valid(desktop_label):
		desktop_label.text = "CANOPY CHASE\n"+summary+"\n"+details+"\n\n"+message+"\n\nWASD move   •   Mouse look   •   Space jump\nTab menu   •   R camp"
	if is_instance_valid(status_label):
		status_label.text = summary+"\n"+details+"\n"+message

func update_bots(delta):
	if mode not in [1,2] or not playing:
		return
	var target = player.head.global_position
	for bot in bots:
		var node: Node3D = bot.node
		var chasing = (not player_it) if mode==1 else bot.infected
		var diff = target-node.position
		diff.y = 0
		var direction = diff.normalized()
		if not chasing:
			direction = -direction if diff.length()<9 else Vector3(sin(elapsed*.45+bot.phase),0,cos(elapsed*.4+bot.phase))
		if mode==2 and bot.infected:
			var closest = 1000.0
			for other in bots:
				if not other.infected:
					var distance = node.position.distance_to(other.node.position)
					if distance<closest:
						closest = distance
						direction = (other.node.position-node.position).normalized()
					if distance<1.0:
						other.infected = true
						other.name.modulate = Color("ff6c8a")
		var proposed = node.position+direction*bot.speed*delta
		# Sweep a waist-height ray so runners steer around climbable obstacles.
		var ray_from = node.position+Vector3(0,.8,0)
		var ray_to = ray_from+direction*1.3
		var query = PhysicsRayQueryParameters3D.create(ray_from,ray_to,1)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			proposed = node.position+direction.rotated(Vector3.UP,PI/2)*bot.speed*delta
		proposed.x = clampf(proposed.x,-26,26)
		proposed.z = clampf(proposed.z,-26,26)
		node.position = Vector3(proposed.x,sin(elapsed*5+bot.phase)*.12,proposed.z)
		if direction.length()>.01:
			node.rotation.y = atan2(direction.x,direction.z)
		if cooldown>0:
			continue
		var touching = false
		for point in player.touch_points():
			if point.distance_to(node.global_position+Vector3(0,1.1,0))<.78:
				touching = true
		if mode==1:
			if player_it and touching:
				player_it = false
				score += 1
				total_tags += 1
				currency += 3
				cooldown = 3
				toast("TAG! Run away for 15 seconds.")
				player.haptic(1,.7)
			elif not player_it and diff.length()<.7 and absf(target.y-1.6)<1.3:
				player_it = true
				cooldown = 3
				toast("You've been tagged. Your turn!")
		elif touching and not bot.infected:
			bot.infected = true
			bot.name.modulate = Color("ff6c8a")
			score += 1
			total_tags += 1
			currency += 3
			player.haptic(1,.6)
	if mode==1 and not player_it and fmod(round_time,15)<delta:
		player_it = true
		cooldown = 2
		toast("Chase again!")
	if mode==2 and bots.all(func(b): return b.infected):
		currency += 15
		finish_round("All runners infected! +15 bonus shards")

func update_collectibles(delta):
	for crystal in crystals:
		if crystal.taken or mode not in [0,4]:
			continue
		crystal.node.rotation.y += delta
		crystal.node.position.y = crystal.base.y+sin(elapsed*2+crystal.base.x)*.15
		var collect = false
		for point in player.touch_points():
			if point.distance_to(crystal.node.global_position)<.45:
				collect = true
		if player.head.global_position.distance_to(crystal.node.global_position)<.65:
			collect = true
		if collect and (playing or mode==0):
			crystal.taken = true
			crystal.node.visible = false
			currency += 1
			found += 1
			score += 1
			player.haptic(0,.25)
			if found==crystals.size() and mode==4:
				currency += 20
				finish_round("Every crystal found! +20 bonus shards")
	if mode==3 and playing and gate_index<gates.size():
		if player.head.global_position.distance_to(gates[gate_index].global_position)<1.25:
			gates[gate_index].visible = false
			gate_index += 1
			player.haptic(1,.3)
			if gate_index==gates.size():
				var key = str(map_index)
				if round_time<float(best_times.get(key,9999)):
					best_times[key] = snappedf(round_time,.1)
				currency += 10
				finish_round("Course complete! %.1fs  +10 shards" % round_time)
			else:
				gates[gate_index].visible = true

func finish_round(message: String):
	playing = false
	toast(message+" • Restart from the menu.",15)
	save_progress()

func toast(message: String, duration = 7.0):
	notice = message
	notice_time = duration

func build_panel():
	if panel:
		remove_child(panel)
		panel.queue_free()
	panel = Node3D.new()
	add_child(panel)
	box(panel,Vector3.ZERO,Vector3(3.5,2.8,.08),Color("102e32"),false)
	text3(panel,"CANOPY / CHASE",Vector3(0,1.18,.06),48,.002)
	text3(panel,"Choose a world. Find your own way up.",Vector3(0,.98,.06),24,.002)
	for i in range(4):
		menu_button(MAPS[i],"map:"+str(i),Vector3(-1.24+i*.83,.68,.08),Vector2(.78,.28))
	for i in range(5):
		menu_button(MODES[i],"mode:"+str(i),Vector3(-1.32+i*.66,.3,.08),Vector2(.62,.28))
	menu_button("RESTART","restart",Vector3(-1.12,-.1,.08),Vector2(.95,.28))
	menu_button("RETURN TO CAMP","reset",Vector3(0,-.1,.08),Vector2(1.12,.28))
	menu_button("DAY / NIGHT","night",Vector3(1.12,-.1,.08),Vector2(.95,.28))
	menu_button("STICK ASSIST","assist",Vector3(-1.12,-.46,.08),Vector2(.95,.28))
	menu_button("SPEED","speed",Vector3(0,-.46,.08),Vector2(.95,.28))
	menu_button("SOUND","sound",Vector3(1.12,-.46,.08),Vector2(.95,.28))
	menu_button("HAND COLOR  /  15 SHARDS","cosmetic",Vector3(-.75,-.82,.08),Vector2(1.4,.28))
	menu_button("TURN 30° / 45°","turn",Vector3(.75,-.82,.08),Vector2(1.4,.28))
	status_label = text3(panel,"",Vector3(0,-1.15,.06),22,.0018)
	panel.visible = menu_open

func menu_button(label: String, action: String, pos: Vector3, size: Vector2):
	var button = box(panel,pos,Vector3(size.x,size.y,.04),Color("28544f"))
	button.collision_layer = 2
	button.collision_mask = 0
	button.set_meta("action",action)
	text3(button,label,Vector3(0,0,.03),22,.00165)

func toggle_menu():
	menu_open = not menu_open
	panel.visible = menu_open and player.xr_active
	if menu_open:
		var forward = -player.head.global_basis.z
		forward.y = 0
		forward = forward.normalized()
		panel.global_position = player.head.global_position+forward*2.6-Vector3(0,.1,0)
		panel.rotation.y = atan2(-forward.x,-forward.z)
	if desktop_menu:
		desktop_menu.visible = menu_open and not player.xr_active

func menu_action(action: String):
	if action.begins_with("map:"):
		map_index = int(action.get_slice(":",1))
		build_map()
	elif action.begins_with("mode:"):
		mode = int(action.get_slice(":",1))
		start_round()
	else:
		match action:
			"restart":
				player.reset_at(Vector3(0,.2,8))
				start_round()
			"reset": player.reset_at(Vector3(0,.2,8))
			"night":
				night = not night
				sun.light_energy = .15 if night else 1.2
				environment.environment.ambient_light_energy = .35 if night else .7
				toast("Night lighting" if night else "Day lighting")
			"assist":
				player.stick_assist = not player.stick_assist
				toast("Stick assist: "+str(player.stick_assist))
			"speed":
				player.speed = .75 if player.speed>=1.25 else player.speed+.25
				toast("Movement speed: "+str(player.speed))
			"sound":
				muted = not muted
				music.volume_db = -80 if muted else -13
				toast("Sound off" if muted else "Sound on")
			"turn":
				player.snap_degrees = 45 if player.snap_degrees==30 else 30
				toast("Snap turn: "+str(player.snap_degrees)+" degrees")
			"cosmetic":
				var next = (cosmetic+1)%COLORS.size()
				if next not in owned:
					if currency<15:
						toast("Collect 15 shards to unlock the next hand color.")
						return
					currency -= 15
					owned.append(next)
				cosmetic = next
				player.set_color(COLORS[cosmetic])
				toast("Hand color equipped")
			"close": toggle_menu()
	if action=="close" and not player.xr_active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	save_progress()
	if action.begins_with("map:") or action.begins_with("mode:") or action in ["reset","restart"]:
		if menu_open:
			toggle_menu()
		if not player.xr_active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func build_desktop_ui():
	if player.xr_active:
		return
	var canvas = CanvasLayer.new()
	add_child(canvas)
	desktop_label = Label.new()
	desktop_label.position = Vector2(26,24)
	desktop_label.add_theme_font_size_override("font_size",20)
	desktop_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	desktop_label.add_theme_constant_override("shadow_offset_x",2)
	desktop_label.add_theme_constant_override("shadow_offset_y",2)
	canvas.add_child(desktop_label)
	desktop_menu = PanelContainer.new()
	desktop_menu.position = Vector2(350,100)
	desktop_menu.custom_minimum_size = Vector2(730,600)
	canvas.add_child(desktop_menu)
	var column = VBoxContainer.new()
	desktop_menu.add_child(column)
	var title = Label.new()
	title.text = "CANOPY CHASE  /  ADVENTURE MENU"
	title.add_theme_font_size_override("font_size",28)
	column.add_child(title)
	for group in [MAPS,MODES,["Restart","Reset","Night","Assist","Speed","Sound","Turn","Cosmetic","Close"]]:
		var grid = HFlowContainer.new()
		column.add_child(grid)
		for i in range(group.size()):
			var button = Button.new()
			button.text = group[i]
			button.custom_minimum_size = Vector2(170,60)
			var action = ("map:"+str(i)) if group==MAPS else (("mode:"+str(i)) if group==MODES else str(group[i]).to_lower())
			button.pressed.connect(func(): menu_action(action))
			grid.add_child(button)
	desktop_menu.visible = false

func save_progress():
	var config = ConfigFile.new()
	config.set_value("progress","shards",currency)
	config.set_value("progress","tags",total_tags)
	config.set_value("progress","owned",owned)
	config.set_value("progress","color",cosmetic)
	config.set_value("progress","best",best_times)
	if player:
		config.set_value("settings","assist",player.stick_assist)
		config.set_value("settings","speed",player.speed)
		config.set_value("settings","turn",player.snap_degrees)
	config.save("user://progress.cfg")

func load_progress():
	var config = ConfigFile.new()
	if config.load("user://progress.cfg") != OK:
		return
	currency = int(config.get_value("progress","shards",0))
	total_tags = int(config.get_value("progress","tags",0))
	owned = config.get_value("progress","owned",[0])
	cosmetic = clampi(int(config.get_value("progress","color",0)),0,4)
	best_times = config.get_value("progress","best",{})
	call_deferred("load_settings")

func load_settings():
	var config = ConfigFile.new()
	config.load("user://progress.cfg")
	player.stick_assist = config.get_value("settings","assist",true)
	player.speed = config.get_value("settings","speed",1.0)
	player.snap_degrees = config.get_value("settings","turn",30.0)

func _notification(what):
	if what==NOTIFICATION_APPLICATION_PAUSED or what==NOTIFICATION_WM_CLOSE_REQUEST:
		save_progress()

func smoke_test():
	# Exercise every map and mode, persistence, settings, and scene replacement.
	for map_id in range(4):
		map_index = map_id
		build_map()
		await get_tree().physics_frame
		for mode_id in range(5):
			mode = mode_id
			start_round()
			for i in range(5):
				await get_tree().physics_frame
			assert(bots.size()==5 and crystals.size()==30 and gates.size()==9)
			print("PASS map=",map_id," mode=",mode_id)
	for action in ["night","night","assist","assist","speed","turn","sound","sound","reset","restart"]:
		menu_action(action)
	player.set_physics_process(false)
	for palm in player.palms:
		palm.global_position = Vector3(100,100,100)
	mode = 4
	start_round()
	var old_currency = currency
	player.head.global_position = crystals[0].node.global_position
	update_collectibles(0)
	assert(found==1 and score==1 and currency==old_currency+1)
	mode = 3
	start_round()
	round_time = 12.3
	for gate in gates:
		player.head.global_position = gate.global_position
		update_collectibles(0)
	assert(gate_index==9 and not playing and best_times.has(str(map_index)))
	mode = 1
	start_round()
	cooldown = 0
	player.palms[0].global_position = bots[0].node.global_position+Vector3(0,1.1,0)
	update_bots(0)
	assert(score==1 and not player_it)
	mode = 2
	start_round()
	cooldown = 0
	for bot in bots:
		player.palms[0].global_position = bot.node.global_position+Vector3(0,1.1,0)
		update_bots(0)
	assert(not playing and bots.all(func(b): return b.infected))
	print("PASS crystal rewards, race completion, bot tag, infection win")
	mode = 0
	map_index = 0
	build_map()
	save_progress()
	music.stop()
	music.stream = null
	await get_tree().create_timer(.15).timeout
	print("SMOKE TEST PASSED")
	get_tree().quit()

func capture_preview():
	player.set_physics_process(false)
	mode = 1
	start_round()
	player.head.global_position = Vector3(0,7,12)
	player.head.look_at(Vector3(0,1,-6))
	for i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/workspace/work/preview.png")
	music.stop()
	music.stream = null
	await get_tree().create_timer(.15).timeout
	get_tree().quit()
