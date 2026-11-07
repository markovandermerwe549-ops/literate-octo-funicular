extends CharacterBody3D

var rig: XROrigin3D
var head: XRCamera3D
var hands: Array[XRController3D] = []
var palms: Array[MeshInstance3D] = []
var anchors = [Vector3.ZERO, Vector3.ZERO]
var anchored = [false, false]
var previous = [Vector3.ZERO, Vector3.ZERO]
var last_local = [Vector3.ZERO, Vector3.ZERO]
var primed = false
var xr_active = false
var snap_ready = true
var speed = 1.0
var snap_degrees = 30.0
var stick_assist = true
var mouse_look = Vector2.ZERO
var launch = Vector3.ZERO
var menu_latch = false
var trigger_latch = false
var ray: MeshInstance3D
var aim: XRController3D
var status: Label3D
var sphere = SphereShape3D.new()
var body_shape: CollisionShape3D
var game: Node3D
var hand_material: StandardMaterial3D

func _ready():
	game = get_parent()
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.18
	body_shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.23
	capsule.height = 1.4
	body_shape.shape = capsule
	body_shape.position.y = 0.7
	add_child(body_shape)
	rig = XROrigin3D.new()
	add_child(rig)
	head = XRCamera3D.new()
	head.current = true
	head.near = 0.07
	head.far = 180
	head.position.y = 1.65
	rig.add_child(head)
	var xr = XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		xr_active = true
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		xr.session_focussed.connect(func(): game.focused = true)
		xr.session_visible.connect(func(): game.focused = false)
		xr.session_stopping.connect(func(): game.save_progress())
	for i in range(2):
		var controller = XRController3D.new()
		controller.tracker = &"left_hand" if i == 0 else &"right_hand"
		controller.pose = &"grip"
		rig.add_child(controller)
		hands.append(controller)
		var palm = MeshInstance3D.new()
		var mesh = SphereMesh.new()
		mesh.radius = 0.095
		mesh.height = 0.19
		mesh.radial_segments = 12
		mesh.rings = 6
		palm.mesh = mesh
		game.add_child(palm)
		palms.append(palm)
	sphere.radius = 0.095
	set_color(Color("b3f46f"))
	status = Label3D.new()
	status.font_size = 32
	status.pixel_size = 0.0008
	status.position = Vector3(0,-0.28,-1.2)
	status.modulate = Color("d9f7da")
	status.no_depth_test = true
	head.add_child(status)
	ray = MeshInstance3D.new()
	var beam = CylinderMesh.new()
	beam.top_radius = 0.003
	beam.bottom_radius = 0.003
	beam.height = 4
	ray.mesh = beam
	ray.rotation.x = PI/2
	ray.position.z = -2
	ray.material_override = game.mat(Color("b3f46f"),true)
	aim = XRController3D.new()
	aim.tracker = &"right_hand"
	aim.pose = &"aim"
	rig.add_child(aim)
	aim.add_child(ray)
	ray.visible = false
	if not xr_active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		status.visible = false

func set_color(color: Color):
	hand_material = game.mat(color)
	for palm in palms:
		palm.material_override = hand_material

func reset_at(point: Vector3):
	global_position = point
	velocity = Vector3.ZERO
	launch = Vector3.ZERO
	anchored = [false,false]
	primed = false

func _unhandled_input(event):
	if xr_active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * 0.003
		head.rotation.x = clampf(head.rotation.x-event.relative.y*0.003,-1.3,1.3)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE,KEY_TAB]:
			game.toggle_menu()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if game.menu_open else Input.MOUSE_MODE_CAPTURED
		if event.keycode == KEY_R:
			reset_at(Vector3(0,0.2,8))
		if event.keycode == KEY_SPACE and is_on_floor():
			velocity.y = 7

