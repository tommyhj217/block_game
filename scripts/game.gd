# 게임 화면. 내 판을 움직이고(시간, 조작), 상대 판을 보여 주고, 공격·아이템·승패를 처리한다.
# 블록 규칙은 Board, 그리기는 BoardView, 연출은 Fx, 소리는 Sfx, 네트워크는 Net에게 맡긴다.
# 화면은 코드로 만든다(_build_ui). 위치와 크기는 맨 위 상수에서 바꾼다.
extends Control

# ─── 화면 배치 (기준 화면 720 x 1280) ───
const STAGE_SIZE := Vector2(720, 1280)
const OPP_TOP := 12.0          # 상대 판 줄의 위쪽
const OPP_HEIGHT := 236.0      # 상대 판 줄 높이 (이름 포함)
const BOARD_RECT := Rect2(40, 262, 380, 760)   # 내 판 (칸 38px)
const METER_RECT := Rect2(14, 262, 16, 760)    # 방해 줄 대기 막대
const SIDE_X := 440.0          # 오른쪽 정보 칸 시작 x
const SIDE_W := 264.0          # 오른쪽 정보 칸 너비
const PAD_TOP := 1058.0        # 조작 버튼 줄 위쪽
const PAD_SIZE := Vector2(165, 190)  # 조작 버튼 크기 (4개)
const PAD_GAP := 10.0
const ITEM_PAD_RECT := Rect2(477, 760, 190, 190)  # 아이템 쓰기 버튼

var board := Board.new()
var stage: Control         # 모든 화면 요소를 담는 720x1280 틀
var view: BoardView
var fx: Fx                 # 연출 층 (맨 위)
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
var _down_time := 0.0          # ▼ 버튼을 누르고 있는 시간
var _down_last_press := -10.0  # ▼를 마지막으로 누른 시각(초). 두 번 누르기 판단에 씀
var _down_block_until := 0.0   # 이 시각까지는 ▼를 무시 (쾅 직후 실수 방지)
var _down_need_release := false  # 새 블록이 나왔는데 ▼를 계속 누르고 있으면, 손을 뗐다 다시 눌러야 내려간다
var _swipes := {}              # 판 위 손가락 번호 → {"pos": 시작 위치, "time": 시작 시각}

# 상대 판: 아이디 → {"view": BoardView, "label": Label, "button": Button}
var opponents := {}
var alive := {}          # 아이디 → 아직 살아 있는지 (나 포함)
var target_id := 0       # 공격 목표 (0이면 자동으로 고름)

var items: Array[String] = []  # 가지고 있는 아이템 (앞에서부터 씀)
var _items_flying := 0         # 아이템 버튼으로 날아가는 중인 아이템 수 (최대 개수 계산에 포함)
var pending_garbage := 0       # 받을 예정인 방해 줄 수
var effects := {"fast": 0.0, "fog": 0.0, "shield": 0.0}  # 남은 효과 시간(초)

var play_time := 0.0   # 이 판을 시작하고 흐른 시간(초). 시간이 갈수록 빨라지는 데 씀
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
var _shake_power := 0.0  # 지금 흔들림 크기(px). 시간이 지나면 줄어든다
var _danger_time := 0.0  # 위험 깜빡임 계산용 시간


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

	# 조작 버튼 4개: ◀ ▶ ↻ ▼ (▼: 한 번 = 한 칸, 꾹 = 쭉, 톡톡 = 쾅)
	var names := ["left", "right", "rotate", "down"]
	var icons := ["◀", "▶", "↻", "▼"]
	var colors := [Color("#2f3a56"), Color("#2f3a56"), Color("#3d5a4a"), Color("#5a3d3d")]
	for i in range(names.size()):
		var rect := Rect2(Vector2(14 + i * (PAD_SIZE.x + PAD_GAP), PAD_TOP), PAD_SIZE)
		_add_pad(names[i], rect, icons[i], colors[i])

	# 버튼 바로 위 작은 사용법 안내
	var how := _make_label("▼ 꾹 누르면 쭉   ·   ▼▼ 톡톡 또는 판을 아래로 휙 = 쾅!", 22,
			Vector2(0, PAD_TOP - 34), Vector2(720, 30))
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.modulate = Color(1, 1, 1, 0.6)

	# 화면 가운데에 잠깐 뜨는 안내 글
	toast_label = _make_label("", 48, Vector2(BOARD_RECT.position.x, 520), Vector2(BOARD_RECT.size.x, 120))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_label.add_theme_constant_override("outline_size", 10)

	# 연출 층은 가장 마지막에 넣어서 모든 것 위에 그려지게 한다
	fx = Fx.new()
	fx.size = STAGE_SIZE
	stage.add_child(fx)

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
		var hint := _make_label("🧹 🛡 🧲 🎁 아이템이 나와요", 26, Vector2(0, OPP_TOP + 120), Vector2(720, 50))
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
	p.pivot_offset = rect.size / 2.0   # 눌렀을 때 가운데를 기준으로 작아지게
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


