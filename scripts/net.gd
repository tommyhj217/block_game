# 네트워크 담당 (autoload 이름: Net)
# autoload: 게임이 켜질 때 자동으로 만들어져서 어느 화면에서나 `Net.함수()`로 쓸 수 있는 노드.
#           화면(씬)이 바뀌어도 사라지지 않아서 연결을 계속 유지할 수 있다.
#
# 구조
# - 방장 폰이 "서버", 나머지는 "손님(클라이언트)". 같은 핫스팟/와이파이 안에서 ENet으로 연결한다.
# - 방 자동 찾기: 손님이 "방 있어요?"(FIND) 신호를 같은 망 전체에 뿌리고(브로드캐스트),
#   방장이 그 신호를 받으면 손님에게 "여기 있어요"(ROOM) 답장을 보낸다.
# - 게임 중에는 각자 자기 판을 직접 계산하고, 판 모양·공격·탈락 소식만 주고받는다.
#
# 시그널(signal): "이런 일이 생겼어요"라고 알리는 신호. 다른 스크립트가 connect()로 받아서 함수를 실행한다.
#                 (Python의 콜백 등록과 비슷하다)
# @rpc: 다른 폰에서 이 함수를 원격으로 부를 수 있게 하는 표시.
#   "any_peer"  = 누구나 부를 수 있음 / "authority" = 방장만 부를 수 있음
#   "call_local" = 보낸 나 자신에게도 실행됨
#   "reliable"  = 꼭 도착함(순서 보장) / "unreliable_ordered" = 빠르지만 가끔 빠질 수 있음
extends Node

signal players_changed                                   # 방 사람 목록이 바뀜
signal room_found(ip: String, room_name: String, count: int)  # 방을 찾음
signal joined                                            # 방에 들어감
signal join_failed                                       # 방에 들어가지 못함
signal room_closed                                       # 방장이 나가서 방이 없어짐
signal state_received(id: int, data: PackedByteArray)    # 상대 판 모양이 도착함
signal attacked(from_id: int, kind: String, amount: int) # 공격을 받음
signal player_out(id: int)                               # 누군가 꽉 차서 탈락함
signal player_left(id: int)                              # 누군가 연결이 끊김

const GAME_SCENE := "res://scenes/game.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const SETTINGS_PATH := "user://settings.cfg"
const JOIN_TIMEOUT := 6.0   # 이 시간(초) 안에 연결이 안 되면 실패로 본다

var my_name := ""
var players := {}         # 방에 있는 사람들 {아이디: 이름}. 방장의 아이디는 항상 1
var match_players := {}   # 지금 판을 시작할 때 있던 사람들 {아이디: 이름}
var match_seed := 0       # 판마다 바뀌는 난수 씨앗
var in_room := false
var is_host := false
var last_message := ""    # 로비로 돌아갔을 때 보여 줄 안내 (예: 방이 닫혔어요)

var _disc: PacketPeerUDP = null   # 방 찾기용 UDP 소켓
var _searching := false
var _disc_timer := 0.0
var _join_timer := -1.0           # 0 이상이면 연결을 기다리는 중


# _ready(): 노드가 화면 나무(트리)에 들어와 준비가 끝났을 때 한 번 불린다. (Python의 __init__ 다음 단계)
func _ready() -> void:
	_load_name()
	# multiplayer: 이 게임의 네트워크 상태. 연결 사건이 생기면 아래 함수들이 불린다.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func my_id() -> int:
	return multiplayer.get_unique_id()


# ─── 이름 저장 ───

func _load_name() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		my_name = cfg.get_value("player", "name", "")
	if my_name.is_empty():
		my_name = "플레이어%d" % randi_range(1, 99)


func set_my_name(value: String) -> void:
	value = value.strip_edges().left(8)  # 화면에 들어가게 8글자까지만
	if value.is_empty():
		return
	my_name = value
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("player", "name", my_name)
	cfg.save(SETTINGS_PATH)


