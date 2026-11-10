# 게임 화면. 내 판을 움직이고(시간, 조작), 상대 판을 보여 주고, 공격·아이템·승패를 처리한다.
# 블록 규칙은 Board, 그리기는 BoardView, 네트워크는 Net(autoload)에게 맡긴다.
# 화면은 코드로 만든다(_build_ui). 위치와 크기는 맨 위 상수에서 바꾼다.
extends Control

# ─── 화면 배치 (기준 화면 720 x 1280) ───
const OPP_TOP := 12.0          # 상대 판 줄의 위쪽
const OPP_HEIGHT := 236.0      # 상대 판 줄 높이 (이름 포함)
const BOARD_RECT := Rect2(40, 262, 380, 760)   # 내 판 (칸 38px)
const METER_RECT := Rect2(14, 262, 16, 760)    # 방해 줄 대기 막대
const SIDE_X := 440.0          # 오른쪽 정보 칸 시작 x
const SIDE_W := 264.0          # 오른쪽 정보 칸 너비
const PAD_TOP := 1058.0        # 조작 버튼 줄 위쪽
const PAD_SIZE := Vector2(132, 190)  # 조작 버튼 크기
const PAD_GAP := 10.0
const ITEM_PAD_RECT := Rect2(477, 760, 190, 190)  # 아이템 쓰기 버튼

const STAGE_SIZE := Vector2(720, 1280)

var board := Board.new()
var stage: Control         # 모든 화면 요소를 담는 720x1280 틀
var view: BoardView
var preview: PiecePreview
var meter: ColorRect
var meter_fill: ColorRect
var info_label: Label
var effect_label: Label
var target_label: Label
var toast_label: Label
var item_slots: Array[Label] = []
var overlay: Control = null

# 조작 버튼: 이름 → 버튼 그림(Panel). 터치는 _input에서 직접 처리해서 여러 손가락을 동시에 쓸 수 있다.
var pads := {}
var _touch_owner := {}   # 손가락 번호 → 누르고 있는 버튼 이름
var held := {"left": false, "right": false, "down": false}
var _repeat := {"left": 0.0, "right": 0.0}

# 상대 판: 아이디 → {"view": BoardView, "label": Label, "button": Button}
var opponents := {}
var alive := {}          # 아이디 → 아직 살아 있는지 (나 포함)
var target_id := 0       # 공격 목표 (0이면 자동으로 고름)

var items: Array[String] = []  # 가지고 있는 아이템 (앞에서부터 씀)
var pending_garbage := 0       # 받을 예정인 방해 줄 수
var effects := {"fast": 0.0, "fog": 0.0, "shield": 0.0}  # 남은 효과 시간(초)

var fall_timer := 0.0
var lock_timer := 0.0
var lock_resets := 0
var send_timer := 0.0
var keepalive_timer := 0.0
var state_dirty := true
var finished := false   # 판 전체가 끝났는지
var practice := false
var my_id := 1
var _toast_time := 0.0


func _ready() -> void:
	my_id = Net.my_id()
	practice = Net.is_practice()
	board.reset(Net.match_seed + my_id * 7919)
	if practice:
		# 혼자 연습할 때는 나에게 쓰는 아이템만 나온다
		board.item_pool = []
		for key in Config.ITEM_ORDER:
			if not Config.ITEMS[key]["target"]:
				board.item_pool.append(key)
	for id in Net.match_players:
		alive[id] = true

	_build_ui()

	# Net의 신호를 받으면 실행할 함수를 연결한다
	Net.state_received.connect(_on_state_received)
	Net.attacked.connect(_on_attacked)
	Net.player_out.connect(_on_player_out)
	Net.player_left.connect(_on_player_left)

	_spawn_next()
	_show_toast("시작!" if practice else "대전 시작!")


# ═══════════════ 화면 만들기 ═══════════════

