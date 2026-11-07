extends Node

const Avatar = preload("res://scripts/remote_avatar.gd")
const PORT = 7777
const MAX_PLAYERS = 8
const PROTOCOL = 2
const NET_MODES = ["Social", "Player tag", "Player infection"]
var game: Node3D
var active = false
var connecting = false
var connect_deadline = 0
var members: Dictionary = {}
var avatars: Dictionary = {}
var scores: Dictionary = {}
var infected: Array = []
var it_peer = 1
var net_mode = 0
var map_id = 0
var epoch = 0
var applied_epoch = -1
var remaining = 90.0
var round_active = false
var tag_cooldown = 2.0
var send_accumulator = 0.0
var message = "Offline"
var address = "192.168.1.100"
var host_ips = ""

func _ready():
	game = get_parent()
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): leave_room("Connection failed. Check IP, Wi-Fi and UDP 7777."))
	multiplayer.server_disconnected.connect(func(): leave_room("Host disconnected. Returned to offline play."))

func host_room(port = PORT) -> Error:
	if active or connecting:
		return ERR_ALREADY_IN_USE
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port,MAX_PLAYERS-1,2)
	if error != OK:
		game.toast("Cannot host: UDP port "+str(port)+" is unavailable.")
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	host_ips = ""
	members = {1:{"pose":[]}}
	scores = {1:0}
	map_id = game.map_index
	net_mode = 0
	message = "Room open — share your IP."
	restart_round()
	game.toast("Hosting. Friends can join your IP on UDP "+str(port),12)
	return OK

func join_room(ip: String, port = PORT) -> Error:
	if active or connecting:
		return ERR_ALREADY_IN_USE
	if not ip.is_valid_ip_address() or ":" in ip:
		game.toast("Enter the host's IPv4 address, such as 192.168.1.20.")
		return ERR_INVALID_PARAMETER
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip,port,2)
	if error != OK:
		game.toast("Could not start connection: "+error_string(error))
		return error
	address = ip
	multiplayer.multiplayer_peer = peer
	connecting = true
	connect_deadline = Time.get_ticks_msec()+10000
	message = "Connecting to "+ip+"…"
	game.toast(message)
	return OK

func _connected():
	active = true
	_hello.rpc_id(1,PROTOCOL)

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(version: int):
	if not active or not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if version != PROTOCOL or members.size()>=MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	if members.has(sender):
		return
	members[sender] = {"pose":[]}
	scores[sender] = 0
	message = "Runner joined."
	_publish_room()

func leave_room(reason = "Left room. Returned to offline play."):
	if not active and not connecting:
		return
	active = false
	connecting = false
	var peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if peer is ENetMultiplayerPeer:
		peer.close()
	for avatar in avatars.values():
		avatar.queue_free()
	avatars.clear()
	members.clear()
	scores.clear()
	infected.clear()
	applied_epoch = -1
	message = reason
	game.mode = 0
	game.start_round()
	game.toast(reason,12)

func _peer_left(id: int):
	if not active or not multiplayer.is_server() or not members.has(id):
		return
	members.erase(id)
	scores.erase(id)
	infected.erase(id)
	if it_peer==id:
		it_peer = int(members.keys()[0])
	if net_mode==2 and infected.is_empty():
		infected.append(it_peer)
	message = "Runner disconnected."
	check_round_complete()
	_publish_room()

func choose_map(index: int):
	if not active or not multiplayer.is_server():
		game.toast("Only the host can change the room's map.")
		return
	map_id = clampi(index,0,3)
	restart_round()

func choose_mode(index: int):
	if not active or not multiplayer.is_server():
		game.toast("Only the host can change the room's mode.")
		return
	net_mode = clampi(index,0,2)
	restart_round()

func restart_round():
	if not active or not multiplayer.is_server():
		game.toast("Only the host can restart the room.")
		return
	epoch += 1
	remaining = 90.0
	round_active = net_mode!=0
	it_peer = int(members.keys()[0])
	infected = [it_peer] if net_mode==2 else []
	tag_cooldown = 2.0
	for id in members:
		members[id].pose = []
		scores[id] = 0
	message = "Waiting for friends" if members.size()<2 else "Round started"
	_publish_room()

func _publish_room():
	var state = {"epoch":epoch,"map":map_id,"mode":net_mode,"remaining":remaining,"playing":round_active,"it":it_peer,"infected":infected,"scores":scores,"members":members.keys(),"message":message}
	_receive_room(state)
	_receive_room.rpc(state)

@rpc("authority", "call_remote", "reliable", 0)
func _receive_room(state: Dictionary):
	if not active:
		return
	var old_it = it_peer
	var was_infected = multiplayer.get_unique_id() in infected
	epoch = state.epoch
	map_id = state.map
	net_mode = state.mode
	remaining = state.remaining
	round_active = state.playing
	it_peer = state.it
	infected = state.infected.duplicate()
	scores = state.scores.duplicate()
	message = state.message
	connecting = false
	if not multiplayer.is_server():
		var updated = {}
		for id in state.members:
			updated[id] = members.get(id,{"pose":[]})
		members = updated
	for id in avatars.keys():
		if not members.has(id):
			avatars[id].queue_free()
			avatars.erase(id)
	for id in members:
		if id != multiplayer.get_unique_id() and not avatars.has(id):
			var avatar = Node3D.new()
			avatar.set_script(Avatar)
			add_child(avatar)
			avatar.setup(game,id)
			avatars[id] = avatar
		if avatars.has(id):
			avatars[id].set_tagged(id==it_peer if net_mode==1 else id in infected)
	if applied_epoch != epoch:
		applied_epoch = epoch
		game.map_index = map_id
		game.mode = 0
		game.build_map()
	game.hide_offline_objectives()
	if old_it!=it_peer or (not was_infected and multiplayer.get_unique_id() in infected):
		game.player.haptic(0,.7)
	game.toast(message,5)

