extends Node

signal hole_punched

var server_udp = PacketPeerUDP.new()
var peer_udp = PacketPeerUDP.new()

export(String) var rendevouz_address = "" 
export(int) var max_player_count = 2
var rendevouz_port = 4000
var found_server = false
var peer_info = 0
var recieved_host_info = false
var peer_greet = 0
var peer_confirm = 0
var peer_go = 0

# warning-ignore:unused_class_variable
var is_host = false
var starting_game = false

var own_port
var peers = {}
var host_address
var host_port
var client_name
var p_timer
var cascade_timer
var session_id

var ports_tried = 0
var greets_sent = 0

const REGISTER_SESSION = "rs:"
const REGISTER_CLIENT = "rc:"
const EXCHANGE_PEERS = "ep:"

# warning-ignore:unused_argument
func _process(delta):
	if peer_udp.get_available_packet_count() > 0:
		var array_bytes = peer_udp.get_packet()
		var packet_string = array_bytes.get_string_from_ascii()

				
		if peer_greet < peer_info:
			if packet_string.begins_with("greet"):
				var m = packet_string.split(":")
				if !peers[m[3]].has("name"):
					peer_greet += 1
					var peer_used_port = m[2]
					peers[m[3]].name = m[1]
					if own_port != peer_used_port:
						own_port = peer_used_port
						print("Changing own port to: " + str(own_port))
						peer_udp.close()
						peer_udp.listen(own_port, "*")
						
					print("Sending confirm")
					
				
		if peer_confirm < peer_info:
			if packet_string.begins_with("confirm"):
				var m = packet_string.split(":")
				if !peers[m[2]].has("is_host"):
					var confirmed_port = int(m[1])
					print("Recieved confirm from: "+peers[m[2]].name + "for port: " + str(confirmed_port))
					if peers[m[2]].port != confirmed_port:
						peers[m[2]].port = confirmed_port
						print("Changing peer port to: " + str(own_port))
						peer_udp.set_dest_address(peers[m[2]], peers[m[2]].port)
						cascade_timer.stop()
						
					peers[m[2]].is_host = m[3]
					peers[m[2]].port = confirmed_port
					if peers[m[2]].is_host:
						host_address = peers[m[2]]
						host_port = peers[m[2]].port
					peer_udp.close()
					peer_udp.listen(peers[m[2]].port, "*")
					print("Sending go")
					peer_confirm += 1
					peer_udp.close()

				
		elif peer_go < peer_info:
			if packet_string.begins_with("go"):
				var m = packet_string.split(":")
				if !peers[m[1]].has("go"):
					print("Recieved go from: "+m[1])
					peer_go += 1
			if peer_go == peer_info:
				emit_signal("hole_punched")
				set_process(false)
		
	if server_udp.get_available_packet_count() > 0:
		var array_bytes = server_udp.get_packet()
		var packet_string = array_bytes.get_string_from_ascii()
		print("Recieved Packet from server: " + packet_string)
		
		if not found_server:
			if packet_string.begins_with("ok"):
				found_server=true
				print("Recieved ok from Rendezvous Server")
				var m = packet_string.split(":")
				own_port =int( m[1] )
				print("Own port is: " + str(own_port))
				print("Waiting for peer...")
				if is_host:
					emit_signal("port_updated")
					_send_client_to_server()
					
				
		elif peer_info == 0:
			if packet_string.begins_with("peer:"):
				var peer_list = packet_string.split(",")
				print("Recieved peer info")
				for i in peer_list:
					var m = packet_string.split(":")
					peers[m[1]] = {"port":m[2]}
					peer_info += 1
					print("Peer adress: " + m[1])
					print("Peer port: " + str( m[2]))
				start_peer_contact()
				
#func cascade_peer():
#	if peer_confirm < peer_info:
#		print("pinging on port " + str(ports_tried + peer_port) + " and above")
#		for i in range(ports_tried, ports_tried+10):
#			var p = peer_port + i
#			peer_udp.set_dest_address(peer_address, p)
#			var buffer = PoolByteArray()
#			buffer.append_array(("greet:"+ client_name+":"+str(p) ).to_utf8())
#			peer_udp.put_packet(buffer)
#			yield(get_tree(),"idle_frame")
#		ports_tried+=10
	

