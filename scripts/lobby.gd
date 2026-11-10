# 첫 화면(로비). 이름 정하기, 혼자 연습, 방 만들기, 방 찾기, 방에서 기다리기.
# 화면 4장을 만들어 두고 하나만 보이게 바꿔 가며 쓴다.
extends Control

var _theme := Theme.new()
var _stage: Control
var _pages := {}             # 화면 이름 → VBoxContainer
var _name_edit: LineEdit
var _host_info: Label
var _host_list: Label
var _start_button: Button
var _hidden_start_button: Button
var _guest_list: Label
var _room_box: VBoxContainer  # 찾은 방 버튼들이 들어가는 곳
var _ip_edit: LineEdit
var _search_status: Label
var _main_message: Label
var _found := {}             # 찾은 방 주소 → 버튼 (같은 방이 여러 번 안 나오게)


func _ready() -> void:
	_theme.default_font_size = 34
	theme = _theme

	var bg := ColorRect.new()
	bg.color = Config.SCREEN_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 화면 비율이 달라도 내용이 가운데 오도록 720x1280 무대 안에 놓는다 (game.gd와 같은 방식)
	_stage = Control.new()
	_stage.size = Vector2(720, 1280)
	add_child(_stage)
	_center_stage()
	get_viewport().size_changed.connect(_center_stage)

	_build_main()
	_build_host()
	_build_search()
	_build_guest()

	Net.players_changed.connect(_refresh_players)
	Net.room_found.connect(_on_room_found)
	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)

	# 게임에서 돌아왔을 때 아직 방 안이면 방 화면을 보여 준다
	if Net.in_room:
		_show("host" if Net.is_host else "guest")
		_refresh_players()
	else:
		_show("main")
		_main_message.text = Net.last_message
		Net.last_message = ""


# ─── 화면 만들기 도우미 ───

func _center_stage() -> void:
	_stage.position = ((get_viewport_rect().size - _stage.size) / 2.0).floor()


func _new_page(page_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = Vector2(60, 80)
	box.size = Vector2(600, 1120)
	box.add_theme_constant_override("separation", 26)
	_stage.add_child(box)
	_pages[page_name] = box
	return box


func _title(box: Control, text: String, font_size: int = 56) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	box.add_child(l)
	return l


func _button(box: Control, text: String, callback: Callable, color := Color("#3a4a78")) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(600, 150)
	b.add_theme_font_size_override("font_size", 44)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color
		if state == "pressed":
			s.bg_color = color.lightened(0.25)
		elif state == "disabled":
			s.bg_color = color.darkened(0.5)
		s.set_corner_radius_all(28)
		b.add_theme_stylebox_override(state, s)
	b.pressed.connect(callback)
	box.add_child(b)
	return b


func _show(page_name: String) -> void:
	for key in _pages:
		_pages[key].visible = key == page_name


# ─── 첫 화면 ───

func _build_main() -> void:
	var box := _new_page("main")
	_title(box, "와르르\n블록 대전", 72)

	var name_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "내 이름"
	name_label.custom_minimum_size = Vector2(170, 0)
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.text = Net.my_name
	_name_edit.max_length = 8
	_name_edit.custom_minimum_size = Vector2(430, 100)
	_name_edit.add_theme_font_size_override("font_size", 40)
	_name_edit.text_changed.connect(func(t): Net.set_my_name(t))
	name_row.add_child(_name_edit)
	box.add_child(name_row)

	_button(box, "🏠 방 만들기", _on_host_pressed, Color("#3d6a4f"))
	_button(box, "🔍 방 찾기", _on_search_pressed, Color("#3a4a78"))
	_button(box, "🎮 블록 혼자 연습", func(): Net.start_practice("blocks"), Color("#5a4a78"))
	_button(box, "🖼 숨은그림 찾기", func(): Net.start_practice("hidden"), Color("#6a5a3d"))

	_main_message = _title(box, "", 30)
	var help := _title(box, "같이 하려면 한 명이 핫스팟을 켜고\n다른 사람은 그 와이파이에 연결해요", 26)
	help.modulate = Color(1, 1, 1, 0.7)


func _on_host_pressed() -> void:
	Net.set_my_name(_name_edit.text)
	if Net.host_room():
		_show("host")
		_refresh_players()
	else:
		_main_message.text = "방을 만들지 못했어요"


func _on_search_pressed() -> void:
	Net.set_my_name(_name_edit.text)
	for child in _room_box.get_children():
		child.queue_free()
	_found.clear()
	_search_status.text = "방을 찾고 있어요..."
	Net.start_search()
	_show("search")


# ─── 방장 화면 ───

func _build_host() -> void:
	var box := _new_page("host")
	_title(box, "🏠 내 방")
	_host_info = _title(box, "", 28)
	_host_list = _title(box, "", 38)
	_host_list.custom_minimum_size = Vector2(600, 300)
	_start_button = _button(box, "▶ 블록 대전", func(): Net.start_match("blocks"), Color("#3d6a4f"))
	_hidden_start_button = _button(box, "▶ 숨은그림 대결", func(): Net.start_match("hidden"), Color("#6a5a3d"))
	_button(box, "나가기", _on_leave_pressed, Color("#5a3d3d"))


# ─── 방 찾기 화면 ───

func _build_search() -> void:
	var box := _new_page("search")
	_title(box, "🔍 방 찾기")
	_search_status = _title(box, "", 30)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 480)
	box.add_child(scroll)
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 16)
	scroll.add_child(_room_box)

	# 자동으로 안 찾아질 때: 방장 화면의 번호를 직접 넣기
	var hint := _title(box, "안 보이면 방장 화면의 번호를 넣어요", 26)
	hint.modulate = Color(1, 1, 1, 0.7)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.0.1"
	_ip_edit.custom_minimum_size = Vector2(400, 110)
	_ip_edit.add_theme_font_size_override("font_size", 36)
	row.add_child(_ip_edit)
	var go := Button.new()
	go.text = "연결"
	go.custom_minimum_size = Vector2(188, 110)
	go.pressed.connect(func(): _join(_ip_edit.text))
	row.add_child(go)
	box.add_child(row)

	_button(box, "뒤로", _on_leave_pressed, Color("#5a3d3d"))


