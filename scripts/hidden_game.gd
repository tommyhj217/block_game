# 숨은그림 찾기 화면. 혼자 하기(단계가 오르고 기록을 잼)와 핫스팟 대결(같은 그림을 먼저 다 찾으면 승리)을 같이 맡는다.
# 그림 만들기는 HiddenPuzzle, 그리기는 HiddenWorld, 연출은 Fx, 소리는 Sfx, 네트워크는 Net.
#
# 조작
# - 손가락 하나로 끌기: 그림 이동 / 두 손가락 벌리기·오므리기: 확대·축소 (PC는 마우스 휠)
# - 톡 누르기: 그 자리에 찾을 그림이 있으면 찾음, 없으면 실수 (잠깐 못 누름)
extends Control

const STAGE_SIZE := Vector2(720, 1280)
const SETTINGS_PATH := "user://settings.cfg"
const LIST_TOP := 1060.0          # 찾을 목록 위쪽
const LIST_CELL := Vector2(112, 100)
const TAP_MOVE_LIMIT := 14.0      # 이보다 많이 움직이면 톡이 아니라 끌기
const TAP_TIME_LIMIT := 0.4       # 이보다 오래 누르면 톡이 아님

var stage: Control
var view: Control            # 그림이 보이는 창 (밖으로 나간 부분은 잘라서 안 보이게)
var world: HiddenWorld
var fx: Fx
var puzzle: HiddenPuzzle
var title_label: Label
var time_label: Label
var score_label: Label
var hint_button: Button
var center_label: Label      # 3, 2, 1 같은 큰 글자
var list_cells := []         # 찾을 목록 칸: {"panel", "label", "check"}
var overlay: Control = null

var level := 0               # 단계 (0부터)
var practice := true
var my_id := 1
var zoom := 1.0
var min_zoom := 0.5
var elapsed := 0.0           # 흐른 시간 (초)
var penalty := 0.0           # 실수·힌트로 더해진 시간 (혼자 하기)
var misses := 0
var hints_left := Config.HIDDEN_HINTS
var freeze_left := 0.0       # 남은 "못 누름" 시간
var countdown := float(Config.HIDDEN_COUNTDOWN)
var started := false
var finished := false
var scores := {}             # 대결: 아이디 → 찾은 개수
var _touches := {}           # 손가락 번호 → 지금 위치
var _taps := {}              # 손가락 번호 → {"pos": 시작 위치, "time": 시작 시각, "moved": 끌었는지}


func _ready() -> void:
	my_id = Net.my_id()
	practice = Net.is_practice()
	level = _load_level() if practice else Config.HIDDEN_BATTLE_STAGE
	puzzle = HiddenPuzzle.make(Net.match_seed, level)
	for id in Net.match_players:
		scores[id] = 0

	_build_ui()
	Net.score_received.connect(_on_score)
	Net.winner_declared.connect(_on_winner)
	Net.player_left.connect(_on_player_left)

	# 처음에는 그림 전체가 보이게 (가장 작게)
	min_zoom = maxf(view.size.x / puzzle.world_size.x, view.size.y / puzzle.world_size.y)
	_set_zoom(min_zoom, view.size / 2.0)
	_refresh_top()


# ═══════════════ 화면 만들기 ═══════════════

