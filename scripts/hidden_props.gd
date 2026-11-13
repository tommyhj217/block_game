# 숨은그림 장면에 들어가는 소품(사람, 동물, 가구, 책, 잡동사니)을 색칠된 그림으로 그리는 도구.
# 소품 하나 = "색칠 모양(뒤에 있는 것을 가림)" + "테두리 선" 목록.
# 좌표는 소품의 바닥 가운데가 (0, 0)이고 위쪽이 음수 y. begin()으로 위치·크기·뒤집기를 정하고 그린다.
# col(색)을 부르면 그 뒤에 그리는 모양이 그 색으로 칠해진다.
#
# 숨길 물건(HiddenShapes)과 똑같은 모양의 소품은 넣지 않는다 (예: 컵, 연필, 우산, 열쇠, 안경, 모자, 별, 하트).
# 그래야 찾을 물건이 그림 안에 하나뿐이다.
class_name HiddenProps
extends RefCounted

# ─── 색 모음 ───
const BRIGHT := ["#e76f51", "#f4a261", "#e9c46a", "#2a9d8f", "#4d96c9", "#8e7dbe", "#e5989b", "#6a994e", "#f28482", "#84a59d"]
const PASTEL := ["#ffd6a5", "#fdffb6", "#caffbf", "#9bf6ff", "#a0c4ff", "#bdb2ff", "#ffc6ff", "#ffadad"]
const WOOD := ["#c8965a", "#b9824a", "#d9a86c", "#a8743f"]
const SKIN := ["#ffe0c2", "#f6cfa8", "#e8b88a", "#c9925e"]
const HAIR := ["#3b2a20", "#5a3b25", "#8a5a2b", "#d9a441", "#1f1f24", "#b5532a"]
const GREEN := ["#6a994e", "#83b366", "#4f8a4b", "#a7c957"]
const PAPER := Color("#fffdf5")
const DARK := Color("#2b2620")

var rng: RandomNumberGenerator
var fills := []      # 지금 그리는 소품의 색칠 모양들 {"poly", "color", "ghost"}
var strokes := []    # 지금 그리는 소품의 선들 (그림 좌표)
var _xf := Transform2D.IDENTITY   # 소품 좌표 → 그림 좌표 변환
var _stack := []                  # push/pop용 (탁자 위에 물건을 올릴 때)
var _col := PAPER                 # 지금 칠하는 색


func _init(r: RandomNumberGenerator) -> void:
	rng = r


# 새 소품 시작. origin = 바닥 가운데 위치, s = 크기 배율, flip = 좌우 뒤집기
func begin(origin: Vector2, s: float, flip: bool = false, rot: float = 0.0) -> void:
	fills = []
	strokes = []
	_stack = []
	_col = PAPER
	# Transform2D(회전, 배율, 기울임, 위치)
	_xf = Transform2D(rot, Vector2(-s if flip else s, s), 0.0, origin)   # rot = 기울기(라디안)


func end() -> Dictionary:
	return {"fills": fills, "strokes": strokes}


# 지금 좌표계 안에서 (offset) 위치로 옮기고 s배로 줄여 그린다. 끝나면 pop()
func push(offset: Vector2, s: float) -> void:
	_stack.append(_xf)
	_xf = _xf * Transform2D(0.0, Vector2(s, s), 0.0, offset)


func pop() -> void:
	_xf = _stack.pop_back()


# ─── 색 고르기 ───

# 이 뒤로 칠하는 색을 정한다. 문자열("#ff0000")이나 Color 둘 다 된다.
func col(color) -> void:
	_col = Color(color) if color is String else color


func pick(list: Array) -> Color:
	return Color(list[rng.randi_range(0, list.size() - 1)])


# ─── 그리기 기본 ───

func L(points: Array) -> void:
	strokes.append(_xf * PackedVector2Array(points))


# 색칠만 (테두리 없음). ghost = true면 뒤의 선을 가리지 않는다 (그림자처럼 비치는 것)
func F(points: Array, ghost: bool = false) -> void:
	fills.append({"poly": _xf * PackedVector2Array(points), "color": _col, "ghost": ghost})


# 닫힌 모양: 색칠 + 테두리 선
func shape(points: Array, fill: bool = true) -> void:
	if fill:
		F(points)
	var closed := points.duplicate()
	closed.append(points[0])
	L(closed)


func rect(x0: float, y0: float, x1: float, y1: float, fill: bool = true) -> void:
	shape([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)], fill)


func arc_pts(c: Vector2, r: Vector2, a0: float, a1: float, n: int = 12) -> Array:
	var out := []
	for i in range(n + 1):
		var a := deg_to_rad(lerpf(a0, a1, float(i) / n))
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return out


func arc(c: Vector2, r: Vector2, a0: float, a1: float, n: int = 12) -> void:
	L(arc_pts(c, r, a0, a1, n))


func ellipse(c: Vector2, r: Vector2, fill: bool = true, n: int = 18) -> void:
	var pts := arc_pts(c, r, 0, 360, n)
	pts.pop_back()
	shape(pts, fill)


# 까만 점 (눈, 단추)
func dot(c: Vector2, r: float = 2.5) -> void:
	var keep := _col
	_col = DARK
	var pts := arc_pts(c, Vector2(r, r), 0, 360, 6)
	pts.pop_back()
	F(pts)
	_col = keep


# 바닥 그림자: 옅고 비치는 타원 (선 없음)
func shadow(rx: float, ry: float = -1.0) -> void:
	var keep := _col
	_col = Color(0.2, 0.12, 0.05, 0.16)
	var pts := arc_pts(Vector2(0, 0), Vector2(rx, ry if ry > 0 else rx * 0.22), 0, 360, 16)
	pts.pop_back()
	F(pts, true)
	_col = keep


func bumpy_pts(c: Vector2, r: Vector2, bumps: int, depth: float) -> Array:
	var out := []
	var n := bumps * 5
	var ph := rng.randf_range(0, TAU)
	for i in range(n):
		var a := TAU * i / n
		var k := 1.0 + depth * absf(sin(a * bumps / 2.0 + ph))
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y) * k)
	return out


func R(a: float, b: float) -> float:
	return rng.randf_range(a, b)


func chance(p: float) -> bool:
	return rng.randf() < p


# ═══════════════ 벽에 붙는 것 ═══════════════

func window(w: float, h: float) -> void:
	col(pick(WOOD))
	rect(-w / 2, -h, w / 2, 0)
	col("#bfe3f5")   # 하늘
	rect(-w / 2 + 10, -h + 10, w / 2 - 10, -10)
	# 바깥 풍경: 구름과 나무 꼭대기
	col("#ffffff")
	shape(bumpy_pts(Vector2(-w * 0.2, -h * 0.72), Vector2(w * 0.12, h * 0.06), 5, 0.3))
	col(pick(GREEN))
	shape(arc_pts(Vector2(w * 0.22, -10), Vector2(w * 0.17, h * 0.3), 180, 360, 10))
	L([Vector2(0, -h + 10), Vector2(0, -10)])
	L([Vector2(-w / 2 + 10, -h / 2), Vector2(w / 2 - 10, -h / 2)])
	# 커튼 (물결 모양 양쪽)
	var curtain := pick(BRIGHT)
	for side in [-1.0, 1.0]:
		col(curtain)
		var pts := [Vector2(side * w / 2, -h - 8)]
		for i in range(7):
			pts.append(Vector2(side * (w / 2 - 14 - (i % 2) * 8 - i * 3), -h + i * h / 6))
		pts.append(Vector2(side * (w / 2 + 6), 0))
		pts.append(Vector2(side * (w / 2 + 6), -h - 8))
		shape(pts)
		for i in range(3):
			L([Vector2(side * (w / 2 - 4 - i * 6), -h + 10), Vector2(side * (w / 2 - 6 - i * 8), -10)])
	col(pick(WOOD))
	rect(-w / 2 - 20, -h - 16, w / 2 + 20, -h - 8)


func clock(r: float) -> void:
	col(pick(BRIGHT))
	ellipse(Vector2(0, -r), Vector2(r, r))
	col("#ffffff")
	ellipse(Vector2(0, -r), Vector2(r * 0.82, r * 0.82))
	for i in range(12):
		var a := TAU * i / 12.0
		L([Vector2(0, -r) + Vector2.from_angle(a) * r * 0.66, Vector2(0, -r) + Vector2.from_angle(a) * r * 0.78])
	L([Vector2(0, -r), Vector2(0, -r) + Vector2.from_angle(R(0, TAU)) * r * 0.55])
	L([Vector2(0, -r), Vector2(0, -r) + Vector2.from_angle(R(0, TAU)) * r * 0.4])
	dot(Vector2(0, -r), 3)