# 무대 좌표 도우미: 내 판 칸 가운데 / 내 판 가운데 / 상대 판 가운데 / 아이템 버튼 가운데
func _my_cell_pos(x: float, y: float) -> Vector2:
	return BOARD_RECT.position + view.cell_center(x, y)


func _my_board_center() -> Vector2:
	return BOARD_RECT.get_center()


func _opp_center(id: int) -> Vector2:
	if opponents.has(id):
		var v: BoardView = opponents[id]["view"]
		return v.position + v.size / 2.0
	return Vector2(360, OPP_TOP + OPP_HEIGHT / 2.0)


func _item_pad_center() -> Vector2:
	return ITEM_PAD_RECT.get_center()


# ═══════════════ 조작 ═══════════════

# _input: 화면의 모든 입력이 먼저 여기로 온다.
# InputEventScreenTouch(손가락 닿음/뗌)와 InputEventScreenDrag(손가락 끌기)를 직접 보고
# 손가락 번호(index)마다 어느 버튼을 누르는지 기억한다. 그래서 ◀를 누른 채 ▼도 누를 수 있다.
func _input(event: InputEvent) -> void:
	if overlay != null:
		return  # 결과 화면이 떠 있으면 조작 버튼은 쉰다
	if event is InputEventScreenTouch:
		if event.pressed:
			var pad_name := _pad_at(event.position)
			if pad_name != "":
				_touch_owner[event.index] = pad_name
				_pad_down(pad_name)
			elif _on_my_board(event.position):
				# 판 위에서 손가락이 닿음: 아래로 휙 쓸어내리는지 지켜본다
				_swipes[event.index] = {"pos": event.position, "time": _now()}
		else:
			if _touch_owner.has(event.index):
				_pad_up(_touch_owner[event.index])
				_touch_owner.erase(event.index)
			_swipes.erase(event.index)
	elif event is InputEventScreenDrag and _swipes.has(event.index):
		# 빠르게 아래로 충분히 쓸었으면 쾅 (옆으로 더 많이 움직였으면 무시)
		var s: Dictionary = _swipes[event.index]
		var d: Vector2 = event.position - s["pos"]
		if _now() - s["time"] > Config.SWIPE_MAX_TIME:
			_swipes.erase(event.index)  # 너무 천천히 움직이면 휙이 아님
		elif d.y >= Config.SWIPE_MIN_DISTANCE and d.y > absf(d.x) * 1.5:
			_swipes.erase(event.index)
			if not finished and not board.game_over and _now() >= _down_block_until:
				_down_block_until = _now() + Config.DROP_COOLDOWN
				_hard_drop()
	elif event is InputEventScreenDrag:
		# 손가락이 ◀ ▶ 버튼 밖으로 나가면 뗀 것으로 본다
		if _touch_owner.has(event.index):
			var owner_name: String = _touch_owner[event.index]
			if (owner_name == "left" or owner_name == "right") and _pad_at(event.position) != owner_name:
				_pad_up(owner_name)
				_touch_owner.erase(event.index)


# PC에서 시험할 때 키보드로도 조작 (←→, ↓ 버튼과 같음, ↑/X 돌리기, 스페이스 바로 떨어뜨리기, C 아이템)
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