func _build_ui() -> void:
	var theme_res := Theme.new()
	theme_res.default_font_size = 30
	theme = theme_res

	var bg := ColorRect.new()
	bg.color = Config.SCREEN_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	stage = Control.new()
	stage.size = STAGE_SIZE
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	_center_stage()
	get_viewport().size_changed.connect(_center_stage)

	# 위쪽 줄: 🏠 / 단계·시간 / 💡
	var home := _small_button("🏠", Vector2(8, 6), _on_home)
	home.custom_minimum_size = Vector2(100, 100)
	hint_button = _small_button("💡%d" % hints_left, Vector2(602, 6), _use_hint)
	hint_button.custom_minimum_size = Vector2(110, 100)
	title_label = _label("", 30, Vector2(110, 4), Vector2(490, 46))
	time_label = _label("", 30, Vector2(110, 4), Vector2(490, 46))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.position.x = 124
	time_label.size.x = 470
	score_label = _label("", 24, Vector2(110, 54), Vector2(490, 50))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.clip_text = true

	# 그림 창: clip_contents = 자기 영역 밖에 그려지는 자식은 잘라서 안 보이게 한다
	view = Control.new()
	view.position = Config.HIDDEN_VIEW_RECT.position
	view.size = Config.HIDDEN_VIEW_RECT.size
	view.clip_contents = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(view)
	world = HiddenWorld.new()
	view.add_child(world)
	world.set_puzzle(puzzle)

	# 찾을 목록 (한 줄에 6칸, 최대 2줄)
	var n := puzzle.targets.size()
	var per_row := mini(6, n)
	var rows := ceili(float(n) / per_row)
	for t in range(n):
		var row := t / per_row
		var col := t % per_row
		var in_row := per_row if row < rows - 1 else n - per_row * (rows - 1)
		var start_x := (720.0 - in_row * LIST_CELL.x) / 2.0
		var pos := Vector2(start_x + col * LIST_CELL.x, LIST_TOP + row * (LIST_CELL.y + 6))
		var panel := Panel.new()
		panel.position = pos + Vector2(4, 0)
		panel.size = LIST_CELL - Vector2(8, 0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#f4ecd8")
		style.set_corner_radius_all(16)
		panel.add_theme_stylebox_override("panel", style)
		stage.add_child(panel)
		var label := Label.new()
		label.text = puzzle.targets[t]["e"]
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 60)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if puzzle.targets[t]["silhouette"]:
			label.modulate = Color(0, 0, 0)   # 검은 그림자로만 보여 줌 (색을 0으로 곱하면 까맣게 됨)
		panel.add_child(label)
		var check := Label.new()
		check.text = "✔"
		check.set_anchors_preset(Control.PRESET_FULL_RECT)
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		check.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		check.add_theme_font_size_override("font_size", 40)
		check.add_theme_color_override("font_color", Color("#2ecc71"))
		check.visible = false
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(check)
		list_cells.append({"panel": panel, "label": label, "check": check})

	center_label = _label("", 160, Config.HIDDEN_VIEW_RECT.position, Config.HIDDEN_VIEW_RECT.size)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.add_theme_color_override("font_outline_color", Color.BLACK)
	center_label.add_theme_constant_override("outline_size", 18)

	fx = Fx.new()
	fx.size = STAGE_SIZE
	stage.add_child(fx)


func _center_stage() -> void:
	stage.position = ((get_viewport_rect().size - STAGE_SIZE) / 2.0).floor()