func frame(w: float, h: float) -> void:
	col(pick(WOOD))
	rect(-w / 2, -h, w / 2, 0)
	col(pick(PASTEL))
	rect(-w / 2 + 8, -h + 8, w / 2 - 8, -8)
	# 안의 그림: 산과 해, 또는 꽃병
	if chance(0.5):
		col(pick(GREEN))
		shape([Vector2(-w / 2 + 8, -8), Vector2(-w / 2 + 8, -20), Vector2(-w * 0.1, -h * 0.6), Vector2(w * 0.1, -h * 0.35),
				Vector2(w * 0.25, -h * 0.55), Vector2(w / 2 - 8, -22), Vector2(w / 2 - 8, -8)])
		col("#ffd166")
		ellipse(Vector2(-w * 0.25, -h * 0.72), Vector2(9, 9))
	else:
		col(pick(BRIGHT))
		shape([Vector2(-w * 0.12, -12), Vector2(w * 0.12, -12), Vector2(w * 0.16, -h * 0.35), Vector2(-w * 0.16, -h * 0.35)])
		for i in range(3):
			col(pick(BRIGHT))
			shape(bumpy_pts(Vector2(-w * 0.15 + i * w * 0.15, -h * 0.55 - (i % 2) * 10), Vector2(10, 10), 5, 0.3))
	L([Vector2(-w * 0.2, -h), Vector2(0, -h - 22), Vector2(w * 0.2, -h)])


func board(w: float, h: float) -> void:
	col(pick(WOOD))
	rect(-w / 2, -h, w / 2, 0)
	col("#d8b98a")   # 코르크
	rect(-w / 2 + 8, -h + 8, w / 2 - 8, -8)
	for i in range(rng.randi_range(4, 7)):
		var c := Vector2(R(-w / 2 + 35, w / 2 - 35), R(-h + 35, -35))
		var nw := R(36, 56)
		var nh := R(30, 50)
		var rot := R(-0.25, 0.25)
		var pts := []
		for p in [Vector2(-nw / 2, -nh / 2), Vector2(nw / 2, -nh / 2), Vector2(nw / 2, nh / 2), Vector2(-nw / 2, nh / 2)]:
			var q: Vector2 = p
			pts.append(c + q.rotated(rot))
		col(pick(PASTEL))
		shape(pts)
		for k in range(2):
			L([c + Vector2(-nw / 2 + 6, -nh / 2 + 14 + k * 10).rotated(rot), c + Vector2(nw / 2 - 6, -nh / 2 + 14 + k * 10).rotated(rot)])
		col("#e63946")
		ellipse(c + Vector2(0, -nh / 2 + 5).rotated(rot), Vector2(4, 4), true, 8)


func bunting(w: float) -> void:
	# 양 끝이 높고 가운데가 처진 줄 + 줄에 매달린 세모 깃발
	var pts := arc_pts(Vector2(0, -60), Vector2(w / 2, 40), 180, 0, 12)
	L(pts)
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		col(BRIGHT[i % BRIGHT.size()])
		shape([a, b, a.lerp(b, 0.5) + Vector2(0, 34)])


# ═══════════════ 가구 ═══════════════

func bookshelf(w: float, h: float) -> void:
	shadow(w * 0.55, 14)
	var wood := pick(WOOD)
	col(wood)
	rect(-w / 2, -h, w / 2, 0)
	col(wood.darkened(0.35))   # 안쪽은 어둡게
	rect(-w / 2 + 8, -h + 8, w / 2 - 8, -8)
	var shelves := rng.randi_range(3, 4)
	var sh := (h - 20) / shelves
	for k in range(shelves):
		var y_bottom := -10 - k * sh
		var x := -w / 2 + 10
		while x < w / 2 - 22:
			var bw := R(12, 26)
			var bh := sh * R(0.55, 0.88)
			if chance(0.1):
				x += R(10, 30)   # 빈칸
				continue
			col(pick(BRIGHT))
			if chance(0.12) and x + bh < w / 2 - 10:
				# 기울어진 책
				shape([Vector2(x, y_bottom), Vector2(x + bw * 0.8, y_bottom), Vector2(x + bh * 0.55 + bw * 0.8, y_bottom - bh * 0.8), Vector2(x + bh * 0.55, y_bottom - bh * 0.83)])
				x += bw + bh * 0.55 + 4
				continue
			rect(x, y_bottom - bh, x + bw, y_bottom)
			if chance(0.6):
				L([Vector2(x + 2, y_bottom - bh * 0.25), Vector2(x + bw - 2, y_bottom - bh * 0.25)])
			if chance(0.4):
				L([Vector2(x + 2, y_bottom - bh * 0.75), Vector2(x + bw - 2, y_bottom - bh * 0.75)])
			x += bw + R(0, 3)
		col(wood)
		rect(-w / 2 + 8, y_bottom, w / 2 - 8, y_bottom + 6)
	col(wood.lightened(0.15))
	rect(-w / 2 - 6, -h - 8, w / 2 + 6, -h)


func table(w: float, h: float, items: bool = true) -> void:
	shadow(w * 0.5, 16)
	var wood := pick(WOOD)
	col(wood.darkened(0.15))
	for x in [-w / 2 + 12, w / 2 - 22]:
		rect(x, -h, x + 10, 0)
	var d := 34.0
	col(wood.lightened(0.2))
	shape([Vector2(-w / 2, -h), Vector2(w / 2, -h), Vector2(w / 2 - 22, -h - d), Vector2(-w / 2 + 22, -h - d)])
	col(wood)
	rect(-w / 2, -h, w / 2, -h + 12)
	if items:
		var n := rng.randi_range(1, 3)
		for i in range(n):
			var x := lerpf(-w / 2 + 40, w / 2 - 40, (i + 0.5) / n) + R(-10, 10)
			push(Vector2(x, -h - d * 0.4), 0.55)
			match rng.randi_range(0, 4):
				0: book_stack(false)
				1: globe(false)
				2: plant(true, false)
				3: open_book_flat()
				_: basket(false)
			pop()


func desk(w: float, h: float) -> void:
	shadow(w * 0.52, 16)
	var wood := pick(WOOD)
	col(wood)
	rect(-w / 2, -h, w / 2, 0)
	col(wood.lightened(0.12))
	for k in range(3):
		var y := -h + 14 + k * (h - 24) / 3.0
		rect(w * 0.05, y, w / 2 - 10, y + (h - 24) / 3.0 - 4)
		dot(Vector2(w * 0.27, y + (h - 24) / 6.0), 3)
	var d := 30.0
	col(wood.lightened(0.25))
	shape([Vector2(-w / 2, -h), Vector2(w / 2, -h), Vector2(w / 2 - 18, -h - d), Vector2(-w / 2 + 18, -h - d)])
	push(Vector2(-w * 0.2, -h - d * 0.4), 0.5)
	if chance(0.5):
		book_stack(false)
	else:
		lamp_small()
	pop()


func chair(h: float) -> void:
	var w := h * 0.42
	shadow(w * 0.7)
	var c := pick(BRIGHT) if chance(0.5) else pick(WOOD)
	col(c.darkened(0.15))
	for x in [-w / 2, w / 2 - 6]:
		rect(x, -h * 0.48, x + 6, 0)
	col(c.lightened(0.15))
	shape([Vector2(-w / 2, -h * 0.48), Vector2(w / 2, -h * 0.48), Vector2(w / 2 - 10, -h * 0.56), Vector2(-w / 2 + 10, -h * 0.56)])
	col(c)
	rect(-w / 2 + 6, -h, w / 2 - 6, -h * 0.56)
	for k in range(3):
		var x := lerpf(-w / 2 + 14, w / 2 - 14, k / 2.0)
		L([Vector2(x, -h + 10), Vector2(x, -h * 0.6)])


func stool(h: float) -> void:
	var w := h * 0.55
	shadow(w * 0.6)
	L([Vector2(-w * 0.35, -h * 0.9), Vector2(-w * 0.5, 0)])
	L([Vector2(w * 0.35, -h * 0.9), Vector2(w * 0.5, 0)])
	L([Vector2(0, -h * 0.9), Vector2(0, -6)])
	L([Vector2(-w * 0.42, -h * 0.4), Vector2(w * 0.42, -h * 0.4)])
	col(pick(BRIGHT))
	ellipse(Vector2(0, -h * 0.92), Vector2(w / 2, w * 0.16))