# 지금 시각(초). 두 번 누르기나 휙 판단에 쓴다.
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# 화면 위치가 내 판 위인지 (조금 넉넉하게)
func _on_my_board(pos: Vector2) -> bool:
	return Rect2(stage.position + BOARD_RECT.position, BOARD_RECT.size).grow(20).has_point(pos)


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
			var now := _now()
			if now < _down_block_until:
				return  # 방금 쾅 했음: 실수로 다음 블록까지 내리지 않게 잠깐 무시
			if now - _down_last_press <= Config.DOUBLE_TAP_TIME:
				# 톡톡 두 번 → 바닥까지 쾅
				_down_last_press = -10.0
				_down_block_until = now + Config.DROP_COOLDOWN
				held["down"] = false
				_hard_drop()
				return
			# 한 번 → 한 칸 내려가고, 계속 누르고 있으면 잠시 뒤부터 쭉
			_down_last_press = now
			held["down"] = true
			_down_need_release = false
			_down_time = 0.0
			if board.try_move(0, 1):
				fall_timer = 0.0
				Sfx.play("move", 0.8, -6.0)
				state_dirty = true
				_refresh_board()
		"rotate":
			if board.try_rotate(1):
				Sfx.play("rotate")
				_after_move()
		"drop":
			_hard_drop()
		"item":
			_use_item()


func _pad_up(pad_name: String) -> void:
	_set_pad_look(pad_name, false)
	if pad_name == "down":
		_down_need_release = false
	if held.has(pad_name):
		held[pad_name] = false


# 누르는 동안 버튼 색을 밝게 하고, 살짝 작아졌다가 돌아오게 (눌린 느낌)
func _set_pad_look(pad_name: String, down: bool) -> void:
	if not pads.has(pad_name):
		return
	var info: Dictionary = pads[pad_name]
	var style: StyleBoxFlat = info["style"]
	style.bg_color = info["color"].lightened(0.3) if down else info["color"]
	var p: Panel = info["panel"]
	# Tween: 값을 정해진 시간 동안 부드럽게 바꿔 주는 도구
	var tw := create_tween()
	tw.tween_property(p, "scale", Vector2(0.92, 0.92) if down else Vector2.ONE, 0.06)


func _move(dx: int) -> void:
	if board.try_move(dx, 0):
		Sfx.play("move", 1.0, -6.0)
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


# 바닥까지 쾅 떨어뜨린다: 지나간 자리에 잔상, 떨어진 자리에 먼지, 판이 살짝 흔들림
func _hard_drop() -> void:
	if board.piece_type < 0:
		return
	var before := board.piece_cells()
	var distance := board.drop_distance()
	board.piece_pos.y += distance
	var after := board.piece_cells()
	var color: Color = Config.CELL_COLORS[board.piece_type + 1]
	var cs := view.cell_size()
	for i in range(after.size()):
		# 지나간 세로 줄에 하얀 잔상
		var top := _my_cell_pos(before[i].x, maxf(before[i].y, 0)) - Vector2(cs, cs) / 2.0
		var bottom := _my_cell_pos(after[i].x, after[i].y) + Vector2(cs, cs) / 2.0
		if bottom.y > top.y:
			fx.flash(Rect2(top, Vector2(cs, bottom.y - top.y)), Color(1, 1, 1, 0.18), 0.15)
	# 블록 아래쪽 칸에서 먼지가 튐
	for c in after:
		if not after.has(c + Vector2i(0, 1)):
			fx.burst(_my_cell_pos(c.x, c.y + 0.5), color.lightened(0.4), 3, 160.0, 5.0)
	if distance > 0:
		_shake(Config.SHAKE_DROP)
	Sfx.play("drop")
	_vibrate(15)
	_after_lock(board.lock_piece())


# ═══════════════ 시간 흐름 ═══════════════