func _build_ui() -> void:
	# 글자 크기를 한 번에 정하는 테마
	var theme_res := Theme.new()
	theme_res.default_font_size = 28
	theme = theme_res

	var bg := ColorRect.new()
	bg.color = Config.SCREEN_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 모든 내용은 720x1280 크기의 "무대" 안에 놓고, 무대를 화면 가운데에 둔다.
	# (폰마다 화면 비율이 달라서 남는 공간이 생겨도 내용이 한쪽으로 쏠리지 않게)
	stage = Control.new()
	stage.size = STAGE_SIZE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	_center_stage()
	# size_changed: 창 크기가 바뀌면 오는 신호. 그때마다 다시 가운데로
	get_viewport().size_changed.connect(_center_stage)

	_build_opponents()

	# 내 판
	view = BoardView.new()
	view.position = BOARD_RECT.position
	view.size = BOARD_RECT.size
	stage.add_child(view)

	# 방해 줄 대기 막대 (빨간 부분이 차오를수록 곧 방해 줄이 올라온다)
	meter = ColorRect.new()
	meter.color = Config.BOARD_BG
	meter.position = METER_RECT.position
	meter.size = METER_RECT.size
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(meter)
	meter_fill = ColorRect.new()
	meter_fill.color = Color("#ff6b6b")
	meter_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_child(meter_fill)

	# 오른쪽 정보 칸
	var next_title := _make_label("다음", 26, Vector2(SIDE_X, 262), Vector2(SIDE_W, 36))
	next_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview = PiecePreview.new()
	preview.position = Vector2(SIDE_X + 52, 302)
	preview.size = Vector2(160, 220)
	stage.add_child(preview)

	info_label = _make_label("", 26, Vector2(SIDE_X, 536), Vector2(SIDE_W, 80))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_label = _make_label("", 26, Vector2(SIDE_X, 616), Vector2(SIDE_W, 70))
	effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_label = _make_label("", 22, Vector2(SIDE_X, 690), Vector2(SIDE_W, 60))
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 아이템 버튼과 그 아래 대기 중인 아이템 칸
	_add_pad("item", ITEM_PAD_RECT, "", Color("#3b3360"))
	for i in range(Config.ITEM_MAX - 1):
		var slot := _make_label("", 40, Vector2(ITEM_PAD_RECT.position.x + 20 + i * 80, 958), Vector2(70, 60))
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_slots.append(slot)

	# 조작 버튼 5개: ← → ↻ ⬇ ⤓
	var names := ["left", "right", "rotate", "down", "drop"]
	var icons := ["◀", "▶", "↻", "▼", "⤓"]
	var colors := [Color("#2f3a56"), Color("#2f3a56"), Color("#3d5a4a"), Color("#2f3a56"), Color("#5a3d3d")]
	for i in range(names.size()):
		var rect := Rect2(Vector2(14 + i * (PAD_SIZE.x + PAD_GAP), PAD_TOP), PAD_SIZE)
		_add_pad(names[i], rect, icons[i], colors[i])

	# 화면 가운데에 잠깐 뜨는 안내 글
	toast_label = _make_label("", 48, Vector2(BOARD_RECT.position.x, 520), Vector2(BOARD_RECT.size.x, 120))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_label.add_theme_constant_override("outline_size", 10)

	_refresh_side()


# 위쪽 상대 판 줄. 혼자 연습이면 안내 글만 놓는다.
func _build_opponents() -> void:
	var ids: Array = []
	for id in Net.match_players:
		if id != my_id:
			ids.append(id)
	if ids.is_empty():
		var title := _make_label("혼자 연습", 44, Vector2(0, OPP_TOP + 40), Vector2(720, 70))
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var hint := _make_label("🧹 아래 청소  🛡 방패 아이템이 나와요", 24, Vector2(0, OPP_TOP + 120), Vector2(720, 50))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	# 상대 수에 맞게 가로로 나눈다
	var slot_w := minf(140.0, 696.0 / ids.size())
	var start_x := (720.0 - slot_w * ids.size()) / 2.0
	for i in range(ids.size()):
		var id: int = ids[i]
		var x := start_x + i * slot_w
		var v := BoardView.new()
		v.position = Vector2(x + 6, OPP_TOP + 34)
		v.size = Vector2(slot_w - 12, OPP_HEIGHT - 34)
		stage.add_child(v)
		var label := _make_label(Net.name_of(id), 22, Vector2(x, OPP_TOP), Vector2(slot_w, 32))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text = true
		# 상대 판을 누르면 공격 목표로 고른다. 투명한 버튼을 판 위에 덮는다.
		var b := Button.new()
		b.flat = true
		b.position = Vector2(x, OPP_TOP)
		b.size = Vector2(slot_w, OPP_HEIGHT)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_opponent_pressed.bind(id))  # bind: 함수에 id 값을 미리 붙여 둠
		stage.add_child(b)
		opponents[id] = {"view": v, "label": label, "button": b}