func floor_lamp(h: float) -> void:
	shadow(36)
	col("#8d8d99")
	ellipse(Vector2(0, -6), Vector2(30, 8))
	rect(-3, -h * 0.75, 3, -6)
	col(pick(PASTEL))
	shape([Vector2(-h * 0.13, -h * 0.72), Vector2(h * 0.13, -h * 0.72), Vector2(h * 0.08, -h), Vector2(-h * 0.08, -h)])
	L([Vector2(h * 0.06, -h * 0.72), Vector2(h * 0.06, -h * 0.6)])
	dot(Vector2(h * 0.06, -h * 0.58), 3)


func lamp_small() -> void:
	col("#8d8d99")
	ellipse(Vector2(0, -6), Vector2(26, 8))
	L([Vector2(0, -6), Vector2(-20, -60), Vector2(10, -100)])
	col(pick(BRIGHT))
	shape([Vector2(0, -95), Vector2(40, -110), Vector2(30, -75)])


func plant(small: bool = false, with_shadow: bool = true) -> void:
	var s := 0.7 if small else 1.0
	if with_shadow:
		shadow(40 * s)
	var pot := pick(["#c8553d", "#d98a5f", "#b56b45", "#7fa6c9", "#e9c46a"])
	col(pot)
	shape([Vector2(-34 * s, -60 * s), Vector2(34 * s, -60 * s), Vector2(26 * s, 0), Vector2(-26 * s, 0)])
	col(pot.lightened(0.15))
	rect(-38 * s, -72 * s, 38 * s, -60 * s)
	var green := pick(GREEN)
	var n := rng.randi_range(5, 8)
	for i in range(n):
		var a := deg_to_rad(lerpf(-160, -20, float(i) / (n - 1)) + R(-8, 8))
		var l := R(60, 110) * s
		var base := Vector2(0, -72 * s)
		var tip := base + Vector2.from_angle(a) * l
		var mid := base.lerp(tip, 0.5)
		var nrm := (tip - base).orthogonal().normalized() * l * 0.18
		col(green.lightened(R(0.0, 0.2)))
		shape([base, mid + nrm, tip, mid - nrm])
		L([base, tip.lerp(base, 0.15)])


func box(w: float, h: float) -> void:
	var d := w * 0.3
	shadow(w * 0.62)
	var c := pick(["#d4a373", "#c9a66b", "#e0b98a"])
	col(c)
	rect(-w / 2, -h, w / 2, 0)
	col(c.lightened(0.18))
	shape([Vector2(-w / 2, -h), Vector2(w / 2, -h), Vector2(w / 2 + d * 0.6, -h - d * 0.5), Vector2(-w / 2 + d * 0.6, -h - d * 0.5)])
	col(c.darkened(0.15))
	shape([Vector2(w / 2, -h), Vector2(w / 2 + d * 0.6, -h - d * 0.5), Vector2(w / 2 + d * 0.6, -d * 0.5), Vector2(w / 2, 0)])
	L([Vector2(0, -h), Vector2(0, -h * 0.6)])
	if chance(0.4):
		# 상자 위로 책이 삐져나옴
		for i in range(2):
			var x := R(-w / 2 + 10, w / 2 - 30)
			var top := R(30, 50)
			col(pick(BRIGHT))
			shape([Vector2(x, -h - 2), Vector2(x + 18, -h - 2), Vector2(x + 28, -h - top), Vector2(x + 10, -h - top)])
	else:
		col(PAPER)
		rect(-w * 0.3, -h * 0.55, w * 0.2, -h * 0.3)
		L([Vector2(-w * 0.24, -h * 0.45), Vector2(w * 0.14, -h * 0.45)])


func book_stack(with_shadow: bool = true) -> void:
	if with_shadow:
		shadow(56)
	var y := 0.0
	for i in range(rng.randi_range(3, 6)):
		var bw := R(70, 100)
		var bh := R(12, 20)
		var off := R(-10, 10)
		col(pick(BRIGHT))
		rect(-bw / 2 + off, y - bh, bw / 2 + off, y)
		col(PAPER)
		rect(bw / 2 + off - 10, y - bh + 3, bw / 2 + off, y - 3)
		y -= bh


func open_book_flat() -> void:
	col(pick(BRIGHT))
	shape([Vector2(-64, -8), Vector2(0, 4), Vector2(64, -8), Vector2(58, -42), Vector2(0, -30), Vector2(-58, -42)])
	col(PAPER)
	shape([Vector2(-60, -10), Vector2(0, 0), Vector2(0, -30), Vector2(-56, -40)])
	shape([Vector2(60, -10), Vector2(0, 0), Vector2(0, -30), Vector2(56, -40)])
	for k in range(3):
		L([Vector2(-48, -14 - k * 7), Vector2(-8, -6 - k * 7)])
		L([Vector2(48, -14 - k * 7), Vector2(8, -6 - k * 7)])


func flat_book(w: float) -> void:
	var rot := R(-0.5, 0.5)
	var h := w * R(0.55, 0.75)
	var pts := []
	for p in [Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)]:
		var q: Vector2 = p
		pts.append(Vector2(q.x, q.y * 0.45).rotated(rot * 0.3) + Vector2(0, -h * 0.25))
	col(pick(BRIGHT))
	shape(pts)
	L([pts[0] + (pts[1] - pts[0]) * 0.12, pts[3] + (pts[2] - pts[3]) * 0.12])


func paper(w: float) -> void:
	var rot := R(-0.8, 0.8)
	var pts := []
	for p in [Vector2(-w / 2, -w * 0.35), Vector2(w / 2, -w * 0.35), Vector2(w / 2, w * 0.35), Vector2(-w / 2, w * 0.35)]:
		var q: Vector2 = p.rotated(rot)
		pts.append(Vector2(q.x, q.y * 0.5))
	col(PAPER if chance(0.6) else pick(PASTEL))
	shape(pts)
	for k in range(3):
		var t := 0.25 + k * 0.22
		L([pts[0].lerp(pts[3], t) + (pts[1] - pts[0]) * 0.15, pts[1].lerp(pts[2], t) - (pts[1] - pts[0]) * 0.15])


func rug(w: float) -> void:
	var c1 := pick(BRIGHT)
	var c2 := pick(PASTEL)
	col(c1)
	ellipse(Vector2(0, 0), Vector2(w / 2, w * 0.13), true, 28)
	col(c2)
	ellipse(Vector2(0, 0), Vector2(w * 0.4, w * 0.1), true, 24)
	col(c1.lightened(0.25))
	ellipse(Vector2(0, 0), Vector2(w * 0.25, w * 0.06), true, 20)
	for i in range(16):
		var a := TAU * i / 16.0
		var p := Vector2(cos(a) * w / 2, sin(a) * w * 0.13)
		L([p, p * 1.07])


func ball(r: float) -> void:
	shadow(r * 1.1)
	col(pick(BRIGHT))
	ellipse(Vector2(0, -r), Vector2(r, r))
	arc(Vector2(-r * 0.9, -r), Vector2(r * 0.6, r), -60, 60, 8)
	arc(Vector2(r * 0.9, -r), Vector2(r * 0.6, r), 120, 240, 8)


func blocks() -> void:
	shadow(50)
	# 장난감 쌓기 블록
	for i in range(rng.randi_range(2, 4)):
		var x := R(-40, 40)
		var y := -i * 30.0
		var c := pick(BRIGHT)
		col(c)
		rect(x - 15, y - 30, x + 15, y)
		col(c.lightened(0.25))
		shape([Vector2(x - 15, y - 30), Vector2(x + 15, y - 30), Vector2(x + 22, y - 36), Vector2(x - 8, y - 36)])
		L([Vector2(x - 8, y - 20), Vector2(x + 8, y - 10)])


func backpack(h: float) -> void:
	var w := h * 0.7
	shadow(w * 0.6)
	var c := pick(BRIGHT)
	col(c)
	var pts := arc_pts(Vector2(0, -h + w / 2), Vector2(w / 2, w / 2), 180, 360, 10)
	pts.append(Vector2(w / 2, -6))
	pts.append(Vector2(-w / 2, -6))
	shape(pts)
	col(c.lightened(0.25))
	rect(-w * 0.35, -h * 0.42, w * 0.35, -10)
	L([Vector2(-w * 0.3, -h * 0.3), Vector2(w * 0.3, -h * 0.3)])
	arc(Vector2(0, -h), Vector2(w * 0.18, 14), 180, 360, 8)
	L([Vector2(-w / 2 + 6, -h * 0.7), Vector2(-w / 2 - 6, -h * 0.25)])