func _process(delta: float) -> void:
	_update_toast(delta)
	_update_effects(delta)
	_update_shake(delta)
	_update_danger(delta)
	_send_state_if_needed(delta)
	if finished or board.game_over or board.piece_type < 0:
		return
	_update_level(delta)

	# ◀ ▶ 를 누르고 있으면 잠깐 뒤부터 계속 움직인다
	for dir_name in ["left", "right"]:
		if held[dir_name]:
			_repeat[dir_name] += delta
			while _repeat[dir_name] >= Config.MOVE_REPEAT_DELAY + Config.MOVE_REPEAT_RATE:
				_repeat[dir_name] -= Config.MOVE_REPEAT_RATE
				_move(-1 if dir_name == "left" else 1)

	# ▼ 를 누르고 있으면 잠시 뒤부터 빠르게 쭉 내려간다
	var soft := false
	if held["down"] and not _down_need_release:
		_down_time += delta
		soft = _down_time >= Config.SOFT_DROP_DELAY
	_update_down_icon()

	# 중력: 시간이 되면 한 칸 내려간다
	var interval := _fall_interval()
	if soft:
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
			Sfx.play("drop", 1.4, -8.0)
			_after_lock(board.lock_piece())
	else:
		lock_timer = 0.0


# ▼를 한 번 누른 직후(두 번째 누르면 쾅이 되는 동안)에는 버튼 그림을 ⤓ 금색으로 바꿔
# "지금 한 번 더 누르면 쾅"이라는 것을 눈으로 알려 준다.
func _update_down_icon() -> void:
	var label: Label = pads["down"]["label"]
	var armed: bool = not held["down"] and _now() - _down_last_press <= Config.DOUBLE_TAP_TIME
	var text := "⤓" if armed else "▼"
	if label.text != text:
		label.text = text
		label.add_theme_color_override("font_color", Color("#ffd84a") if armed else Color.WHITE)


# 지금 한 칸 떨어지는 데 걸리는 시간. 레벨이 오르면 빨라지고, ⚡ 를 맞으면 더 빨라진다.
func _fall_interval() -> float:
	var t := maxf(Config.FALL_MIN, Config.FALL_START - _level() * Config.FALL_STEP)
	if effects["fast"] > 0.0:
		t *= Config.FAST_MULTIPLIER
	return t


# 지금 레벨 (0부터). 지운 줄 수로 오르는 레벨 + 판이 시작된 뒤 흐른 시간으로 오르는 레벨.
# 대전에서는 모두 같은 시간에 시작하므로 다 같이 빨라져서, 판이 너무 길어지지 않는다.
func _level() -> int:
	return board.level() + int(play_time / Config.SECONDS_PER_LEVEL)


# 흐른 시간을 재고, 레벨이 오르면 알려 준다
func _update_level(delta: float) -> void:
	var before := _level()
	play_time += delta
	if _level() > before:
		_level_up_fx()


func _level_up_fx() -> void:
	fx.float_text("빨라진다! ⏩", _my_board_center() - Vector2(0, 200), Color("#ffd84a"), 52)
	Sfx.play("level")
	_refresh_side()


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


# 흔들림: 판을 무작위로 조금씩 옮기고, 흔들림 크기는 빠르게 줄어든다
func _shake(power: float) -> void:
	_shake_power = maxf(_shake_power, power)


func _update_shake(delta: float) -> void:
	if _shake_power <= 0.1:
		if view.position != BOARD_RECT.position:
			view.position = BOARD_RECT.position
		_shake_power = 0.0
		return
	view.position = BOARD_RECT.position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_power
	_shake_power = lerpf(_shake_power, 0.0, minf(1.0, delta * 14.0))


# 꼭대기 가까이 찼으면 판 테두리가 빨갛게 깜빡이고 작게 삐 소리
func _update_danger(delta: float) -> void:
	var in_danger := not board.game_over and board.stack_height() >= Config.ROWS - Config.DANGER_ROWS
	if in_danger:
		var before := _danger_time
		_danger_time += delta
		view.danger = 0.45 + 0.45 * sin(_danger_time * 7.0)
		# 깜빡임 한 번(약 0.9초)마다 삐
		if int(before / 0.9) != int(_danger_time / 0.9):
			Sfx.play("danger")
		view.queue_redraw()
	elif view.danger > 0.0:
		view.danger = 0.0
		_danger_time = 0.0
		view.queue_redraw()