# ─── 방 만들기 / 들어가기 / 나가기 ───

# 방을 만든다. 성공하면 true.
func host_room() -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(Config.GAME_PORT, Config.MAX_PLAYERS - 1)
	if err != OK:
		push_warning("방 만들기 실패: %s" % err)
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	in_room = true
	players = {1: my_name}
	# 손님의 "방 있어요?" 신호를 받을 소켓을 연다
	_disc = PacketPeerUDP.new()
	if _disc.bind(Config.DISCOVERY_PORT) != OK:
		# 같은 PC에서 두 개를 켜서 시험할 때처럼 포트가 이미 쓰이면 자동 찾기만 안 된다
		push_warning("방 찾기 포트를 열지 못함 (번호로는 들어올 수 있음)")
		_disc = null
	players_changed.emit()
	return true


# 방장의 주소(ip)로 방에 들어간다. 결과는 joined / join_failed 신호로 알려 준다.
func join_room(ip: String) -> void:
	stop_search()
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), Config.GAME_PORT)
	if err != OK:
		join_failed.emit()
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	_join_timer = 0.0


# 방에서 나간다 (방장이면 방이 없어진다).
func leave() -> void:
	_join_timer = -1.0
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	# OfflineMultiplayerPeer: 혼자일 때 쓰는 가짜 연결. 내 아이디는 1이 된다.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _disc != null and not _searching:
		_disc.close()
		_disc = null
	in_room = false
	is_host = false
	players = {}


# ─── 방 자동 찾기 ───

func start_search() -> void:
	stop_search()
	_disc = PacketPeerUDP.new()
	_disc.set_broadcast_enabled(true)  # 망 전체에 뿌리는 신호를 보낼 수 있게 함
	_disc.bind(0)                      # 0 = 빈 포트 아무거나 (답장은 이 포트로 온다)
	_searching = true
	_disc_timer = Config.DISCOVERY_INTERVAL  # 바로 한 번 보내기


func stop_search() -> void:
	if _searching and _disc != null:
		_disc.close()
		_disc = null
	_searching = false


# 이 폰의 망 주소 목록 (예: 192.168.43.1). 방장 화면에 "내 번호"로 보여 준다.
func local_ips() -> Array:
	var result := []
	for ip in IP.get_local_addresses():
		if ip.contains(":"):
			continue  # IPv6는 건너뜀
		if ip.begins_with("127.") or ip.begins_with("169.254."):
			continue  # 자기 자신, 자동 할당 주소는 건너뜀
		result.append(ip)
	return result


# 방 찾기 신호를 보낼 곳들: 망 전체(255.255.255.255), 각 망의 끝 주소(x.x.x.255), 이 PC 자신
func _broadcast_targets() -> Array:
	var result := ["255.255.255.255", "127.0.0.1"]
	for ip in local_ips():
		var parts: PackedStringArray = ip.split(".")
		if parts.size() == 4:
			result.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	return result


# _process(delta): 매 프레임마다 불린다. delta는 지난 프레임부터 흐른 시간(초).
func _process(delta: float) -> void:
	# 연결 기다리는 시간 재기
	if _join_timer >= 0.0:
		_join_timer += delta
		if _join_timer > JOIN_TIMEOUT:
			leave()
			join_failed.emit()

	if _disc == null:
		return

	if _searching:
		# 손님: 일정 간격으로 "방 있어요?"를 뿌리고 답장을 받는다
		_disc_timer += delta
		if _disc_timer >= Config.DISCOVERY_INTERVAL:
			_disc_timer = 0.0
			var msg := ("%s|FIND" % Config.DISCOVERY_TAG).to_utf8_buffer()
			for target in _broadcast_targets():
				_disc.set_dest_address(target, Config.DISCOVERY_PORT)
				_disc.put_packet(msg)
		while _disc.get_available_packet_count() > 0:
			var text := _disc.get_packet().get_string_from_utf8()
			var ip := _disc.get_packet_ip()
			var parts := text.split("|")
			if parts.size() >= 4 and parts[0] == Config.DISCOVERY_TAG and parts[1] == "ROOM":
				room_found.emit(ip, parts[2], int(parts[3]))
	elif is_host:
		# 방장: "방 있어요?"를 받으면 보낸 손님에게 답장한다
		while _disc.get_available_packet_count() > 0:
			var text := _disc.get_packet().get_string_from_utf8()
			var ip := _disc.get_packet_ip()
			var port := _disc.get_packet_port()
			if text == "%s|FIND" % Config.DISCOVERY_TAG:
				var reply := "%s|ROOM|%s|%d" % [Config.DISCOVERY_TAG, my_name, players.size()]
				_disc.set_dest_address(ip, port)
				_disc.put_packet(reply.to_utf8_buffer())