func globe(with_shadow: bool = true) -> void:
	if with_shadow:
		shadow(42)
	col(pick(WOOD))
	ellipse(Vector2(0, -12), Vector2(36, 8))
	L([Vector2(0, -12), Vector2(0, -40)])
	arc(Vector2(0, -90), Vector2(56, 56), 30, 150, 10)
	col("#8ecae6")
	ellipse(Vector2(0, -90), Vector2(46, 46))
	col("#95d5b2")
	shape(bumpy_pts(Vector2(-14, -100), Vector2(16, 12), 5, 0.35))
	shape(bumpy_pts(Vector2(18, -76), Vector2(11, 9), 4, 0.3))
	arc(Vector2(0, -90), Vector2(20, 46), -90, 90, 10)
	L([Vector2(-46, -90), Vector2(46, -90)])


func basket(with_shadow: bool = true) -> void:
	if with_shadow:
		shadow(52)
	# 바구니 안의 실뭉치 (바구니 뒤쪽에 먼저 그려서 위로 반만 보이게)
	for i in range(rng.randi_range(1, 3)):
		col(pick(BRIGHT))
		ellipse(Vector2(R(-28, 28), -54), Vector2(14, 13), true, 10)
	col("#d9a86c")
	shape([Vector2(-50, -50), Vector2(50, -50), Vector2(38, 0), Vector2(-38, 0)])
	for k in range(1, 4):
		var y := -50 + k * 12.5
		L([Vector2(-50 + k * 3, y), Vector2(50 - k * 3, y)])
	for k in range(-3, 4):
		L([Vector2(k * 13, -50), Vector2(k * 10, 0)])
	arc(Vector2(0, -50), Vector2(42, 40), 180, 360, 12)


func bin() -> void:
	shadow(36)
	col(pick(["#9aa5b1", "#7fa6c9", "#84a59d"]))
	shape([Vector2(-34, -80), Vector2(34, -80), Vector2(26, 0), Vector2(-26, 0)])
	for k in range(-2, 3):
		L([Vector2(k * 12, -76), Vector2(k * 9, -4)])
	col(PAPER)
	for i in range(rng.randi_range(1, 3)):
		var c := Vector2(R(-20, 20), -86 - i * 6)
		shape(bumpy_pts(c, Vector2(14, 11), 6, 0.3))
		L([c + Vector2(-6, -2), c + Vector2(4, 3)])


# ═══════════════ 사람과 동물 ═══════════════

# 서 있는 아이. 머리 모양·옷 색과 무늬·팔 자세가 무작위로 달라진다.
func kid() -> void:
	shadow(44)
	var skin := pick(SKIN)
	var shirt := pick(BRIGHT)
	var bottom := pick(["#4a6fa5", "#5c677d", "#7d5a50", "#386641", "#8e7dbe", "#bc4749"])
	var skirt := chance(0.4)
	# 다리와 신발
	if skirt:
		col(skin)
		rect(-17, -62, -8, -6)
		rect(8, -62, 17, -6)
	else:
		col(bottom)
		rect(-24, -92, -3, -6)
		rect(3, -92, 24, -6)
	col(pick(["#e63946", "#f1faee", "#457b9d", "#ffb703", "#3a3a3a"]))
	ellipse(Vector2(-16, -5), Vector2(14, 7))
	ellipse(Vector2(16, -5), Vector2(14, 7))
	# 몸통
	col(shirt)
	if skirt:
		shape([Vector2(-26, -150), Vector2(26, -150), Vector2(42, -56), Vector2(-42, -56)])
	else:
		shape([Vector2(-28, -158), Vector2(28, -158), Vector2(30, -88), Vector2(-30, -88)])
	match rng.randi_range(0, 3):
		0:
			col(shirt.lightened(0.45))
			for k in range(2):
				rect(-27, -142 + k * 24, 27, -132 + k * 24)
		1:
			col(PAPER)
			for k in range(5):
				ellipse(Vector2(R(-18, 18), R(-145, -100)), Vector2(4, 4), true, 6)
		2:
			col(shirt.lightened(0.4))
			rect(6, -140, 20, -124)
		_:
			L([Vector2(0, -158), Vector2(0, -92)])
			for k in range(3):
				dot(Vector2(-5, -146 + k * 18), 2.5)
	# 팔
	var pose := rng.randi_range(0, 3)
	for side in [-1.0, 1.0]:
		var sh := Vector2(side * 28, -150)
		var hand: Vector2
		match pose:
			0: hand = Vector2(side * 44, -96)                     # 내림
			1: hand = Vector2(side * 52, -206) if side > 0 else Vector2(-44, -96)  # 한 손 들기
			2: hand = Vector2(side * 14, -118)                    # 앞으로 (책 들기)
			_: hand = Vector2(side * 60, -150)                    # 벌림
		# 팔은 어깨에서 손까지 이어지는 좁은 네모
		var n := (hand - sh).orthogonal().normalized() * 7.0
		col(shirt)
		shape([sh + n, hand + n, hand - n, sh - n])
		col(skin)
		ellipse(hand, Vector2(8, 8), true, 8)
	if pose == 2:
		col(pick(BRIGHT))
		shape([Vector2(-34, -128), Vector2(34, -128), Vector2(30, -96), Vector2(-30, -96)])
		L([Vector2(0, -128), Vector2(0, -96)])
	# 머리
	var hc := Vector2(0, -192)
	col(skin)
	ellipse(hc, Vector2(32, 32))
	_hair(hc)
	dot(hc + Vector2(-11, 2), 3)
	dot(hc + Vector2(11, 2), 3)
	arc(hc + Vector2(0, 10), Vector2(9, 6), 20, 160, 6)
	col("#ffb4a2")
	ellipse(hc + Vector2(-20, 12), Vector2(5, 3), true, 6)
	ellipse(hc + Vector2(20, 12), Vector2(5, 3), true, 6)


func _hair(hc: Vector2) -> void:
	col(pick(HAIR))
	match rng.randi_range(0, 3):
		0:  # 단발
			shape(arc_pts(hc, Vector2(36, 36), 180, 360, 12) + [hc + Vector2(36, 18), hc + Vector2(24, 4), hc + Vector2(-24, 4), hc + Vector2(-36, 18)])
		1:  # 삐죽 머리
			var pts := []
			for i in range(9):
				var a := deg_to_rad(lerpf(190, 350, i / 8.0))
				var r := 46.0 if i % 2 == 1 else 31.0
				pts.append(hc + Vector2(cos(a), sin(a)) * r)
			shape(pts)
		2:  # 양 갈래로 묶은 머리
			ellipse(hc + Vector2(40, -14), Vector2(12, 16))
			ellipse(hc + Vector2(-40, -14), Vector2(12, 16))
			shape(arc_pts(hc, Vector2(34, 34), 190, 350, 10))
		_:  # 곱슬
			var top := []
			for p in bumpy_pts(hc + Vector2(0, -12), Vector2(36, 26), 9, 0.25):
				if p.y < hc.y - 4:
					top.append(p)
			if top.size() >= 3:
				shape(top)


# 바닥에 앉아 책 읽는 아이
func kid_sitting() -> void:
	shadow(70, 14)
	var skin := pick(SKIN)
	var shirt := pick(BRIGHT)
	col(pick(["#4a6fa5", "#5c677d", "#7d5a50", "#386641"]))
	rect(-10, -26, 70, -6)
	rect(-10, -48, 64, -28)
	col("#3a3a3a")
	ellipse(Vector2(76, -16), Vector2(8, 12))
	ellipse(Vector2(70, -38), Vector2(8, 12))
	col(shirt)
	shape([Vector2(-34, -120), Vector2(14, -120), Vector2(20, -20), Vector2(-40, -20)])
	if chance(0.5):
		col(shirt.lightened(0.4))
		rect(-36, -92, 16, -80)
	# 책
	col(pick(BRIGHT))
	shape([Vector2(4, -70), Vector2(40, -86), Vector2(40, -40), Vector2(4, -26)])
	shape([Vector2(4, -70), Vector2(-24, -84), Vector2(-24, -40), Vector2(4, -26)])
	L([Vector2(-30, -110), Vector2(-20, -60)])
	L([Vector2(10, -110), Vector2(30, -66)])
	var hc := Vector2(-10, -152)
	col(skin)
	ellipse(hc, Vector2(30, 30))
	_hair(hc)
	arc(hc + Vector2(-10, 4), Vector2(5, 3), 20, 160, 5)
	arc(hc + Vector2(10, 4), Vector2(5, 3), 20, 160, 5)
	arc(hc + Vector2(0, 14), Vector2(6, 4), 20, 160, 5)