func _vibrate(ms: int) -> void:
	# 폰에서만 진동 (PC에서는 아무 일도 안 함)
	if Config.VIBRATION and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


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
	var lines := _handle_clear(result)
	if lines == 0 and pending_garbage > 0:
		# 줄을 못 지웠으면 기다리던 방해 줄이 올라온다
		_raise_garbage()
	state_dirty = true
	if board.game_over:
		_i_lost()
		return
	_spawn_next()


# 줄을 지운 결과를 처리한다: 연출, 아이템 얻기, 공격. 지운 줄 수를 돌려준다.
# (블록이 굳을 때와 🧲 끌어내리기 아이템을 쓸 때 같이 쓴다)
func _handle_clear(result: Dictionary) -> int:
	var lines: int = result["lines"]
	if lines > 0:
		_clear_fx(result)
		# 지운 만큼 공격. 받을 예정인 방해 줄이 있으면 먼저 그만큼 없앤다(막기).
		var send: int = Config.GARBAGE_FOR_LINES[mini(lines, 4)]
		var cancel := mini(pending_garbage, send)
		pending_garbage -= cancel
		send -= cancel
		if send > 0 and not practice:
			_send_attack("garbage", send)
	# 지운 줄에 있던 아이템은 아이템 버튼으로 날아가서 들어간다
	for i in range(result["items"].size()):
		var key: String = result["items"][i]
		var cell: Vector2i = result["item_cells"][i]
		_fly_item_to_pad(key, _my_cell_pos(cell.x, cell.y))
	return lines


# 줄 지우기 연출: 줄이 번쩍이고, 칸 조각이 튀고, 지운 줄 수만큼 크게 흔들리고 소리가 높아진다
func _clear_fx(result: Dictionary) -> void:
	var lines: int = result["lines"]
	var cs := view.cell_size()
	for r in range(result["rows"].size()):
		var y: int = result["rows"][r]
		var row: PackedByteArray = result["row_cells"][r]
		var left := _my_cell_pos(0, y) - Vector2(cs, cs) / 2.0
		fx.flash(Rect2(left, Vector2(cs * Config.COLS, cs)), Color(1, 1, 1, 0.9), 0.3)
		for x in range(Config.COLS):
			var color: Color = Config.CELL_COLORS[Board.color_of(row[x])]
			fx.burst(_my_cell_pos(x, y), color, 3 if lines < 4 else 5, 300.0 + lines * 60.0, 9.0)
	var center_y: float = _my_cell_pos(0, result["rows"][0]).y
	match lines:
		1:
			pass
		2:
			fx.float_text("2줄!", Vector2(_my_board_center().x, center_y), Color.WHITE, 60)
		3:
			fx.float_text("3줄!!", Vector2(_my_board_center().x, center_y), Color("#7fe0ff"), 70)
		_:
			# 4줄: 판 전체가 번쩍이고 금색 큰 글자
			fx.flash(Rect2(BOARD_RECT.position, BOARD_RECT.size), Color(1, 0.9, 0.5, 0.35), 0.4)
			fx.float_text("와르르!", Vector2(_my_board_center().x, center_y), Color("#ffd84a"), 88, 1.2)
	Sfx.play("clear%d" % mini(lines, 4))
	_shake(Config.SHAKE_PER_LINE * lines)
	_vibrate(25 * lines)


# 기다리던 방해 줄이 아래에서 올라온다
func _raise_garbage() -> void:
	var n := pending_garbage
	pending_garbage = 0
	board.add_garbage(n, board.random_hole())
	var cs := view.cell_size()
	var top := _my_cell_pos(0, Config.ROWS - n) - Vector2(cs, cs) / 2.0
	fx.flash(Rect2(top, Vector2(cs * Config.COLS, cs * n)), Color(1, 0.3, 0.3, 0.5), 0.35)
	_shake(Config.SHAKE_HIT)
	Sfx.play("hit")
	_vibrate(60)


func _spawn_next() -> void:
	fall_timer = 0.0
	lock_timer = 0.0
	lock_resets = 0
	# ▼를 누른 채로 새 블록이 나오면, 새 블록은 손을 뗐다 다시 눌러야 내려간다 (모르고 내려가는 것 방지)
	if held["down"]:
		_down_need_release = true
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
	var list := _alive_opponents()
	if list.is_empty():
		return 0
	return list[randi_range(0, list.size() - 1)]