func _physics_process(delta):
	if not game.focused:
		return
	if not xr_active:
		desktop_move(delta)
		return
	var menu_pressed = hands[0].is_button_pressed("ax_button") or hands[0].is_button_pressed("menu_button") or hands[1].is_button_pressed("by_button")
	if menu_pressed and not menu_latch:
		game.toggle_menu()
	menu_latch = menu_pressed
	if hands[0].is_button_pressed("by_button"):
		reset_at(Vector3(0,0.2,8))
	if game.menu_open:
		for i in range(2):
			palms[i].global_position = hands[i].global_position
		velocity = Vector3.ZERO
		launch = Vector3.ZERO
		anchored = [false,false]
		primed = false
		menu_ray()
		return
	var turn = hands[1].get_vector2("primary").x
	if absf(turn) > 0.7 and snap_ready:
		var old_head = head.global_position
		rotation.y -= signf(turn)*deg_to_rad(snap_degrees)
		global_position += old_head-head.global_position
		snap_ready = false
	if absf(turn) < 0.25:
		snap_ready = true
	var target_move = Vector3.ZERO
	var contacts = 0
	for i in range(2):
		if not hands[i].get_is_active():
			anchored[i] = false
			palms[i].visible = false
			continue
		palms[i].visible = true
		var desired = hands[i].global_position
		var from = previous[i] if primed else desired
		if from.distance_to(desired)>1.2:
			from = desired
		var query = PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.transform = Transform3D(Basis.IDENTITY,from)
		query.motion = desired-from
		query.collision_mask = 1
		var sweep = get_world_3d().direct_space_state.cast_motion(query)
		var actual = from.lerp(desired,sweep[0]) if sweep.size() == 2 else desired
		query.transform.origin = desired
		query.motion = Vector3.ZERO
		query.margin = 0.06
		var touching = not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
		var grip = hands[i].get_float("grip") > 0.55
		if grip and touching and not anchored[i]:
			anchors[i] = actual
			anchored[i] = true
			haptic(i,0.25)
		if not grip:
			anchored[i] = false
		if anchored[i]:
			if anchors[i].distance_to(desired)>1.5:
				anchored[i] = false
			else:
				target_move += anchors[i]-desired
				actual = anchors[i]
				contacts += 1
		elif actual.distance_to(desired)>0.002 and primed:
			target_move += actual-desired
			contacts += 1
		palms[i].global_position = actual
		previous[i] = actual
		last_local[i] = hands[i].position
	primed = true
	if contacts > 0:
		target_move /= contacts
		var push = (target_move / maxf(delta,0.001)).limit_length(8*speed)
		velocity = push
		launch = launch.lerp(push,0.4)
	else:
		if launch.length()>0.1:
			velocity = launch.limit_length(9*speed)
			launch = Vector3.ZERO
		velocity.y -= 16*delta
		if is_on_floor():
			velocity.x = move_toward(velocity.x,0,14*delta)
			velocity.z = move_toward(velocity.z,0,14*delta)
		if stick_assist and not game.menu_open:
			var stick = hands[0].get_vector2("primary")
			var direction = head.global_basis*Vector3(stick.x,0,-stick.y)
			direction.y = 0
			if direction.length()>0.2:
				velocity.x = direction.x*4*speed
				velocity.z = direction.z*4*speed
	body_shape.position.x = head.position.x
	body_shape.position.z = head.position.z
	move_and_slide()
	if global_position.y < -12:
		reset_at(Vector3(0,0.2,8))
	menu_ray()

func desktop_move(delta):
	if game.menu_open:
		return
	var input = Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	var direction = global_basis*input.normalized()
	velocity.x = direction.x*5*speed
	velocity.z = direction.z*5*speed
	velocity.y -= 16*delta
	move_and_slide()
	for i in range(2):
		palms[i].global_position = head.global_position+global_basis*Vector3(-0.3 if i==0 else 0.3,-0.35,-0.45)
	if global_position.y < -12:
		reset_at(Vector3(0,0.2,8))

func menu_ray():
	ray.visible = game.menu_open
	var trigger = hands[1].get_float("trigger") > 0.6
	if game.menu_open and trigger and not trigger_latch:
		var source = aim.global_position
		var query = PhysicsRayQueryParameters3D.create(source,source-aim.global_basis.z*8,2)
		var hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider.has_meta("action"):
			game.menu_action(hit.collider.get_meta("action"))
			haptic(1,0.3)
	trigger_latch = trigger

func haptic(index: int, amount: float):
	if xr_active:
		hands[index].trigger_haptic_pulse("haptic",0,amount,0.06,0)

func touch_points() -> Array:
	return [palms[0].global_position,palms[1].global_position]
