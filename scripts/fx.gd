# 손맛 연출을 그리는 투명한 층. 게임 화면 맨 위에 덮어 둔다.
# - burst: 조각이 사방으로 튀었다가 떨어짐 (줄 지울 때, 공격이 도착할 때)
# - flash: 네모 영역이 번쩍였다가 사라짐
# - float_text: 글자가 톡 커지며 떠올랐다가 사라짐 ("4줄!" 같은 것)
# - shoot: 공이 포물선을 그리며 날아감 (공격, 아이템 얻기). 도착하면 함수를 부를 수 있다.
# 규칙에는 영향을 주지 않고 보이는 것만 담당한다.
class_name Fx
extends Control

const GRAVITY := 1400.0   # 조각이 떨어지는 힘 (px/초²)

var _parts := []    # 조각들: {pos, vel, color, life, max, size}
var _flashes := []  # 번쩍임: {rect, color, life, max}
var _texts := []    # 떠오르는 글자: {text, pos, color, size, life, max}
var _shots := []    # 날아가는 공: {from, to, t, dur, color, text, done}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func burst(pos: Vector2, color: Color, count: int = 10, speed: float = 320.0, part_size: float = 8.0) -> void:
	for i in range(count):
		var angle := randf_range(0.0, TAU)       # TAU = 2π (한 바퀴)
		var v := Vector2(cos(angle), sin(angle)) * randf_range(speed * 0.4, speed)
		v.y -= speed * 0.5                       # 위쪽으로 조금 더 튀게
		var life := randf_range(0.35, 0.7)
		_parts.append({"pos": pos, "vel": v, "color": color, "life": life, "max": life,
				"size": part_size * randf_range(0.6, 1.2)})


func flash(rect: Rect2, color: Color, duration: float = 0.25) -> void:
	_flashes.append({"rect": rect, "color": color, "life": duration, "max": duration})


func float_text(text: String, pos: Vector2, color: Color = Color.WHITE, font_size: int = 64, duration: float = 0.9) -> void:
	# 방금 띄운 글자가 같은 자리에 있으면 겹치지 않게 조금 위에 띄운다
	for t in _texts:
		if t["max"] - t["life"] < 0.5 and absf(t["pos"].y - pos.y) < 70.0 and absf(t["pos"].x - pos.x) < 200.0:
			pos.y = t["pos"].y - 80.0
	_texts.append({"text": text, "pos": pos, "color": color, "size": font_size, "life": duration, "max": duration})


# from에서 to로 공을 날린다. 도착하면 on_arrive를 부른다(없어도 됨).
# Callable: 함수를 값처럼 담아 둔 것 (Python에서 함수를 변수에 넣는 것과 같다)
func shoot(from: Vector2, to: Vector2, color: Color, text: String = "", duration: float = 0.45,
		on_arrive: Callable = Callable()) -> void:
	_shots.append({"from": from, "to": to, "t": 0.0, "dur": duration, "color": color,
			"text": text, "done": on_arrive})


func _process(delta: float) -> void:
	if _parts.is_empty() and _flashes.is_empty() and _texts.is_empty() and _shots.is_empty():
		return
	# 조각: 속도만큼 움직이고 중력으로 떨어진다
	for p in _parts:
		p["vel"].y += GRAVITY * delta
		p["pos"] += p["vel"] * delta
		p["life"] -= delta
	_parts = _parts.filter(func(p): return p["life"] > 0.0)  # 수명이 끝난 것은 버린다
	for f in _flashes:
		f["life"] -= delta
	_flashes = _flashes.filter(func(f): return f["life"] > 0.0)
	for t in _texts:
		t["life"] -= delta
	_texts = _texts.filter(func(t): return t["life"] > 0.0)
	# 공: 시간에 따라 앞으로 가고, 지나간 자리에 작은 불꽃을 남긴다
	var arrived := []
	for s in _shots:
		s["t"] += delta / s["dur"]
		if s["t"] >= 1.0:
			arrived.append(s)
		else:
			_parts.append({"pos": _shot_pos(s), "vel": Vector2(randf_range(-40, 40), randf_range(-40, 40)),
					"color": s["color"], "life": 0.25, "max": 0.25, "size": 7.0})
	for s in arrived:
		_shots.erase(s)
		burst(s["to"], s["color"], 14, 300.0)
		if s["done"].is_valid():
			s["done"].call()
	queue_redraw()


# 공의 현재 위치: 직선으로 가면서 가운데쯤에서 위로 볼록하게 (포물선)
func _shot_pos(s: Dictionary) -> Vector2:
	var t: float = clampf(s["t"], 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)  # 처음과 끝은 천천히, 가운데는 빠르게
	var p: Vector2 = s["from"].lerp(s["to"], eased)
	p.y -= sin(t * PI) * 120.0
	return p


func _draw() -> void:
	var font := get_theme_default_font()
	for f in _flashes:
		var c: Color = f["color"]
		c.a *= f["life"] / f["max"]
		draw_rect(f["rect"], c)
	for p in _parts:
		var c: Color = p["color"]
		c.a = clampf(p["life"] / p["max"] * 1.5, 0.0, 1.0)
		var s: float = p["size"]
		draw_rect(Rect2(p["pos"] - Vector2(s, s) / 2.0, Vector2(s, s)), c)
	for s in _shots:
		var pos := _shot_pos(s)
		var glow: Color = s["color"]
		glow.a = 0.35
		draw_circle(pos, 26.0, glow)
		draw_circle(pos, 15.0, s["color"])
		if s["text"] != "":
			draw_string(font, pos + Vector2(-30, 14), s["text"], HORIZONTAL_ALIGNMENT_CENTER, 60, 38)
	for t in _texts:
		var age: float = t["max"] - t["life"]
		# 처음 0.12초 동안 톡 커지고, 그다음 천천히 떠오르며 사라진다
		var pop := clampf(age / 0.12, 0.0, 1.0)
		var scale_now := lerpf(0.5, 1.0, pop) + (0.15 * (1.0 - absf(pop * 2.0 - 1.0)))
		var fs := int(t["size"] * scale_now)
		var c: Color = t["color"]
		c.a = clampf(t["life"] / (t["max"] * 0.4), 0.0, 1.0)
		var pos: Vector2 = t["pos"] - Vector2(300, age * 60.0 - fs * 0.35)
		var outline := Color(0, 0, 0, c.a)
		draw_string_outline(font, pos, t["text"], HORIZONTAL_ALIGNMENT_CENTER, 600, fs, 12, outline)
		draw_string(font, pos, t["text"], HORIZONTAL_ALIGNMENT_CENTER, 600, fs, c)