func _alive_opponents() -> Array:
	var list := []
	for id in alive:
		if id != my_id and alive[id]:
			list.append(id)
	return list


# 공격을 보낸다. target을 0으로 두면 자동으로 고른다. 공이 상대 판으로 날아가는 연출도 한다.
func _send_attack(kind: String, amount: int, target: int = 0) -> void:
	var t := target if target != 0 else _pick_target()
	if t == 0:
		return
	Net.send_attack(t, kind, amount)
	var icon: String = "" if kind == "garbage" else Config.ITEMS[kind]["icon"]
	var color := Color("#ff8a5b") if kind == "garbage" else Color("#c58bff")
	fx.shoot(_my_board_center() - Vector2(0, 300), _opp_center(t), color, icon)
	Sfx.play("send")


# 얻은 아이템이 아이템 버튼으로 날아가서 들어간다
func _fly_item_to_pad(key: String, from: Vector2) -> void:
	if items.size() + _items_flying >= Config.ITEM_MAX:
		return  # 가득 차서 못 받음
	_items_flying += 1
	fx.shoot(from, _item_pad_center(), Color("#fff3a0"), Config.ITEMS[key]["icon"], 0.5,
			func():
				_items_flying -= 1
				if items.size() < Config.ITEM_MAX:
					items.append(key)
				Sfx.play("item_get")
				_refresh_side())


func _use_item() -> void:
	if items.is_empty():
		return
	var key: String = items.pop_front()
	Sfx.play("item_use")
	match key:
		"garbage":
			_send_attack("garbage", Config.ITEM_GARBAGE_LINES)
		"fast", "fog", "steal":
			_send_attack(key, 0)
		"all":
			# 💥 살아 있는 모든 상대에게 방해 줄
			for id in _alive_opponents():
				_send_attack("garbage", Config.ITEM_ALL_LINES, id)
			fx.float_text("💥 모두 공격!", _my_board_center() - Vector2(0, 200), Color("#ff8a5b"), 56)
		"sweep":
			# 🧹 맨 아래 줄들이 터지며 사라진다
			var cs := view.cell_size()
			for i in range(Config.ITEM_SWEEP_LINES):
				var y := Config.ROWS - 1 - i
				for x in range(Config.COLS):
					var v := board.get_cell(x, y)
					if v != 0:
						fx.burst(_my_cell_pos(x, y), Config.CELL_COLORS[Board.color_of(v)], 3)
			var top := _my_cell_pos(0, Config.ROWS - Config.ITEM_SWEEP_LINES) - Vector2(cs, cs) / 2.0
			fx.flash(Rect2(top, Vector2(cs * Config.COLS, cs * Config.ITEM_SWEEP_LINES)), Color(1, 1, 1, 0.8), 0.3)
			board.clear_bottom(Config.ITEM_SWEEP_LINES)
			fx.float_text("🧹 깨끗!", _my_board_center(), Color.WHITE, 56)
			_shake(6.0)
		"shield":
			effects["shield"] = Config.ITEM_DURATION
			pending_garbage = 0
			view.shielded = true
			fx.flash(Rect2(BOARD_RECT.position, BOARD_RECT.size), Color(0.4, 0.75, 1, 0.35), 0.4)
			fx.float_text("🛡 방패!", _my_board_center(), Color("#9fd8ff"), 56)
		"magnet":
			# 🧲 모든 칸이 아래로 떨어져 구멍을 메우고, 꽉 찬 줄은 지워진다(공격도 됨)
			fx.flash(Rect2(BOARD_RECT.position, BOARD_RECT.size), Color(0.6, 0.6, 1, 0.3), 0.3)
			var result := board.collapse()
			if result["lines"] == 0:
				fx.float_text("🧲 착!", _my_board_center(), Color.WHITE, 56)
			_shake(8.0)
			_handle_clear(result)
		"bars":
			# 🎁 다음 블록 몇 개가 막대로 바뀐다
			board.set_next_type(0, Config.ITEM_BARS_COUNT)
			fx.float_text("🎁 막대 %d개!" % Config.ITEM_BARS_COUNT, _my_board_center(), Color("#7fe0ff"), 56)
			fx.burst(preview.position + preview.size / 2.0, Config.CELL_COLORS[1], 16)
	state_dirty = true
	_refresh_board()
	_refresh_side()