func _center_stage() -> void:
	var vp := get_viewport_rect().size
	stage.position = ((vp - STAGE_SIZE) / 2.0).floor()


func _make_label(text: String, font_size: int, pos: Vector2, label_size: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = label_size
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	return l


# 조작 버튼 하나를 만든다. 모양만 만들고 터치는 _input에서 처리한다.
func _add_pad(pad_name: String, rect: Rect2, icon: String, color: Color) -> void:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(24)
	p.add_theme_stylebox_override("panel", style)
	stage.add_child(p)
	var l := Label.new()
	l.text = icon
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 72)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	pads[pad_name] = {"panel": p, "label": l, "style": style, "color": color}


# ═══════════════ 조작 ═══════════════

# _input: 화면의 모든 입력이 먼저 여기로 온다.
# InputEventScreenTouch(손가락 닿음/뗌)와 InputEventScreenDrag(손가락 끌기)를 직접 보고
# 손가락 번호(index)마다 어느 버튼을 누르는지 기억한다. 그래서 ◀를 누른 채 ⤓도 누를 수 있다.
func _input(event: InputEvent) -> void:
	if overlay != null:
		return  # 결과 화면이 떠 있으면 조작 버튼은 쉰다
	if event is InputEventScreenTouch:
		if event.pressed:
			var pad_name := _pad_at(event.position)
			if pad_name != "":
				_touch_owner[event.index] = pad_name
				_pad_down(pad_name)
		elif _touch_owner.has(event.index):
			_pad_up(_touch_owner[event.index])
			_touch_owner.erase(event.index)
	elif event is InputEventScreenDrag:
		# 손가락이 버튼 밖으로 나가면 뗀 것으로 본다 (◀▶▼만)
		if _touch_owner.has(event.index):
			var owner_name: String = _touch_owner[event.index]
			if held.has(owner_name) and _pad_at(event.position) != owner_name:
				_pad_up(owner_name)
				_touch_owner.erase(event.index)


# PC에서 시험할 때 키보드로도 조작 (←→↓, ↑/X 돌리기, 스페이스 떨어뜨리기, C 아이템)
func _unhandled_key_input(event: InputEvent) -> void:
	if overlay != null or not (event is InputEventKey) or event.echo:
		return
	var map := {KEY_LEFT: "left", KEY_RIGHT: "right", KEY_DOWN: "down", KEY_UP: "rotate",
			KEY_X: "rotate", KEY_SPACE: "drop", KEY_C: "item"}
	if map.has(event.keycode):
		if event.pressed:
			_pad_down(map[event.keycode])
		else:
			_pad_up(map[event.keycode])


func _pad_at(pos: Vector2) -> String:
	for pad_name in pads:
		var p: Panel = pads[pad_name]["panel"]
		if p.get_global_rect().has_point(pos):
			return pad_name
	return ""


func _pad_down(pad_name: String) -> void:
	_set_pad_look(pad_name, true)
	if finished or board.game_over:
		return
	match pad_name:
		"left":
			held["left"] = true
			_repeat["left"] = 0.0
			_move(-1)
		"right":
			held["right"] = true
			_repeat["right"] = 0.0
			_move(1)
		"down":
			held["down"] = true
			fall_timer = Config.SOFT_DROP_INTERVAL  # 누르자마자 한 칸 내려가게
		"rotate":
			if board.try_rotate(1):
				_after_move()
		"drop":
			_after_lock(board.hard_drop())
		"item":
			_use_item()


func _pad_up(pad_name: String) -> void:
	_set_pad_look(pad_name, false)
	if held.has(pad_name):
		held[pad_name] = false


# 누르는 동안 버튼 색을 밝게
func _set_pad_look(pad_name: String, down: bool) -> void:
	if not pads.has(pad_name):
		return
	var info: Dictionary = pads[pad_name]
	var style: StyleBoxFlat = info["style"]
	style.bg_color = info["color"].lightened(0.3) if down else info["color"]