func cat() -> void:
	shadow(36)
	var fur := pick(["#f4a259", "#9a9a9a", "#f5f0e6", "#4a4a4a", "#d9b08c"])
	col(fur)
	# 꼬리 (두께가 있는 곡선)
	var tail_a := []
	var tail_b := []
	for i in range(8):
		var t := i / 7.0
		var p := Vector2(24 + t * 30, -10 - sin(t * PI) * 40 - t * 20)
		tail_a.append(p + Vector2(0, -5))
		tail_b.append(p + Vector2(0, 5))
	tail_b.reverse()
	shape(tail_a + tail_b)
	ellipse(Vector2(0, -38), Vector2(30, 36))
	var hc := Vector2(0, -88)
	shape([hc + Vector2(-22, -10), hc + Vector2(-18, -36), hc + Vector2(-4, -22)])
	shape([hc + Vector2(22, -10), hc + Vector2(18, -36), hc + Vector2(4, -22)])
	ellipse(hc, Vector2(24, 21))
	dot(hc + Vector2(-8, -2), 2.5)
	dot(hc + Vector2(8, -2), 2.5)
	L([hc + Vector2(-4, 6), hc + Vector2(0, 9), hc + Vector2(4, 6)])
	for s in [-1.0, 1.0]:
		L([hc + Vector2(s * 8, 8), hc + Vector2(s * 30, 4)])
		L([hc + Vector2(s * 8, 10), hc + Vector2(s * 30, 14)])
	L([Vector2(-10, -4), Vector2(-10, -30)])
	L([Vector2(10, -4), Vector2(10, -30)])


func dog() -> void:
	shadow(60)
	var fur := pick(["#c68642", "#f5f0e6", "#8d5524", "#e0ac69", "#6b6b6b"])
	col(fur)
	for x in [-34, -18, 20, 36]:
		rect(x - 6, -36, x + 6, 0)
	shape([Vector2(46, -62), Vector2(66, -86), Vector2(74, -80), Vector2(54, -52)])
	ellipse(Vector2(0, -50), Vector2(52, 28))
	var hc := Vector2(-54, -82)
	ellipse(hc, Vector2(26, 23))
	col(fur.lightened(0.3))
	ellipse(hc + Vector2(-22, 8), Vector2(14, 10))
	dot(hc + Vector2(-34, 6), 4)
	dot(hc + Vector2(-6, -6), 2.5)
	col(fur.darkened(0.3))
	shape([hc + Vector2(8, -16), hc + Vector2(24, -10), hc + Vector2(22, 22), hc + Vector2(10, 18)])
	arc(hc + Vector2(-20, 18), Vector2(8, 5), 20, 160, 5)


func bear() -> void:
	shadow(40)
	var fur := pick(["#b08968", "#9c6644", "#ddb892", "#e5989b"])
	col(fur)
	ellipse(Vector2(-26, -8), Vector2(14, 10))
	ellipse(Vector2(26, -8), Vector2(14, 10))
	shape([Vector2(-26, -64), Vector2(-50, -42), Vector2(-42, -34), Vector2(-22, -50)])
	shape([Vector2(26, -64), Vector2(50, -42), Vector2(42, -34), Vector2(22, -50)])
	ellipse(Vector2(0, -40), Vector2(34, 38))
	col(fur.lightened(0.3))
	ellipse(Vector2(0, -36), Vector2(16, 18))
	var hc := Vector2(0, -96)
	col(fur)
	ellipse(hc + Vector2(-22, -20), Vector2(11, 11))
	ellipse(hc + Vector2(22, -20), Vector2(11, 11))
	ellipse(hc, Vector2(28, 25))
	col(fur.lightened(0.3))
	ellipse(hc + Vector2(0, 8), Vector2(11, 8))
	dot(hc + Vector2(0, 4), 3)
	dot(hc + Vector2(-10, -6), 2.5)
	dot(hc + Vector2(10, -6), 2.5)


func rabbit() -> void:
	shadow(30)
	var fur := pick(["#ffffff", "#f1e3d3", "#d6ccc2", "#ffe5ec"])
	col(fur)
	ellipse(Vector2(24, -16), Vector2(8, 8))
	ellipse(Vector2(0, -30), Vector2(26, 30))
	var hc := Vector2(0, -74)
	ellipse(hc + Vector2(-9, -40), Vector2(7, 24))
	ellipse(hc + Vector2(9, -40), Vector2(7, 24))
	col("#ffc2d1")
	ellipse(hc + Vector2(-9, -40), Vector2(3, 16), true, 8)
	ellipse(hc + Vector2(9, -40), Vector2(3, 16), true, 8)
	col(fur)
	ellipse(hc, Vector2(20, 18))
	dot(hc + Vector2(-7, -2), 2.5)
	dot(hc + Vector2(7, -2), 2.5)
	L([hc + Vector2(-3, 7), hc + Vector2(0, 9), hc + Vector2(3, 7)])


# ═══════════════ 공원 ═══════════════

func sun(r: float) -> void:
	col("#ffd166")
	# 햇살 (세모)
	for i in range(12):
		var a := TAU * i / 12.0
		var d := Vector2.from_angle(a)
		var n := d.orthogonal() * r * 0.16
		shape([d * (r + 8) + n, d * (r + 8) - n, d * (r + R(30, 46))])
	col("#ffe08a")
	ellipse(Vector2.ZERO, Vector2(r, r))
	dot(Vector2(-r * 0.3, -r * 0.1), 4)
	dot(Vector2(r * 0.3, -r * 0.1), 4)
	arc(Vector2(0, r * 0.15), Vector2(r * 0.4, r * 0.3), 20, 160, 10)


func cloud(w: float) -> void:
	col("#ffffff")
	shape(bumpy_pts(Vector2.ZERO, Vector2(w / 2, w * 0.2), rng.randi_range(5, 8), 0.25))
	arc(Vector2(-w * 0.15, 0), Vector2(w * 0.16, w * 0.08), 200, 320, 8)


func house(w: float, h: float) -> void:
	col(pick(PASTEL))
	rect(-w / 2, -h, w / 2, 0)
	col(pick(["#e76f51", "#bc4749", "#8e7dbe", "#4d96c9", "#b5653a"]))
	shape([Vector2(-w / 2 - 16, -h), Vector2(0, -h - h * 0.6), Vector2(w / 2 + 16, -h)])
	# 지붕 기와 줄
	for k in range(1, 4):
		var t := k / 4.0
		L([Vector2(-(w / 2 + 16) * t, -h - h * 0.6 * (1.0 - t)), Vector2((w / 2 + 16) * t, -h - h * 0.6 * (1.0 - t))])
	col(pick(WOOD))
	rect(-w * 0.1, -h * 0.55, w * 0.1, 0)
	dot(Vector2(w * 0.06, -h * 0.28), 3)
	col("#bfe3f5")
	for sx in [-0.32, 0.32]:
		rect(w * sx - w * 0.1, -h * 0.75, w * sx + w * 0.1, -h * 0.4)
		L([Vector2(w * sx, -h * 0.75), Vector2(w * sx, -h * 0.4)])
		L([Vector2(w * sx - w * 0.1, -h * 0.575), Vector2(w * sx + w * 0.1, -h * 0.575)])
	# 굴뚝
	col(pick(["#b5653a", "#9aa5b1"]))
	rect(w * 0.2, -h - h * 0.55, w * 0.32, -h - h * 0.2)