# ─── 연결 사건 ───

func _on_connected_to_server() -> void:
	_join_timer = -1.0
	in_room = true
	# 방장에게 내 이름을 알린다. rpc_id(1, ...) = 아이디 1(방장)에게만 보냄
	_register.rpc_id(1, my_name)
	joined.emit()


func _on_connection_failed() -> void:
	leave()
	join_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	last_message = "방이 닫혔어요"
	room_closed.emit()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_peer_connected(_id: int) -> void:
	pass  # 이름은 _register로 받는다


func _on_peer_disconnected(id: int) -> void:
	if is_host:
		players.erase(id)
		_set_players.rpc(players)
		players_changed.emit()
	player_left.emit(id)


# ─── 방 사람 목록 ───

# 손님 → 방장: "제 이름은 ○○예요"
@rpc("any_peer", "reliable")
func _register(player_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if players.size() >= Config.MAX_PLAYERS:
		return
	players[id] = String(player_name).left(8)
	_set_players.rpc(players)
	players_changed.emit()


# 방장 → 모두: 지금 방 사람 목록
@rpc("authority", "reliable")
func _set_players(list: Dictionary) -> void:
	players = list
	players_changed.emit()


# ─── 판 시작 ───

# 방장이 "시작"을 누르면 모두에게 게임 화면을 연다.
func start_match() -> void:
	if not is_host or players.size() < 2:
		return
	_begin.rpc(randi(), players)


@rpc("authority", "reliable", "call_local")
func _begin(seed_value: int, list: Dictionary) -> void:
	match_seed = seed_value
	match_players = list
	get_tree().change_scene_to_file(GAME_SCENE)


# 혼자 연습: 연결 없이 게임 화면을 연다.
func start_practice() -> void:
	leave()
	match_seed = randi()
	match_players = {my_id(): my_name}
	get_tree().change_scene_to_file(GAME_SCENE)


func is_practice() -> bool:
	return match_players.size() < 2


func name_of(id: int) -> String:
	if match_players.has(id):
		return match_players[id]
	return players.get(id, "?")


# ─── 게임 중 주고받기 ───

# 내 판 모양을 모두에게 보낸다 (자주 보내므로 빠른 방식)
func send_state(data: PackedByteArray) -> void:
	if in_room:
		_state.rpc(data)


@rpc("any_peer", "unreliable_ordered")
func _state(data: PackedByteArray) -> void:
	state_received.emit(multiplayer.get_remote_sender_id(), data)


# 상대(target)에게 공격을 보낸다. kind: "garbage", "fast", "fog"
func send_attack(target: int, kind: String, amount: int) -> void:
	if in_room:
		_attack.rpc_id(target, kind, amount)


@rpc("any_peer", "reliable")
func _attack(kind: String, amount: int) -> void:
	attacked.emit(multiplayer.get_remote_sender_id(), kind, amount)


# 내가 꽉 차서 탈락했다고 모두에게 알린다 (나에게도 실행됨)
func send_out() -> void:
	if in_room:
		_out.rpc(my_id())
	else:
		player_out.emit(my_id())


@rpc("any_peer", "reliable", "call_local")
func _out(id: int) -> void:
	player_out.emit(id)