func _move(dx: int) -> void:
	if board.try_move(dx, 0):
		_after_move()


# 블록이 옆으로 움직이거나 돌았을 때: 바닥에 닿아 있으면 굳는 시간을 다시 늘려 준다
func _after_move() -> void:
	if _on_ground() and lock_resets < Config.LOCK_RESET_LIMIT:
		lock_timer = 0.0
		lock_resets += 1
	state_dirty = true
	_refresh_board()


func _on_ground() -> bool:
	return board.piece_type >= 0 and not board.fits(board.piece_type, board.piece_rot, board.piece_pos + Vector2i(0, 1))


# ═══════════════ 시간 흐름 ═══════════════

func _process(delta: float) -> void:
	_update_toast(delta)
	_update_effects(delta)
	_send_state_if_needed(delta)
	if finished or board.game_over or board.piece_type < 0:
		return

	# ◀ ▶ 를 누르고 있으면 잠깐 뒤부터 계속 움직인다
	for dir_name in ["left", "right"]:
		if held[dir_name]:
			_repeat[dir_name] += delta
			while _repeat[dir_name] >= Config.MOVE_REPEAT_DELAY + Config.MOVE_REPEAT_RATE:
				_repeat[dir_name] -= Config.MOVE_REPEAT_RATE
				_move(-1 if dir_name == "left" else 1)

	# 중력: 시간이 되면 한 칸 내려간다
	var interval := _fall_interval()
	if held["down"]:
		interval = minf(interval, Config.SOFT_DROP_INTERVAL)
	fall_timer += delta
	while fall_timer >= interval:
		fall_timer -= interval
		if board.try_move(0, 1):
			state_dirty = true
			_refresh_board()
		else:
			fall_timer = 0.0
			break

	# 바닥에 닿아 있으면 잠시 뒤 굳는다
	if _on_ground():
		lock_timer += delta
		if lock_timer >= Config.LOCK_DELAY:
			_after_lock(board.lock_piece())
	else:
		lock_timer = 0.0


# 지금 한 칸 떨어지는 데 걸리는 시간. 레벨이 오르면 빨라지고, ⚡ 를 맞으면 더 빨라진다.
func _fall_interval() -> float:
	var t := maxf(Config.FALL_MIN, Config.FALL_START - board.level() * Config.FALL_STEP)
	if effects["fast"] > 0.0:
		t *= Config.FAST_MULTIPLIER
	return t


func _update_effects(delta: float) -> void:
	var changed := false
	for key in effects:
		if effects[key] > 0.0:
			effects[key] = maxf(0.0, effects[key] - delta)
			changed = true
	if changed:
		view.fog = effects["fog"] > 0.0
		view.shielded = effects["shield"] > 0.0
		view.queue_redraw()
		_refresh_effects()


# 내 판이 바뀌었으면 상대에게 보낸다. 바뀌지 않아도 1초마다 한 번은 보낸다(빠진 신호 대비).
func _send_state_if_needed(delta: float) -> void:
	if practice:
		return
	send_timer += delta
	keepalive_timer += delta
	if (state_dirty and send_timer >= Config.STATE_SEND_INTERVAL) or keepalive_timer >= 1.0:
		Net.send_state(board.snapshot())
		send_timer = 0.0
		keepalive_timer = 0.0
		state_dirty = false


# ═══════════════ 블록이 굳은 뒤 ═══════════════

func _after_lock(result: Dictionary) -> void:
	var lines: int = result["lines"]
	# 지운 줄에 있던 아이템 얻기
	for key in result["items"]:
		if items.size() < Config.ITEM_MAX:
			items.append(key)
			_show_toast("%s 얻었다!" % Config.ITEMS[key]["icon"])
	if lines > 0:
		if lines >= 2:
			_show_toast("%d줄!" % lines)
		# 지운 만큼 공격. 받을 예정인 방해 줄이 있으면 먼저 그만큼 없앤다(막기).
		var send: int = Config.GARBAGE_FOR_LINES[mini(lines, 4)]
		var cancel := mini(pending_garbage, send)
		pending_garbage -= cancel
		send -= cancel
		if send > 0 and not practice:
			_send_attack("garbage", send)
	elif pending_garbage > 0:
		# 줄을 못 지웠으면 기다리던 방해 줄이 올라온다
		board.add_garbage(pending_garbage, board.random_hole())
		pending_garbage = 0
	state_dirty = true
	if board.game_over:
		_i_lost()
		return
	_spawn_next()