func tree(h: float) -> void:
	shadow(h * 0.22)
	var trunk_w := h * 0.1
	col(pick(["#9c6644", "#7f5539", "#b08968"]))
	shape([Vector2(-trunk_w * 0.9, 0), Vector2(-trunk_w / 2, -h * 0.55), Vector2(trunk_w / 2, -h * 0.55), Vector2(trunk_w * 0.9, 0)])
	for k in range(3):
		arc(Vector2(0, -R(h * 0.08, h * 0.45)), Vector2(trunk_w * 0.3, 6), 200, 340, 5)
	var green := pick(GREEN)
	var c := Vector2(0, -h * 0.72)
	var cr := h * 0.32
	col(green)
	shape(bumpy_pts(c, Vector2(cr, cr * 0.85), rng.randi_range(7, 10), 0.16))
	# 잎 덩어리 무늬
	for k in range(rng.randi_range(6, 10)):
		var p := c + Vector2.from_angle(R(0, TAU)) * R(0, cr * 0.65)
		var lr := R(10, 18)
		var a0 := R(0, 360)
		arc(p, Vector2(lr, lr * 0.8), a0, a0 + 200, 7)
	# 열매 (동그란 열매 — 숨길 물건과 겹치지 않는 모양)
	if chance(0.5):
		col(pick(["#e63946", "#ff9f1c", "#f28482"]))
		for k in range(rng.randi_range(2, 5)):
			ellipse(c + Vector2.from_angle(R(0, TAU)) * R(cr * 0.2, cr * 0.7), Vector2(8, 8), true, 8)


func bush(w: float) -> void:
	shadow(w * 0.5)
	col(pick(GREEN))
	var pts := []
	for p in bumpy_pts(Vector2(0, -w * 0.28), Vector2(w / 2, w * 0.3), 7, 0.2):
		pts.append(Vector2(p.x, minf(p.y, 0.0)))   # 바닥 아래로 내려가지 않게
	shape(pts)
	for k in range(4):
		var p := Vector2(R(-w * 0.3, w * 0.3), R(-w * 0.45, -w * 0.1))
		arc(p, Vector2(12, 9), 190, 350, 6)
	if chance(0.6):
		col(pick(["#ffadad", "#ffffff", "#ffd166", "#ffc6ff"]))
		for k in range(rng.randi_range(3, 6)):
			ellipse(Vector2(R(-w * 0.35, w * 0.35), R(-w * 0.45, -w * 0.1)), Vector2(6, 6), true, 6)


func bench(w: float) -> void:
	shadow(w * 0.5, 12)
	var wood := pick(WOOD)
	col("#6b6b6b")
	for x in [-w / 2 + 14, w / 2 - 22]:
		rect(x, -60, x + 8, 0)
	col(wood)
	rect(-w / 2, -66, w / 2, -52)                 # 앉는 곳
	for k in range(3):                            # 등받이 널빤지
		rect(-w / 2, -130 + k * 22, w / 2, -114 + k * 22)
	col("#6b6b6b")
	rect(-w / 2 + 14, -130, -w / 2 + 22, -66)
	rect(w / 2 - 22, -130, w / 2 - 14, -66)


func duck() -> void:
	shadow(34)
	var body := pick(["#ffffff", "#ffe08a", "#f1e3d3"])
	col("#ff9f1c")
	shape([Vector2(-8, -6), Vector2(-20, 0), Vector2(0, 0)])
	shape([Vector2(10, -6), Vector2(0, 0), Vector2(20, 0)])
	col(body)
	shape([Vector2(-34, -40), Vector2(-48, -56), Vector2(-30, -30), Vector2(-20, -8), Vector2(22, -8), Vector2(34, -30), Vector2(20, -50), Vector2(-10, -50)])
	arc(Vector2(-6, -30), Vector2(18, 12), 20, 160, 6)
	ellipse(Vector2(28, -62), Vector2(16, 15))
	col("#ff9f1c")
	shape([Vector2(42, -64), Vector2(60, -58), Vector2(42, -54)])
	dot(Vector2(32, -66), 2.5)


func slide(h: float) -> void:
	shadow(h * 0.6, 14)
	var c := pick(BRIGHT)
	# 사다리
	col("#8d8d99")
	rect(-h * 0.5, -h, -h * 0.5 + 8, 0)
	rect(-h * 0.5 + 44, -h, -h * 0.5 + 52, 0)
	for k in range(5):
		L([Vector2(-h * 0.5 + 8, -h * 0.15 - k * h * 0.17), Vector2(-h * 0.5 + 44, -h * 0.15 - k * h * 0.17)])
	# 미끄러지는 판
	col(c)
	shape([Vector2(-h * 0.5 + 52, -h * 0.9), Vector2(-h * 0.5 + 52, -h * 0.76), Vector2(h * 0.45, -8), Vector2(h * 0.62, -8), Vector2(h * 0.62, -20), Vector2(h * 0.48, -22)])
	col(c.lightened(0.25))
	shape([Vector2(-h * 0.5 - 6, -h - 4), Vector2(-h * 0.5 + 58, -h - 4), Vector2(-h * 0.5 + 58, -h * 0.9), Vector2(-h * 0.5 - 6, -h * 0.9)])


func street_lamp(h: float) -> void:
	shadow(26)
	col("#5c677d")
	ellipse(Vector2(0, -6), Vector2(20, 7))
	rect(-5, -h * 0.85, 5, -6)
	col("#fff3b0")
	shape([Vector2(-22, -h * 0.85), Vector2(22, -h * 0.85), Vector2(16, -h), Vector2(-16, -h)])
	col("#5c677d")
	shape([Vector2(-20, -h), Vector2(20, -h), Vector2(0, -h - 18)])


func balloons() -> void:
	# 바닥의 돌에 묶인 풍선 다발
	shadow(20)
	col("#9aa5b1")
	ellipse(Vector2(0, -8), Vector2(16, 9))
	for i in range(rng.randi_range(3, 5)):
		var top := Vector2(R(-60, 60), -R(170, 260))
		L([Vector2(0, -12), Vector2(top.x * 0.4, top.y * 0.5), top + Vector2(0, 30)])
		col(pick(BRIGHT))
		ellipse(top, Vector2(24, 30))
		shape([top + Vector2(-5, 34), top + Vector2(5, 34), top + Vector2(0, 28)])
		arc(top + Vector2(-8, -8), Vector2(8, 12), 180, 260, 4)


func sandbox(w: float) -> void:
	var wood := pick(WOOD)
	col(wood)
	shape([Vector2(-w / 2, 0), Vector2(w / 2, 0), Vector2(w / 2 - 36, -w * 0.3), Vector2(-w / 2 + 36, -w * 0.3)])
	col("#f3e1b0")
	shape([Vector2(-w / 2 + 22, -10), Vector2(w / 2 - 22, -10), Vector2(w / 2 - 48, -w * 0.3 + 8), Vector2(-w / 2 + 48, -w * 0.3 + 8)])
	# 모래 더미와 양동이
	shape(arc_pts(Vector2(-w * 0.15, -18), Vector2(40, 34), 180, 360, 8))
	col(pick(BRIGHT))
	shape([Vector2(w * 0.1, -50), Vector2(w * 0.1 + 34, -50), Vector2(w * 0.1 + 28, -16), Vector2(w * 0.1 + 6, -16)])
	arc(Vector2(w * 0.1 + 17, -50), Vector2(17, 18), 180, 360, 8)


func sign() -> void:
	shadow(22)
	col(pick(WOOD))
	rect(-5, -120, 5, 0)
	col(pick(PASTEL))
	rect(-56, -150, 56, -90)
	L([Vector2(-40, -130), Vector2(40, -130)])
	L([Vector2(-40, -112), Vector2(20, -112)])


func bike() -> void:
	shadow(70, 12)
	var c := pick(BRIGHT)
	col("#f5f0e6")
	for x in [-50.0, 50.0]:
		ellipse(Vector2(x, -32), Vector2(32, 32))
		col("#dcd6c8")
		ellipse(Vector2(x, -32), Vector2(24, 24))
		for k in range(4):
			var a := TAU * k / 8.0
			L([Vector2(x, -32) + Vector2.from_angle(a) * 24, Vector2(x, -32) - Vector2.from_angle(a) * 24])
		col("#f5f0e6")
	# 몸체 (선으로)
	col(c)
	shape([Vector2(-50, -32), Vector2(-14, -80), Vector2(-6, -80), Vector2(-40, -30)])
	shape([Vector2(-14, -80), Vector2(34, -80), Vector2(8, -30), Vector2(0, -34)])
	shape([Vector2(34, -84), Vector2(42, -84), Vector2(54, -32), Vector2(46, -32)])
	col("#3a3a3a")
	rect(-28, -92, 0, -84)                        # 안장
	L([Vector2(38, -84), Vector2(34, -104), Vector2(52, -108)])   # 손잡이