func _label(text: String, font_size: int, pos: Vector2, label_size: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = label_size
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	return l


func _small_button(text: String, pos: Vector2, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 44)
	b.pressed.connect(callback)
	stage.add_child(b)
	return b


# ═══════════════ 좌표 바꾸기 ═══════════════

# 화면(뷰포트) 좌표 → 그림 창 안 좌표
func _to_view(screen: Vector2) -> Vector2:
	return screen - stage.position - view.position


# 그림 창 안 좌표 → 그림 좌표
func _view_to_world(p: Vector2) -> Vector2:
	return (p - world.position) / zoom


# 그림 좌표 → 무대 좌표 (연출을 띄울 때)
func _world_to_stage(p: Vector2) -> Vector2:
	return view.position + world.position + p * zoom


func _in_view(screen: Vector2) -> bool:
	return Rect2(Vector2.ZERO, view.size).has_point(_to_view(screen))


# 그림 창 안의 점 at을 기준으로 확대 배율을 바꾼다 (그 점 아래의 그림이 손가락 밑에 그대로 있게)
func _set_zoom(new_zoom: float, at: Vector2) -> void:
	var before := _view_to_world(at)
	zoom = clampf(new_zoom, min_zoom, Config.HIDDEN_ZOOM_MAX)
	world.scale = Vector2(zoom, zoom)
	world.position = at - before * zoom
	_clamp_pan()


# 그림이 창 밖으로 밀려나 빈 곳이 보이지 않게 위치를 제한한다
func _clamp_pan() -> void:
	var w := puzzle.world_size * zoom
	world.position.x = clampf(world.position.x, minf(0.0, view.size.x - w.x), 0.0)
	world.position.y = clampf(world.position.y, minf(0.0, view.size.y - w.y), 0.0)


# ═══════════════ 터치 ═══════════════

func _input(event: InputEvent) -> void:
	if overlay != null:
		return
	# PC 시험용: 마우스 휠로 확대·축소
	if event is InputEventMouseButton and event.pressed and _in_view(event.position):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom * 1.15, _to_view(event.position))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom / 1.15, _to_view(event.position))
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _in_view(event.position):
				return
			_touches[event.index] = event.position
			_taps[event.index] = {"pos": event.position, "time": _now(), "moved": _touches.size() > 1}
			# 두 번째 손가락이 닿으면 첫 손가락도 톡이 아님 (확대하는 중)
			if _touches.size() > 1:
				for k in _taps:
					_taps[k]["moved"] = true
		else:
			if _taps.has(event.index):
				var t: Dictionary = _taps[event.index]
				if not t["moved"] and _now() - t["time"] <= TAP_TIME_LIMIT and _touches.size() == 1:
					_tap(_to_view(event.position))
			_touches.erase(event.index)
			_taps.erase(event.index)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var old_pos: Vector2 = _touches[event.index]
		if _touches.size() == 1:
			# 손가락 하나: 그림 이동
			if event.position.distance_to(_taps[event.index]["pos"]) > TAP_MOVE_LIMIT:
				_taps[event.index]["moved"] = true
			if _taps[event.index]["moved"]:
				world.position += event.position - old_pos
				_clamp_pan()
			_touches[event.index] = event.position
		else:
			# 손가락 둘: 두 손가락 사이 거리가 변한 만큼 확대, 가운데가 움직인 만큼 이동
			var other_idx: int = -1
			for k in _touches:
				if k != event.index:
					other_idx = k
					break
			var other: Vector2 = _touches[other_idx]
			var old_dist := old_pos.distance_to(other)
			var new_dist: float = event.position.distance_to(other)
			var old_mid := (old_pos + other) / 2.0
			var new_mid: Vector2 = (event.position + other) / 2.0
			_touches[event.index] = event.position
			if old_dist > 10.0:
				_set_zoom(zoom * new_dist / old_dist, _to_view(new_mid))
			world.position += new_mid - old_mid
			_clamp_pan()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# 그림 창 안 점 p를 톡 눌렀다
func _tap(p: Vector2) -> void:
	if not started or finished:
		return
	if freeze_left > 0.0:
		fx.float_text("⏳", view.position + p, Color.WHITE, 48, 0.5)
		return
	var w := _view_to_world(p)
	var t := puzzle.hit_target(w, Config.HIDDEN_TAP_TOLERANCE / zoom)
	if t >= 0:
		_found(t)
	else:
		_miss(view.position + p)


func _found(t: int) -> void:
	puzzle.targets[t]["found"] = true
	var obj: Dictionary = puzzle.objects[puzzle.targets[t]["obj"]]
	var from := _world_to_stage(obj["pos"])
	if world.hint_on and obj["pos"].distance_to(world.hint_pos) <= Config.HIDDEN_HINT_RADIUS:
		world.hint_on = false   # 힌트가 가리키던 그림을 찾았으면 힌트 끄기
	world.queue_redraw()
	fx.burst(from, Color("#2ecc71"), 16, 300.0)
	fx.float_text("찾았다!", from - Vector2(0, 40), Color("#7dffb0"), 44, 0.7)
	var cell: Dictionary = list_cells[t]
	var cell_center: Vector2 = cell["panel"].position + cell["panel"].size / 2.0
	fx.shoot(from, cell_center, Color("#fff3a0"), obj["e"], 0.45, func():
		cell["check"].visible = true
		cell["label"].modulate = Color(1, 1, 1, 0.35)   # 찾은 그림은 흐리게 (그림자였어도 원래 색으로)
		cell["panel"].get_theme_stylebox("panel").bg_color = Color("#bfe8c9"))
	Sfx.play("item_get")
	_vibrate(30)
	var count := puzzle.found_count()
	if practice:
		if count == puzzle.targets.size():
			_solo_clear()
	else:
		Net.send_score(count)
	_refresh_top()