func _spawn_next() -> void:
	fall_timer = 0.0
	lock_timer = 0.0
	lock_resets = 0
	if not board.spawn():
		_refresh_board()
		_i_lost()
		return
	_refresh_board()
	_refresh_side()


# ═══════════════ 공격과 아이템 ═══════════════

# 공격할 상대를 고른다: 고른 상대가 살아 있으면 그 상대, 아니면 살아 있는 상대 중 무작위.
func _pick_target() -> int:
	if target_id != 0 and alive.get(target_id, false):
		return target_id
	var list := []
	for id in alive:
		if id != my_id and alive[id]:
			list.append(id)
	if list.is_empty():
		return 0
	return list[randi_range(0, list.size() - 1)]


func _send_attack(kind: String, amount: int) -> void:
	var t := _pick_target()
	if t == 0:
		return
	Net.send_attack(t, kind, amount)
	var icon: String = "🧱" if kind == "garbage" else Config.ITEMS[kind]["icon"]
	_show_toast("%s → %s" % [icon, Net.name_of(t)])


func _use_item() -> void:
	if items.is_empty():
		return
	var key: String = items.pop_front()
	match key:
		"garbage":
			_send_attack("garbage", Config.ITEM_GARBAGE_LINES)
		"fast", "fog":
			_send_attack(key, 0)
		"sweep":
			board.clear_bottom(Config.ITEM_SWEEP_LINES)
			_show_toast("🧹 깨끗!")
		"shield":
			effects["shield"] = Config.ITEM_DURATION
			pending_garbage = 0
			view.shielded = true
			_show_toast("🛡 방패!")
	state_dirty = true
	_refresh_board()
	_refresh_side()


# 상대가 나를 공격했다
func _on_attacked(from_id: int, kind: String, amount: int) -> void:
	if finished or board.game_over:
		return
	if effects["shield"] > 0.0:
		_show_toast("🛡 막았다!")
		return
	var who := Net.name_of(from_id)
	match kind:
		"garbage":
			pending_garbage = mini(pending_garbage + amount, Config.GARBAGE_MAX_PENDING)
			_show_toast("%s의 🧱 %d줄" % [who, amount])
		"fast":
			effects["fast"] = Config.ITEM_DURATION
			_show_toast("%s의 ⚡ 빨라져라!" % who)
		"fog":
			effects["fog"] = Config.ITEM_DURATION
			view.fog = true
			_show_toast("%s의 🌫 안개!" % who)
	_refresh_side()


func _on_opponent_pressed(id: int) -> void:
	if not alive.get(id, false):
		return
	# 같은 상대를 다시 누르면 자동 고르기로 돌아간다
	target_id = 0 if target_id == id else id
	_refresh_opponents()
	_refresh_side()


# ═══════════════ 상대 소식 ═══════════════

func _on_state_received(id: int, data: PackedByteArray) -> void:
	if opponents.has(id):
		opponents[id]["view"].set_cells(data)


func _on_player_out(id: int) -> void:
	if not alive.has(id) or not alive[id]:
		return
	alive[id] = false
	if id == target_id:
		target_id = 0
	if id != my_id and opponents.has(id):
		_show_toast("%s 탈락" % Net.name_of(id))
	_refresh_opponents()
	_refresh_side()
	_check_end()


func _on_player_left(id: int) -> void:
	if opponents.has(id) and alive.get(id, false):
		opponents[id]["label"].text = "%s (나감)" % Net.name_of(id)
		_on_player_out(id)


# 내가 꽉 찼다
func _i_lost() -> void:
	board.game_over = true
	for key in held:
		held[key] = false
	view.dimmed = true
	_refresh_board()
	if practice:
		finished = true
		_show_result("꽉 찼어요!\n%d줄 지웠어요" % board.lines_total)
		return
	_show_toast("꽉 찼어요!")
	Net.send_state(board.snapshot())
	Net.send_out()


