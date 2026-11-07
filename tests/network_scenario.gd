extends Node

var game: Node3D
var net: Node
var role = ""
var test_position = Vector3(8,1.65,0)
var checked_authority = false
var joined = false
var infected_finished = false

func _ready():
	game = get_parent()
	net = game.network
	game.player.set_physics_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--net-test="):
			role = arg.get_slice("=",1)
	if role=="host":
		test_position = Vector3(-8,1.65,0)
		call_deferred("host_scenario")
	else:
		call_deferred("client_scenario")

func _process(_delta):
	if role=="client1":
		test_position = Vector3(.5,1.65,0) if net.map_id==1 else Vector3(8,1.65,0)
	elif role=="client2":
		test_position = Vector3(1,1.65,0) if net.net_mode==2 else Vector3(12,1.65,0)
	game.player.head.global_position = test_position
	game.player.head.global_basis = Basis.IDENTITY
	game.player.palms[0].global_position = test_position+Vector3(-.25,-.4,0)
	game.player.palms[1].global_position = test_position+Vector3(.3,-.4,0)

func require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("NETWORK TEST FAILED: "+message)
		get_tree().quit(1)
	return condition

func wait_for(check: Callable, label: String, timeout = 15.0) -> bool:
	var deadline = Time.get_ticks_msec()+int(timeout*1000)
	while not check.call():
		if Time.get_ticks_msec()>deadline:
			return require(false,"Timed out: "+label)
		await get_tree().create_timer(.05).timeout
	return true

func host_scenario():
	if not require(net.host_room(18777)==OK,"host startup"):
		return
	if not (await wait_for(func(): return net.members.size()==2,"first real client")):
		return
	if not (await wait_for(func(): return net.avatars.values()[0].initialized,"remote head/hand replication")):
		return
	print("PASS host: connected remote avatar over ENet")
	var malformed = [Vector3(NAN,0,0),Quaternion.IDENTITY,Vector3.ZERO,Vector3.ZERO,0]
	if not require(not net.valid_pose(malformed),"reject nonfinite pose"):
		return
	malformed[0] = Vector3.ZERO
	malformed[2] = Vector3(100,0,0)
	if not require(not net.valid_pose(malformed),"reject impossible hand reach"):
		return
	net.choose_map(1)
	net.choose_mode(1)
	test_position = Vector3(0,1.65,0)
	if not (await wait_for(func(): return net.it_peer!=1 and net.scores.get(1,0)==1,"server-authoritative real-player tag")):
		return
	print("PASS host: real-player tag transferred and score synchronized")
	print("WAIT_LATE_JOIN")
	if not (await wait_for(func(): return net.members.size()==3,"late joining third process")):
		return
	net.choose_mode(2)
	if not (await wait_for(func(): return not net.round_active and net.infected.size()==3,"infection victory across three processes")):
		return
	print("PASS host: three-player infection completed")
	if not (await wait_for(func(): return net.members.size()==2,"client departure cleanup")):
		return
	if not require(net.avatars.size()==1,"departed avatar removed"):
		return
	print("PASS host: departing client removed")
	net.leave_room()
	await shutdown("PASS host: network scenario complete")

func client_scenario():
	if not require(net.join_room("127.0.0.1",18777)==OK,"client startup"):
		return
	if not (await wait_for(func(): return net.active and not net.connecting and net.members.size()>=2,"client handshake")):
		return
	joined = true
	if not (await wait_for(func(): return game.map_index==1,"host map synchronized")):
		return
	var old_map = game.map_index
	game.menu_action("map:3")
	if not require(game.map_index==old_map,"client cannot change host map"):
		return
	print("PASS ",role,": host map synchronized; host-only controls enforced")
	if role=="client2":
		if not require(net.net_mode in [1,2],"late join inherited existing room mode"):
			return
		print("PASS client2: late join inherited current map/mode")
	if not (await wait_for(func(): return net.net_mode==2 and not net.round_active and net.infected.size()==3,"replicated infection victory")):
		return
	print("PASS ",role,": infection result replicated")
	if role=="client2":
		net.leave_room()
		await shutdown("PASS client2: graceful leave")
	else:
		if not (await wait_for(func(): return not net.active,"host departure")):
			return
		if not require(net.avatars.is_empty() and not game.playing,"offline state restored"):
			return
		await shutdown("PASS client1: host disconnect recovered")

func shutdown(message: String):
	game.music.stop()
	game.music.stream = null
	await get_tree().create_timer(.2).timeout
	print(message)
	get_tree().quit()