# 상대가 나에게 무언가 보냈다
func _on_attacked(from_id: int, kind: String, amount: int) -> void:
	if finished or board.game_over:
		return
	var who := Net.name_of(from_id)
	# 🦝 훔치기의 답장(선물): 방패와 상관없이 받는다
	if kind == "gift":
		if amount > 0:
			var key := Board.item_key(amount)
			_fly_item_to_pad(key, _opp_center(from_id))
			_show_toast("🦝 %s 가져왔다!" % Config.ITEMS[key]["icon"])
		else:
			_show_toast("🦝 빈손...")
		return
	if effects["shield"] > 0.0:
		_show_toast("🛡 막았다!")
		Sfx.play("block")
		if kind == "steal":
			Net.send_attack(from_id, "gift", 0)
		return
	# 공이 상대 판에서 내 판으로 날아온다
	var color := Color("#ff8a5b") if kind == "garbage" else Color("#c58bff")
	var icon: String = "" if kind == "garbage" else Config.ITEMS[kind]["icon"]
	fx.shoot(_opp_center(from_id), _my_board_center() - Vector2(0, 300), color, icon, 0.4,
			func():
				_shake(4.0)
				Sfx.play("hit", 1.3, -6.0))
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
		"steal":
			# 내 첫 번째 아이템을 빼앗긴다 (없으면 빈손 답장)
			if items.is_empty():
				Net.send_attack(from_id, "gift", 0)
				_show_toast("%s의 🦝 (뺏길 게 없어요)" % who)
			else:
				var key: String = items.pop_front()
				Net.send_attack(from_id, "gift", Config.ITEM_ORDER.find(key) + 1)
				fx.shoot(_item_pad_center(), _opp_center(from_id), Color("#fff3a0"), Config.ITEMS[key]["icon"])
				_show_toast("%s의 🦝 %s 뺏겼다!" % [who, Config.ITEMS[key]["icon"]])
	_vibrate(30)
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
		fx.burst(_opp_center(id), Color("#8a8f99"), 20, 250.0)
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
	view.danger = 0.0
	_refresh_board()
	_shake(16.0)
	Sfx.play("lose")
	_vibrate(200)
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
		if left[0] == my_id:
			text = "🏆 이겼어요!"
			Sfx.play("win")
			# 이긴 사람 판 위로 축하 조각
			for i in range(6):
				fx.burst(_my_board_center() + Vector2(randf_range(-150, 150), randf_range(-250, 100)),
						Config.CELL_COLORS[randi_range(1, 7)], 14, 420.0)
		else:
			text = "🏆 %s 승리!" % Net.name_of(left[0])
	# 이긴 사람의 마지막 판 모양을 모두에게 한 번 더 보낸다
	Net.send_state(board.snapshot())
	_show_result(text)


# ═══════════════ 화면 갱신 ═══════════════

func _refresh_board() -> void:
	view.active = []
	view.ghost = []
	if board.piece_type >= 0 and not board.game_over:
		view.active = board.piece_cells()
		if Config.GHOST_ENABLED:
			# 떨어질 자리 미리 보기 (설정에서 켰을 때만)
			view.ghost = board.cells_at(board.piece_type, board.piece_rot, board.piece_pos + Vector2i(0, board.drop_distance()))
	view.set_cells(board.snapshot(true))


func _refresh_side() -> void:
	preview.set_types(board.next_queue.slice(0, Config.NEXT_PREVIEW))
	info_label.text = "%d줄  레벨 %d" % [board.lines_total, _level() + 1]
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

	# 결과 상자가 톡 튀어나오게
	box.pivot_offset = Vector2(260, 150)
	box.scale = Vector2(0.6, 0.6)
	var tw := create_tween()
	tw.tween_property(box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
