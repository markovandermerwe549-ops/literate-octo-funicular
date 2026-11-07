extends Node3D

var game: Node3D
var head: Node3D
var body: MeshInstance3D
var palms: Array = []
var arms: Array = []
var label: Label3D
var target: Array = []
var color_index = -1
var highlighted = false
var initialized = false

func setup(owner_game: Node3D, peer_id: int):
	game = owner_game
	head = Node3D.new()
	add_child(head)
	game.orb(head,Vector3.ZERO,.28,Color.WHITE)
	game.orb(head,Vector3(0,-.03,-.21),.21,Color("e7edcc"))
	game.orb(head,Vector3(-.1,.03,-.39),.035,Color("193334"))
	game.orb(head,Vector3(.1,.03,-.39),.035,Color("193334"))
	body = game.orb(self,Vector3.ZERO,.35,Color.WHITE)
	for i in range(2):
		palms.append(game.orb(self,Vector3.ZERO,.095,Color.WHITE))
		var arm = MeshInstance3D.new()
		var cylinder = CylinderMesh.new()
		cylinder.top_radius = .055
		cylinder.bottom_radius = .055
		cylinder.height = 1
		cylinder.radial_segments = 8
		arm.mesh = cylinder
		add_child(arm)
		arms.append(arm)
	label = game.text3(self,"Runner "+str(peer_id).right(4),Vector3.ZERO,26,.0025)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	visible = false

func set_pose(pose: Array):
	target = pose
	visible = true
	if not initialized:
		head.position = pose[0]
		head.quaternion = pose[1]
		palms[0].position = pose[2]
		palms[1].position = pose[3]
		initialized = true

func _process(delta):
	if target.is_empty():
		return
	var weight = 1.0-exp(-18.0*delta)
	head.position = head.position.lerp(target[0],weight)
	head.quaternion = head.quaternion.slerp(target[1],weight)
	body.position = head.position-Vector3(0,.53,0)
	label.position = head.position+Vector3(0,.47,0)
	for i in range(2):
		palms[i].position = palms[i].position.lerp(target[i+2],weight)
		var shoulder = head.position+Vector3(-.22 if i==0 else .22,-.45,0)
		var direction = palms[i].position-shoulder
		arms[i].position = (shoulder+palms[i].position)*.5
		if direction.length()>.001:
			arms[i].basis = Basis(Quaternion(Vector3.UP,direction.normalized())).scaled(Vector3(1,direction.length(),1))
	if color_index != int(target[4]):
		color_index = int(target[4])
		var material = game.mat(game.COLORS[color_index])
		head.get_child(0).material_override = material
		body.material_override = material
		for palm in palms:
			palm.material_override = material
		for arm in arms:
			arm.material_override = material

func set_tagged(tagged: bool):
	highlighted = tagged
	label.modulate = Color("ff6c8a") if tagged else Color("edf7df")
	label.text = label.text.trim_suffix("  [IT]")+ ("  [IT]" if tagged else "")