func fence(w: float) -> void:
	var wood := pick(["#f5f0e6", "#e8d8b8", "#d9a86c"])
	col(wood)
	rect(-w / 2, -66, w / 2, -56)
	rect(-w / 2, -30, w / 2, -20)
	var x := -w / 2 + 10
	while x < w / 2 - 20:
		shape([Vector2(x, 0), Vector2(x, -86), Vector2(x + 10, -100), Vector2(x + 20, -86), Vector2(x + 20, 0)])
		x += 52


func pond(w: float) -> void:
	col("#a8dcf0")
	shape(bumpy_pts(Vector2.ZERO, Vector2(w / 2, w * 0.16), 9, 0.06))
	for i in range(rng.randi_range(3, 6)):
		arc(Vector2(R(-w * 0.3, w * 0.3), R(-w * 0.08, w * 0.08)), Vector2(R(18, 34), 5), 190, 350, 6)
	# 연잎
	col("#83b366")
	for i in range(rng.randi_range(2, 4)):
		var c := Vector2(R(-w * 0.3, w * 0.3), R(-w * 0.07, w * 0.07))
		var pts := arc_pts(c, Vector2(22, 11), 20, 340, 10)
		pts.append(c)
		shape(pts)


func picnic_mat(w: float) -> void:
	var c := pick(BRIGHT)
	col(c)
	var pts := [Vector2(-w / 2, 0), Vector2(w / 2 - 30, 10), Vector2(w / 2, -w * 0.22), Vector2(-w / 2 + 40, -w * 0.26)]
	shape(pts)
	# 격자 무늬
	for k in range(1, 4):
		var t := k / 4.0
		L([pts[0].lerp(pts[1], t), pts[3].lerp(pts[2], t)])
		L([pts[0].lerp(pts[3], t), pts[1].lerp(pts[2], t)])
	# 접시와 샌드위치
	col(PAPER)
	ellipse(Vector2(-w * 0.1, -w * 0.1), Vector2(26, 10))
	col("#f3d9a4")
	shape([Vector2(-w * 0.1 - 14, -w * 0.1 - 2), Vector2(-w * 0.1 + 14, -w * 0.1 - 2), Vector2(-w * 0.1, -w * 0.1 - 18)])


func flower_patch() -> void:
	for i in range(rng.randi_range(2, 4)):
		var base := Vector2(R(-40, 40), R(-6, 6))
		var top := base + Vector2(R(-10, 10), -R(34, 60))
		L([base, top])
		col(pick(GREEN))
		shape([base.lerp(top, 0.3), base.lerp(top, 0.3) + Vector2(16, -10), base.lerp(top, 0.3) + Vector2(22, -2)])
		col(pick(["#ffadad", "#ffd166", "#ffc6ff", "#ffffff", "#a0c4ff", "#f28482"]))
		shape(bumpy_pts(top, Vector2(11, 11), 5, 0.4))
		col("#ffd166")
		ellipse(top, Vector2(4, 4), true, 6)


func rock(r: float) -> void:
	col(pick(["#c9c4b8", "#b8b2a7", "#d6d1c4"]))
	var pts := []
	var n := rng.randi_range(6, 8)
	for k in range(n):
		var a := TAU * k / n
		pts.append(Vector2(cos(a) * r * R(0.8, 1.1), -r * 0.55 + sin(a) * r * 0.6 * R(0.8, 1.1)))
	shape(pts)
	L([Vector2(-r * 0.3, -r * 0.8), Vector2(0, -r * 0.55), Vector2(r * 0.15, -r * 0.3)])


func grass_tuft() -> void:
	col(pick(GREEN))
	for i in range(rng.randi_range(3, 5)):
		var x := R(-24, 24)
		shape([Vector2(x - 5, 0), Vector2(x + 5, 0), Vector2(x + R(-12, 12), -R(22, 40))])



# ═══════════════ 우주 낙서 (흑백 선 그림) ═══════════════
# 색칠 책 같은 흑백 낙서 그림. 모든 모양을 종이색으로 칠해서 선만 보이게 한다.
# 이 묶음의 소품은 가운데가 (0, 0)이다 (바닥에 서 있는 것이 아니라 떠 있는 것이라서).
# 숨길 물건과 겹치는 모양(다섯 꼭짓점 별, 초승달)은 쓰지 않는다.

const BG := Color("#fdfcf7")   # 종이색 (HiddenWorld의 바탕색과 같다)


# 고리가 있는 행성
func planet_ring(r: float) -> void:
	col(BG)
	arc(Vector2.ZERO, Vector2(r * 1.7, r * 0.45), 180, 360, 16)   # 뒤쪽 고리
	ellipse(Vector2.ZERO, Vector2(r, r))
	arc(Vector2.ZERO, Vector2(r * 1.7, r * 0.45), 0, 180, 16)     # 앞쪽 고리 (두 줄)
	arc(Vector2.ZERO, Vector2(r * 1.45, r * 0.32), 8, 172, 14)
	for k in range(3):
		arc(Vector2(0, -r * 0.55 + k * r * 0.3), Vector2(r * 0.75, r * 0.14), 200, 340, 8)


# 구덩이가 있는 행성
func planet_crater(r: float) -> void:
	col(BG)
	ellipse(Vector2.ZERO, Vector2(r, r))
	for k in range(rng.randi_range(4, 7)):
		var p := Vector2.from_angle(R(0, TAU)) * R(0, r * 0.7)
		var cr := R(r * 0.08, r * 0.2)
		ellipse(p, Vector2(cr, cr * 0.8), false, 8)
	for k in range(rng.randi_range(6, 12)):
		dot(Vector2.from_angle(R(0, TAU)) * R(0, r * 0.85), 1.8)
	# 작은 깃발 같은 탑
	if chance(0.4):
		L([Vector2(0, -r), Vector2(0, -r - 26)])
		ellipse(Vector2(0, -r - 30), Vector2(5, 5), true, 6)


# 빗금 무늬 행성
func planet_hatch(r: float) -> void:
	col(BG)
	ellipse(Vector2.ZERO, Vector2(r, r))
	var x := -r + 8.0
	while x < r:
		var half := sqrt(maxf(r * r - x * x, 0.0)) * 0.92
		L([Vector2(x, -half), Vector2(x, half)])
		x += 9.0


# 소용돌이 해
func sun_swirl(r: float) -> void:
	col(BG)
	for i in range(18):
		var a := TAU * i / 18.0
		var d := Vector2.from_angle(a)
		L([d * (r + 6), d * (r + 14) + d.orthogonal() * 4, d * (r + 22)])
	ellipse(Vector2.ZERO, Vector2(r, r))
	var spiral := []
	for k in range(30):
		var a := k * 0.5
		spiral.append(Vector2(cos(a), sin(a)) * (3.0 + k * r * 0.027))
	L(spiral)


# 로켓 (위쪽을 향함)
func rocket(h: float) -> void:
	var w := h * 0.32
	col(BG)
	# 날개
	shape([Vector2(-w / 2, h * 0.1), Vector2(-w, h * 0.42), Vector2(-w / 2, h * 0.34)])
	shape([Vector2(w / 2, h * 0.1), Vector2(w, h * 0.42), Vector2(w / 2, h * 0.34)])
	# 몸통
	shape([Vector2(0, -h * 0.5), Vector2(w * 0.38, -h * 0.3), Vector2(w / 2, -h * 0.05), Vector2(w / 2, h * 0.34),
			Vector2(-w / 2, h * 0.34), Vector2(-w / 2, -h * 0.05), Vector2(-w * 0.38, -h * 0.3)])
	L([Vector2(-w * 0.4, -h * 0.28), Vector2(w * 0.4, -h * 0.28)])
	L([Vector2(-w / 2, h * 0.24), Vector2(w / 2, h * 0.24)])
	ellipse(Vector2(0, -h * 0.08), Vector2(w * 0.24, w * 0.24), true, 10)
	ellipse(Vector2(0, -h * 0.08), Vector2(w * 0.13, w * 0.13), false, 8)
	# 불꽃
	shape([Vector2(-w * 0.34, h * 0.34), Vector2(-w * 0.2, h * 0.5), Vector2(-w * 0.08, h * 0.42), Vector2(0, h * 0.58),
			Vector2(w * 0.08, h * 0.42), Vector2(w * 0.2, h * 0.5), Vector2(w * 0.34, h * 0.34)])