# 살아 있는 사람이 한 명 이하면 판이 끝난다
func _check_end() -> void:
	if practice or finished:
		return
	var left := []
	for id in alive:
		if alive[id]:
			left.append(id)
	if left.size() > 1:
		return
	finished = true
	var text := "무승부!"
	if left.size() == 1:
		text = "🏆 이겼어요!" if left[0] == my_id else "🏆 %s 승리!" % Net.name_of(left[0])
	# 이긴 사람의 마지막 판 모양을 모두에게 한 번 더 보낸다
	Net.send_state(board.snapshot())
	_show_result(text)


# ═══════════════ 화면 갱신 ═══════════════

func _refresh_board() -> void:
	view.set_cells(board.snapshot(false))
	view.active = []
	view.ghost = []
	if board.piece_type >= 0 and not board.game_over:
		view.active = board.piece_cells()
		var g := board.cells_at(board.piece_type, board.piece_rot, board.piece_pos + Vector2i(0, board.drop_distance()))
		view.ghost = g
		view.set_cells(board.snapshot(true))
	view.queue_redraw()


func _refresh_side() -> void:
	preview.set_types(board.next_queue.slice(0, Config.NEXT_PREVIEW))
	info_label.text = "%d줄  레벨 %d" % [board.lines_total, board.level() + 1]
	# 아이템 버튼에는 다음에 쓸 아이템, 아래 칸에는 그다음 아이템들
	var item_label: Label = pads["item"]["label"]
	item_label.text = Config.ITEMS[items[0]]["icon"] if items.size() > 0 else ""
	for i in range(item_slots.size()):
		item_slots[i].text = Config.ITEMS[items[i + 1]]["icon"] if items.size() > i + 1 else "·"
	# 방해 줄 대기 막대
	var ratio := float(pending_garbage) / Config.ROWS
	meter_fill.size = Vector2(METER_RECT.size.x, METER_RECT.size.y * minf(ratio, 1.0))
	meter_fill.position = Vector2(0, METER_RECT.size.y - meter_fill.size.y)
	if practice:
		target_label.text = ""
	elif target_id != 0:
		target_label.text = "목표: %s" % Net.name_of(target_id)
	else:
		target_label.text = "목표: 자동\n(상대 판을 누르면 고름)"
	_refresh_effects()


func _refresh_effects() -> void:
	var parts := []
	for key in ["fast", "fog", "shield"]:
		if effects[key] > 0.0:
			parts.append("%s %d" % [Config.ITEMS[key]["icon"], ceili(effects[key])])
	effect_label.text = "  ".join(parts)


func _refresh_opponents() -> void:
	for id in opponents:
		var v: BoardView = opponents[id]["view"]
		v.dimmed = not alive.get(id, false)
		v.highlighted = id == target_id
		v.queue_redraw()


func _show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	_toast_time = 1.2


func _update_toast(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		# 마지막 0.3초 동안 서서히 사라짐
		toast_label.modulate.a = clampf(_toast_time / 0.3, 0.0, 1.0)


# ═══════════════ 결과 화면 ═══════════════

func _show_result(text: String) -> void:
	if overlay != null:
		overlay.queue_free()
	for key in held:
		held[key] = false
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# CenterContainer: 안에 넣은 것을 자기 영역 한가운데에 놓아 주는 상자
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 28)
	center.add_child(box)

	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)

	if practice:
		box.add_child(_result_button("다시 하기", func(): Net.start_practice()))
		box.add_child(_result_button("처음으로", _go_lobby))
	else:
		if Net.is_host:
			box.add_child(_result_button("한 판 더", func(): Net.start_match()))
		else:
			var wait := Label.new()
			wait.text = "방장이 한 판 더 시작할 수 있어요"
			wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(wait)
		box.add_child(_result_button("방으로", _go_lobby))


func _result_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 140)
	b.add_theme_font_size_override("font_size", 44)
	# 둥근 색 버튼 모양 (normal = 평소, hover = 마우스를 올렸을 때, pressed = 누르는 동안)
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#3d6a4f") if state != "pressed" else Color("#5a8f6e")
		s.set_corner_radius_all(28)
		b.add_theme_stylebox_override(state, s)
	b.pressed.connect(callback)
	return b


func _go_lobby() -> void:
	get_tree().change_scene_to_file(Net.LOBBY_SCENE)