func _miss(at: Vector2) -> void:
	misses += 1
	if practice:
		penalty += Config.HIDDEN_MISS_PENALTY
		fx.float_text("+%d초" % int(Config.HIDDEN_MISS_PENALTY), at - Vector2(0, 50), Color("#ff9a9a"), 36, 0.8)
		freeze_left = Config.HIDDEN_MISS_FREEZE
	else:
		freeze_left = Config.HIDDEN_BATTLE_MISS_FREEZE
	fx.float_text("✖", at, Color("#ff5a5a"), 72, 0.6)
	view.modulate = Color(0.6, 0.6, 0.6)   # 못 누르는 동안 그림을 어둡게
	Sfx.play("block", 0.7, -4.0)
	_vibrate(80)
	_refresh_top()


func _use_hint() -> void:
	if not started or finished or hints_left <= 0:
		return
	var left := []
	for t in puzzle.targets:
		if not t["found"]:
			left.append(t)
	if left.is_empty():
		return
	hints_left -= 1
	hint_button.text = "💡%d" % hints_left
	hint_button.disabled = hints_left <= 0
	var t: Dictionary = left[randi_range(0, left.size() - 1)]
	var obj: Dictionary = puzzle.objects[t["obj"]]
	# 정확한 자리 대신 근처를 가리킨다 (동그라미 안 어딘가에 있음)
	var off := Vector2.from_angle(randf_range(0, TAU)) * randf_range(0.0, Config.HIDDEN_HINT_RADIUS * 0.6)
	world.hint_pos = obj["pos"] + off
	world.hint_on = true
	world.queue_redraw()
	# 그 근처로 확대해서 데려간다
	_set_zoom(maxf(zoom, 0.9), view.size / 2.0)
	world.position = view.size / 2.0 - world.hint_pos * zoom
	_clamp_pan()
	if practice:
		penalty += Config.HIDDEN_HINT_PENALTY
		fx.float_text("+%d초" % int(Config.HIDDEN_HINT_PENALTY), Vector2(600, 150), Color("#ffd84a"), 40)
	Sfx.play("item_use")
	_refresh_top()


func _vibrate(ms: int) -> void:
	if Config.VIBRATION and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ═══════════════ 시간 흐름 ═══════════════

func _process(delta: float) -> void:
	if not started:
		# 시작 전 3, 2, 1
		var before := ceili(countdown)
		countdown -= delta
		if countdown <= 0.0:
			started = true
			center_label.text = "찾아라!"
			Sfx.play("level")
			var tw := create_tween()
			tw.tween_property(center_label, "modulate:a", 0.0, 0.6).set_delay(0.4)
		else:
			center_label.text = str(ceili(countdown))
			if ceili(countdown) != before:
				Sfx.play("move", 1.0, -2.0)
		return
	if finished:
		return
	elapsed += delta
	if freeze_left > 0.0:
		freeze_left -= delta
		if freeze_left <= 0.0:
			view.modulate = Color.WHITE
	_refresh_time()


func _refresh_time() -> void:
	var total := elapsed + penalty
	time_label.text = "⏱ %02d:%02d" % [int(total) / 60, int(total) % 60]


func _refresh_top() -> void:
	title_label.text = ("단계 %d" % (level + 1)) if practice else "대결"
	_refresh_time()
	var total := puzzle.targets.size()
	if practice:
		score_label.text = "찾음 %d/%d   실수 %d" % [puzzle.found_count(), total, misses]
	else:
		# 대결: 모두의 찾은 개수 (나 먼저)
		var parts := ["나 %d" % scores.get(my_id, 0)]
		for id in scores:
			if id != my_id:
				parts.append("%s %d" % [Net.name_of(id), scores[id]])
		score_label.text = "  ·  ".join(parts) + "  / %d" % total


# ═══════════════ 대결 ═══════════════

func _on_score(id: int, score: int) -> void:
	if score < 0:
		_on_player_left(id)   # -1 = 그만둠
		return
	scores[id] = score
	if id != my_id and not finished:
		Sfx.play("move", 1.6, -8.0)   # 상대가 하나 찾을 때 작은 소리 (긴장감)
	_refresh_top()
	# 방장이 처음으로 다 찾은 사람을 승자로 정한다
	if Net.is_host and not finished and score >= puzzle.targets.size():
		Net.declare_winner(id)