func _process(delta):
	if connecting and Time.get_ticks_msec()>connect_deadline:
		leave_room("Connection timed out. Check host IP and UDP 7777.")
		return
	if not active or connecting:
		return
	if round_active and members.size()>=2:
		remaining = maxf(0,remaining-delta)
	tag_cooldown = maxf(0,tag_cooldown-delta)
	send_accumulator += delta
	if send_accumulator<.05:
		return
	send_accumulator = fmod(send_accumulator,.05)
	var pose = local_pose()
	if multiplayer.is_server():
		if valid_pose(pose):
			members[1].pose = pose
		if remaining<=0 and round_active:
			round_active = false
			message = "Time! Host can restart."
			_publish_room()
		check_tags()
		var poses = {}
		for id in members:
			if not members[id].pose.is_empty():
				poses[id] = members[id].pose
		_receive_snapshot(epoch,poses,remaining)
		_receive_snapshot.rpc(epoch,poses,remaining)
	else:
		_submit_pose.rpc_id(1,epoch,pose)

func local_pose() -> Array:
	var rotation = game.player.head.global_basis.orthonormalized().get_rotation_quaternion()
	return [game.player.head.global_position,rotation,game.player.palms[0].global_position,game.player.palms[1].global_position,game.cosmetic]

func valid_pose(pose: Array) -> bool:
	if pose.size()!=5 or not pose[0] is Vector3 or not pose[1] is Quaternion or not pose[2] is Vector3 or not pose[3] is Vector3 or not pose[4] is int:
		return false
	var head: Vector3 = pose[0]
	var rotation: Quaternion = pose[1]
	if not head.is_finite() or absf(head.x)>32 or absf(head.z)>32 or head.y< -15 or head.y>25 or not rotation.is_finite() or not rotation.is_normalized():
		return false
	for i in [2,3]:
		if not pose[i].is_finite() or head.distance_to(pose[i])>2.3:
			return false
	return pose[4]>=0 and pose[4]<5

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_pose(pose_epoch: int, pose: Array):
	if not active or not multiplayer.is_server() or pose_epoch!=epoch:
		return
	var sender = multiplayer.get_remote_sender_id()
	if members.has(sender) and valid_pose(pose):
		members[sender].pose = pose

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_snapshot(pose_epoch: int, poses: Dictionary, time_left: float):
	if not active or pose_epoch!=epoch:
		return
	remaining = time_left
	for id in poses:
		if avatars.has(id) and valid_pose(poses[id]):
			avatars[id].set_pose(poses[id])
		if members.has(id) and not multiplayer.is_server():
			members[id].pose = poses[id]

func check_tags():
	if not round_active or net_mode==0 or tag_cooldown>0 or members.size()<2:
		return
	for attacker in members:
		if (net_mode==1 and attacker!=it_peer) or (net_mode==2 and attacker not in infected):
			continue
		var attacker_pose: Array = members[attacker].pose
		if attacker_pose.is_empty():
			continue
		for victim in members:
			if victim==attacker or (net_mode==2 and victim in infected):
				continue
			var victim_pose: Array = members[victim].pose
			if victim_pose.is_empty():
				continue
			for hand in [attacker_pose[2],attacker_pose[3]]:
				var head: Vector3 = victim_pose[0]
				var nearest = Vector3(head.x,clampf(hand.y,head.y-.85,head.y),head.z)
				if hand.distance_to(nearest)>.43:
					continue
				# The host checks contact against map collision, so walls block tags.
				var query = PhysicsRayQueryParameters3D.create(hand,nearest,1)
				if not game.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
					continue
				scores[attacker] = int(scores.get(attacker,0))+1
				if net_mode==1:
					it_peer = victim
				else:
					infected.append(victim)
				tag_cooldown = 1.5
				message = "Runner "+str(victim).right(4)+" was tagged!"
				check_round_complete()
				_publish_room()
				return

func check_round_complete():
	if net_mode==2 and round_active and members.size()>=2 and infected.size()>=members.size():
		round_active = false
		message = "Everyone infected! Host can restart."

func status_line() -> String:
	if connecting:
		return "CONNECTING  /  "+address
	if not active:
		return "OFFLINE  /  Host or join a room"
	var mine = multiplayer.get_unique_id()
	var role = "YOU ARE IT" if net_mode==1 and mine==it_peer else "RUNNER"
	if net_mode==2:
		role = "INFECTED" if mine in infected else "SURVIVOR"
	if net_mode==0:
		role = "SOCIAL"
	return "%d / %d players  |  %s  |  %ds  |  Tags %d\n%s  /  %s" % [members.size(),MAX_PLAYERS,NET_MODES[net_mode],int(remaining),int(scores.get(mine,0)),role,message]

func local_addresses() -> String:
	if not host_ips.is_empty():
		return host_ips
	var ips: Array[String] = []
	for ip in IP.get_local_addresses():
		if not ":" in ip and not ip.begins_with("127.") and ip!="0.0.0.0":
			ips.append(ip)
	host_ips = ", ".join(ips) if not ips.is_empty() else "Check Wi-Fi settings for your IPv4 address"
	return host_ips
