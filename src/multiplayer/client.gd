extends "common.gd"

const PING_TIMEOUT = 3
const PING_RETRY = 3

var server_ip
var server_port
var connected = false
var ping
var retry = 0

func start(game, ip, port):
	.start(game)
	if udp.listen(0) == OK:
		server_ip = ip
		server_port = port
		udp.set_send_address(ip, port)
		udp.put_var(new_packet(CMD_CS_CONNECT, global.local_player.get_name()))
		ping = OS.get_unix_time()
		return true
	else:
		return false

func send(pckt):
	udp.put_var(pckt)

func connection_accepted(args):
	connected = true
	print("Server accepted connection")
	for player_name in args:
		if not player_name in players.keys():
			var player = global.add_player(game_node, player_name, false)
			emit_signal("player_connected", player)
			players[player_name] = player
	for player_name in players.keys():
		if not player_name in args:
			emit_signal("player_disconnected", players[player_name])
			players.erase(player_name)

func ping(args):
	send(new_packet(CMD_CS_PONG, global.local_player.get_name()))
	ping = OS.get_unix_time()
	retry = 0

func pong(args):
	ping = OS.get_unix_time()
	retry = 0

func player_move(args):
	if args.player in players.keys():
		players[args.player].set_global_transform(args.transform)

func player_damage(args):
	if args.player in players.keys():
		players[args.player].damage(args.damage, args.regenerable, false)

func player_attack(args):
	if args.player in players.keys():
		players[args.player].weapon_node.set_rotation_deg(Vector3(args.rot, 0, 0))

func player_die(args):
	if args in players.keys():
		if players[args].hp > 0:
			players[args].die(false)

func player_use(args):
	if args.player in players.keys():
		players[args.player].items[args.item].use()

func player_connected(args):
	players[args.player] = global.add_player(game_node, args.player, false)
	players[args.player].set_global_transform(args.transform)
	emit_signal("player_connected", players[args.player])

func player_disconnected(args):
	emit_signal("player_disconnected", players[args])
	players.erase(args)

func handle_packet(pckt, ip, port):
	print("Received %s from %s:%s" % [pckt, ip, port])
	if not connected:
		if pckt.command == CMD_SC_CONNECT_ACCEPT:
			connection_accepted(pckt.args)
		elif pckt.command == CMD_SC_USERNAME_IN_USE:
			stop()
			global.stop_game()
	elif pckt.command == CMD_SC_PING:
		ping(pckt.args)
	elif pckt.command == CMD_SC_PONG:
		pong(pckt.args)
	elif pckt.command == CMD_SC_MOVE:
		player_move(pckt.args)
	elif pckt.command == CMD_SC_DAMAGE:
		player_damage(pckt.args)
	elif pckt.command == CMD_SC_ATTACK:
		player_attack(pckt.args)
	elif pckt.command == CMD_SC_DIE:
		player_die(pckt.args)
	elif pckt.command == CMD_SC_USE:
		player_use(pckt.args)
	elif pckt.command == CMD_SC_PLAYER_CONNECTED:
		player_connected(pckt.args)
	elif pckt.command == CMD_SC_PLAYER_DISCONNECTED:
		player_disconnected(pckt.args)
	elif pckt.command == CMD_SC_DOWN:
		stop()
		global.stop_game()
		print("Server shutdown!")

func process(delta):
	.process(delta)

	if OS.get_unix_time() - ping > PING_TIMEOUT:
		if retry > PING_RETRY:
			stop()
			print("Server didn't reply!")
		else:
			send(new_packet(CMD_CS_PING, global.local_player.get_name()))
			ping = OS.get_unix_time()
			retry += 1

func stop():
	.stop()
	if connected:
		print("Sending disconnect command to server")
		send(new_packet(CMD_CS_DISCONNECT, global.local_player.get_name()))
	connected = false
	emit_signal("disconnected")

func _exit_tree():
	stop()

func _on_used_item(item):
	var player = global.local_player
	var item_i = player.items.find(item)
	var pckt = new_packet(CMD_CS_USE, {'player': player.get_name(), 'item': item_i})
	udp.put_var(pckt)