# 꼬리 달린 별똥별 (오른쪽 위로 날아감)
func comet(r: float) -> void:
	col(BG)
	for k in range(4):
		var off := (k - 1.5) * r * 0.5
		L([Vector2(-r * 0.6, off), Vector2(-r * R(2.6, 4.0), off * 1.6)])
	ellipse(Vector2.ZERO, Vector2(r, r * 0.9), true, 12)
	ellipse(Vector2(r * 0.2, -r * 0.2), Vector2(r * 0.25, r * 0.2), false, 6)
	dot(Vector2(-r * 0.3, r * 0.3), 1.8)


func ufo(w: float) -> void:
	col(BG)
	shape(arc_pts(Vector2(0, -w * 0.08), Vector2(w * 0.24, w * 0.26), 180, 360, 10))
	ellipse(Vector2.ZERO, Vector2(w / 2, w * 0.14), true, 16)
	for k in range(-2, 3):
		ellipse(Vector2(k * w * 0.17, w * 0.02), Vector2(w * 0.035, w * 0.035), false, 6)
	L([Vector2(-w * 0.2, w * 0.13), Vector2(-w * 0.28, w * 0.3)])
	L([Vector2(w * 0.2, w * 0.13), Vector2(w * 0.28, w * 0.3)])
	L([Vector2(0, -w * 0.34), Vector2(0, -w * 0.44)])
	ellipse(Vector2(0, -w * 0.47), Vector2(4, 4), true, 6)


# 인공위성: 몸통과 양쪽의 격자 날개
func satellite(w: float) -> void:
	col(BG)
	for side in [-1.0, 1.0]:
		var x0: float = side * w * 0.14
		var x1: float = side * w * 0.5
		rect(minf(x0, x1), -w * 0.1, maxf(x0, x1), w * 0.1)
		for k in range(1, 4):
			var x := lerpf(x0, x1, k / 4.0)
			L([Vector2(x, -w * 0.1), Vector2(x, w * 0.1)])
		L([Vector2(x0, 0), Vector2(x1, 0)])
	rect(-w * 0.14, -w * 0.14, w * 0.14, w * 0.14)
	L([Vector2(0, -w * 0.14), Vector2(0, -w * 0.3)])
	arc(Vector2(0, -w * 0.36), Vector2(w * 0.1, w * 0.06), 0, 180, 6)


# 별자리: 작은 동그라미를 선으로 이은 것
func constellation(spread: float) -> void:
	col(BG)
	var pts := []
	var p := Vector2(-spread * 0.5, R(-spread * 0.3, spread * 0.3))
	for i in range(rng.randi_range(3, 5)):
		pts.append(p)
		p += Vector2(R(spread * 0.25, spread * 0.45), R(-spread * 0.4, spread * 0.4))
	for i in range(pts.size() - 1):
		var d: Vector2 = (pts[i + 1] - pts[i]).normalized()
		L([pts[i] + d * 7, pts[i + 1] - d * 7])
	for q in pts:
		ellipse(q, Vector2(5, 5), true, 8)


# 네 갈래 반짝이
func sparkle(r: float) -> void:
	col(BG)
	var pts := []
	for i in range(8):
		var a := TAU * i / 8.0
		pts.append(Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.28))
	shape(pts)


# 선 세 개가 엇갈린 작은 별
func asterisk(r: float) -> void:
	for i in range(3):
		var d := Vector2.from_angle(PI * i / 3.0) * r
		L([-d, d])


# 열기구
func air_balloon(r: float) -> void:
	col(BG)
	L([Vector2(-r * 0.5, r * 0.85), Vector2(-r * 0.2, r * 1.5)])
	L([Vector2(r * 0.5, r * 0.85), Vector2(r * 0.2, r * 1.5)])
	rect(-r * 0.24, r * 1.5, r * 0.24, r * 1.85)
	ellipse(Vector2.ZERO, Vector2(r * 0.85, r), true, 16)
	for k in [0.3, 0.6]:
		arc(Vector2.ZERO, Vector2(r * 0.85 * k, r), 90, 270, 10)
		arc(Vector2.ZERO, Vector2(r * 0.85 * k, r), -90, 90, 10)
	L([Vector2(0, -r), Vector2(0, r)])


# 우주인 (둥둥 떠 있음)
func astronaut() -> void:
	col(BG)
	# 등에 멘 산소통
	rect(-34, -34, 34, 30)
	# 팔다리 (두꺼운 네모를 벌린 모양)
	shape([Vector2(-24, -18), Vector2(-62, -44), Vector2(-72, -30), Vector2(-28, 2)])
	shape([Vector2(24, -18), Vector2(64, -6), Vector2(60, 12), Vector2(26, 4)])
	shape([Vector2(-22, 26), Vector2(-40, 74), Vector2(-20, 80), Vector2(-4, 34)])
	shape([Vector2(22, 26), Vector2(44, 66), Vector2(26, 78), Vector2(4, 34)])
	# 장갑과 신발
	ellipse(Vector2(-70, -40), Vector2(10, 10), true, 8)
	ellipse(Vector2(66, 4), Vector2(10, 10), true, 8)
	ellipse(Vector2(-32, 82), Vector2(14, 8), true, 8)
	ellipse(Vector2(38, 78), Vector2(14, 8), true, 8)
	# 몸통과 가슴의 단추 상자
	shape([Vector2(-26, -30), Vector2(26, -30), Vector2(28, 34), Vector2(-28, 34)])
	rect(-14, -10, 14, 12)
	dot(Vector2(-6, 0), 2.5)
	dot(Vector2(6, 0), 2.5)
	L([Vector2(-10, 7), Vector2(10, 7)])
	# 헬멧과 얼굴
	ellipse(Vector2(0, -58), Vector2(34, 32))
	ellipse(Vector2(0, -56), Vector2(24, 21))
	dot(Vector2(-8, -60), 2.5)
	dot(Vector2(8, -60), 2.5)
	arc(Vector2(0, -52), Vector2(8, 6), 20, 160, 6)
	L([Vector2(0, -90), Vector2(0, -102)])
	ellipse(Vector2(0, -105), Vector2(4, 4), true, 6)


# 큰 행성 (화면 아래쪽에 일부만 보임): 땅 덩어리, 구름 무늬
func big_planet(r: float) -> void:
	col(BG)
	ellipse(Vector2.ZERO, Vector2(r, r), true, 60)
	# 땅 덩어리 (위쪽 보이는 부분에만)
	for k in range(rng.randi_range(9, 13)):
		var a := deg_to_rad(R(-140, -40))
		var c := Vector2.from_angle(a) * R(r * 0.3, r * 0.84)
		shape(bumpy_pts(c, Vector2(R(40, 110), R(22, 50)), rng.randi_range(5, 8), 0.3), false)
	# 구름 같은 물결 줄
	for k in range(rng.randi_range(24, 34)):
		var a := deg_to_rad(R(-150, -30))
		var c := Vector2.from_angle(a) * R(r * 0.25, r * 0.93)
		arc(c, Vector2(R(14, 30), R(6, 12)), 190, 350, 5)
	for k in range(30):
		var a := deg_to_rad(R(-150, -30))
		ellipse(Vector2.from_angle(a) * R(r * 0.25, r * 0.92), Vector2(R(5, 10), R(4, 7)), false, 6)


# 행성 가장자리에 서 있는 작은 나무 (바닥 가운데가 (0, 0), 위쪽이 바깥)
func tiny_tree(h: float) -> void:
	col(BG)
	L([Vector2(0, 0), Vector2(0, -h * 0.5)])
	L([Vector2(0, -h * 0.3), Vector2(h * 0.14, -h * 0.42)])
	shape(bumpy_pts(Vector2(0, -h * 0.7), Vector2(h * 0.26, h * 0.3), 6, 0.25))


# 행성 위의 작은 건물들
func tiny_city(h: float) -> void:
	col(BG)
	for k in range(3):
		var x := (k - 1) * h * 0.3
		var bh := h * R(0.5, 1.0)
		rect(x - h * 0.13, -bh, x + h * 0.13, 4)
		var y := -bh + 8
		while y < -6:
			L([Vector2(x - h * 0.07, y), Vector2(x - h * 0.02, y)])
			L([Vector2(x + h * 0.03, y), Vector2(x + h * 0.08, y)])
			y += 10
	L([Vector2(0, -h), Vector2(0, -h - 14)])