func _on_player_left(id: int) -> void:
	if not scores.has(id) or id == my_id:
		return
	scores.erase(id)
	_refresh_top()
	if not finished and Net.is_host and scores.size() <= 1:
		Net.declare_winner(my_id)   # 다 나가고 나만 남음


func _on_winner(id: int) -> void:
	if finished:
		return
	finished = true
	world.reveal_all = true   # 못 찾은 그림을 빨간 동그라미로 보여 줌
	world.hint_on = false
	world.queue_redraw()
	var text := ""
	if id == my_id:
		text = "🏆 이겼어요!"
		Sfx.play("win")
		for i in range(5):
			fx.burst(Vector2(randf_range(150, 570), randf_range(300, 800)), Color.from_hsv(randf(), 0.7, 1.0), 16, 420.0)
	else:
		text = "🏆 %s 승리!" % Net.name_of(id)
		Sfx.play("lose")
	_show_result("%s\n나는 %d개 찾았어요" % [text, puzzle.found_count()])


# ═══════════════ 혼자 하기 ═══════════════

func _load_level() -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return int(cfg.get_value("hidden", "level", 0))


func _solo_clear() -> void:
	finished = true
	var total := elapsed + penalty
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var key := "best_%d" % level
	var best: float = cfg.get_value("hidden", key, 0.0)
	var new_record := best <= 0.0 or total < best
	if new_record:
		cfg.set_value("hidden", key, total)
		best = total
	cfg.set_value("hidden", "level", level + 1)   # 다음 단계 열기
	cfg.save(SETTINGS_PATH)
	Sfx.play("clear4")
	for i in range(5):
		fx.burst(Vector2(randf_range(150, 570), randf_range(300, 800)), Color.from_hsv(randf(), 0.7, 1.0), 16, 420.0)
	var text := "🎉 다 찾았어요!\n⏱ %s" % _fmt(total)
	text += "\n실수 %d · 힌트 %d" % [misses, Config.HIDDEN_HINTS - hints_left]
	text += "\n🌟 최고 기록!" if new_record else "\n최고 기록 %s" % _fmt(best)
	_show_result(text)


func _fmt(sec: float) -> String:
	return "%02d:%02d" % [int(sec) / 60, int(sec) % 60]


func _on_home() -> void:
	if not practice and not finished:
		Net.send_score(-1)   # 대결 중에 나가면 그만둔 것으로 알림
	get_tree().change_scene_to_file(Net.LOBBY_SCENE)


# ═══════════════ 결과 화면 ═══════════════

func _show_result(text: String) -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(540, 0)
	box.add_theme_constant_override("separation", 24)
	center.add_child(box)
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	box.add_child(title)
	if practice:
		box.add_child(_result_button("다음 단계 ▶", func(): Net.start_practice("hidden")))
		box.add_child(_result_button("정답 보기", _close_overlay_to_view))
		box.add_child(_result_button("처음으로", func(): get_tree().change_scene_to_file(Net.LOBBY_SCENE)))
	else:
		if Net.is_host:
			box.add_child(_result_button("한 판 더", func(): Net.start_match("hidden")))
		box.add_child(_result_button("정답 보기", _close_overlay_to_view))
		box.add_child(_result_button("방으로", func(): get_tree().change_scene_to_file(Net.LOBBY_SCENE)))
	box.pivot_offset = Vector2(270, 200)
	box.scale = Vector2(0.6, 0.6)
	create_tween().tween_property(box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 결과 창을 닫고 그림을 둘러볼 수 있게 한다 (🏠로 나감)
func _close_overlay_to_view() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null
	world.reveal_all = true
	world.queue_redraw()
	center_label.modulate.a = 1.0
	center_label.text = ""
	if practice:
		score_label.text = "다음 단계는 🏠 → 🖼 숨은그림 찾기"


func _result_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(540, 120)
	b.add_theme_font_size_override("font_size", 40)
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#3d6a4f") if state != "pressed" else Color("#5a8f6e")
		s.set_corner_radius_all(28)
		b.add_theme_stylebox_override(state, s)
	b.pressed.connect(callback)
	return b