func ping_peer():
#	print("pinging peer...")
	if starting_game: return
	var buffer
	
	if peer_confirm < peer_info and greets_sent < 7:
#		print("sending:"+ str(buffer.get_string_from_utf8()))
		for p in peers.keys():
			peer_udp.set_dest_address(p, peers[p].port)
			buffer = PoolByteArray()
			buffer.append_array(("greet:"+ client_name+":"+str(peers[p].port)+":"+p.to_utf8()))
			peer_udp.put_packet(buffer)
			greets_sent+=1
			#if greets_sent == 6:
				#print("Receiving no confirm. Starting port cascade")
				#.start()
		
	elif peer_greet == peer_info and peer_go < peer_info:
		for p in peers.keys():
			peer_udp.set_dest_address(p, peers[p].port)
			buffer = PoolByteArray()
			buffer.append_array(("confirm:" + str(own_port)+":"+p+":"+str(is_host)).to_utf8())
	#		print("sending:"+ str(buffer.get_string_from_utf8()))
			peer_udp.put_packet(buffer)
		
	if  peer_confirm == peer_info:
		for p in peers.keys():
			peer_udp.set_dest_address(p, peers[p].port)
			buffer = PoolByteArray()
			buffer.append_array(("go:"+p).to_utf8())
	#		print("sending:"+ str(buffer.get_string_from_utf8()))
			peer_udp.put_packet(buffer)

func start_peer_contact():	
	server_udp.put_packet("goodbye".to_utf8())
	server_udp.close()
	if peer_udp.is_listening():
		peer_udp.close()
	#peer_udp.set_dest_address(peer_address, peer_port)
	
	var err = peer_udp.listen(own_port, "*")
	if err != OK:
		print("Error listening on port: " + str(own_port))
	else:
		print("Listening on port: " + str(own_port))
	p_timer.start()
	print("Contacting peer...")
	
func finalize_peers(id):
	var buffer = PoolByteArray()
	buffer.append_array((EXCHANGE_PEERS+str(id)).to_utf8())
	server_udp.close()
	server_udp.set_dest_address(rendevouz_address, rendevouz_port)
	server_udp.put_packet(buffer)
	
func start_traversal(id):
	if server_udp.is_listening():
		server_udp.close()
	var err = server_udp.listen(rendevouz_port, "*")
	if err != OK:
		print("Error listening on port: " + str(rendevouz_port) + " to server: " + rendevouz_address)
	else:
		print("Listening on port: " + str(rendevouz_port) + " to server: " + rendevouz_address)
		
	found_server = false
	peer_info = 0
	peer_greet = 0
	peer_confirm = 0
	peer_go = 0
	peers = {}

	ports_tried = 0
	greets_sent = 0
	session_id = id

	print("Connecting Rendezvouz Server...")
	
	if (is_host):
		var buffer = PoolByteArray()
		buffer.append_array((REGISTER_SESSION+session_id+":"+str(max_player_count)).to_utf8())
		server_udp.close()
		server_udp.set_dest_address(rendevouz_address, rendevouz_port)
		server_udp.put_packet(buffer)
	else:
		_send_client_to_server()
	
func _send_client_to_server():
	yield(get_tree().create_timer(2.0), "timeout")
	var buffer = PoolByteArray()
	buffer.append_array((REGISTER_CLIENT+client_name+":"+session_id).to_utf8())
	server_udp.close()
	server_udp.set_dest_address(rendevouz_address, rendevouz_port)
	server_udp.put_packet(buffer)
		
func _exit_tree():
	server_udp.close()
	
#func print(line):	get_node("/root/Lobby").print(line)
	
func _ready():
	p_timer = Timer.new()
	get_node("/root/").add_child(p_timer)
	p_timer.connect("timeout", self, "ping_peer")
	p_timer.wait_time = 0.3
	
#	cascade_timer = Timer.new()
#	get_node("/root/").add_child(cascade_timer)
#	cascade_timer.connect("timeout", self, "cascade_peer")
#	cascade_timer.wait_time = 0.2