func _on_room_found(ip: String, room_name: String, count: int) -> void:
	var text := "%s의 방 (%d명)" % [room_name, count]
	if _found.has(ip):
		_found[ip].text = text  # 이미 있는 방은 인원만 바꿈
		return
	var b := _button(_room_box, text, func(): _join(ip), Color("#3d6a4f"))
	b.custom_minimum_size = Vector2(580, 130)
	_found[ip] = b
	_search_status.text = "들어갈 방을 눌러요"


func _join(ip: String) -> void:
	if ip.strip_edges().is_empty():
		return
	_search_status.text = "연결하는 중..."
	Net.join_room(ip)


func _on_joined() -> void:
	_show("guest")
	_refresh_players()


func _on_join_failed() -> void:
	_search_status.text = "연결하지 못했어요. 다시 해 볼까요?"
	# 다시 찾기 시작
	Net.start_search()


# ─── 손님 화면 ───

func _build_guest() -> void:
	var box := _new_page("guest")
	_title(box, "🙌 방에 들어왔어요")
	_guest_list = _title(box, "", 38)
	_guest_list.custom_minimum_size = Vector2(600, 420)
	_title(box, "방장이 시작하기를 기다려요", 30)
	_button(box, "나가기", _on_leave_pressed, Color("#5a3d3d"))


# ─── 공통 ───

func _refresh_players() -> void:
	var lines := []
	var ids: Array = Net.players.keys()
	ids.sort()  # 방장(1)이 맨 위
	for id in ids:
		var mark := "👑 " if id == 1 else "🙂 "
		var me := " (나)" if id == Net.my_id() else ""
		lines.append(mark + str(Net.players[id]) + me)
	var text := "\n".join(lines)
	_host_list.text = text
	_guest_list.text = text
	var can_start := Net.players.size() >= 2
	_start_button.disabled = not can_start
	_start_button.text = "▶ 블록 대전" if can_start else "친구를 기다려요"
	_hidden_start_button.disabled = not can_start
	_hidden_start_button.visible = can_start   # 친구가 들어오면 두 가지 놀이 중 고를 수 있다
	var ips := Net.local_ips()
	_host_info.text = "내 번호: %s" % (", ".join(ips) if not ips.is_empty() else "없음 (와이파이를 확인해요)")


func _on_leave_pressed() -> void:
	Net.stop_search()
	Net.leave()
	_show("main")
