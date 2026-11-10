# 숨은그림 장면에 들어가는 소품(사람, 동물, 가구, 책, 잡동사니)을 선 그림으로 그리는 도구.
# 소품 하나 = "채우기 모양(종이 흰색, 뒤에 있는 것을 가림)" + "선" 목록.
# 좌표는 소품의 바닥 가운데가 (0, 0)이고 위쪽이 음수 y. begin()으로 위치·크기·뒤집기를 정하고 그린다.
#
# 숨길 물건(HiddenShapes)과 똑같은 모양의 소품은 넣지 않는다 (예: 컵, 연필, 우산, 열쇠, 안경, 모자, 별, 하트).
# 그래야 찾을 물건이 그림 안에 하나뿐이다.
class_name HiddenProps
extends RefCounted

var rng: RandomNumberGenerator
var fills := []      # 지금 그리는 소품의 채우기 모양들 (그림 좌표)
var strokes := []    # 지금 그리는 소품의 선들 (그림 좌표)
var _xf := Transform2D.IDENTITY   # 소품 좌표 → 그림 좌표 변환
var _stack := []                  # push/pop용 (탁자 위에 물건을 올릴 때)


func _init(r: RandomNumberGenerator) -> void:
	rng = r


# 새 소품 시작. origin = 바닥 가운데 위치, s = 크기 배율, flip = 좌우 뒤집기
func begin(origin: Vector2, s: float, flip: bool = false) -> void:
	fills = []
	strokes = []
	_stack = []
	# Transform2D(회전, 배율, 기울임, 위치)
	_xf = Transform2D(0.0, Vector2(-s if flip else s, s), 0.0, origin)


func end() -> Dictionary:
	return {"fills": fills, "strokes": strokes}


# 지금 좌표계 안에서 (offset) 위치로 옮기고 s배로 줄여 그린다. 끝나면 pop()
func push(offset: Vector2, s: float) -> void:
	_stack.append(_xf)
	_xf = _xf * Transform2D(0.0, Vector2(s, s), 0.0, offset)


func pop() -> void:
	_xf = _stack.pop_back()


# ─── 그리기 기본 ───

func L(points: Array) -> void:
	strokes.append(_xf * PackedVector2Array(points))


func F(points: Array) -> void:
	fills.append(_xf * PackedVector2Array(points))


# 닫힌 모양: 채우기 + 테두리 선
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


func dot(c: Vector2, r: float = 2.5) -> void:
	ellipse(c, Vector2(r, r), true, 6)


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
	rect(-w / 2, -h, w / 2, 0)
	rect(-w / 2 + 10, -h + 10, w / 2 - 10, -10, false)
	L([Vector2(0, -h + 10), Vector2(0, -10)])
	L([Vector2(-w / 2 + 10, -h / 2), Vector2(w / 2 - 10, -h / 2)])
	# 바깥 풍경: 구름과 나무 꼭대기
	L(bumpy_pts(Vector2(-w * 0.2, -h * 0.75), Vector2(w * 0.12, h * 0.06), 5, 0.3))
	arc(Vector2(w * 0.25, -h * 0.15), Vector2(w * 0.15, h * 0.15), 180, 360, 10)
	# 커튼 (물결 모양 양쪽)
	for side in [-1.0, 1.0]:
		var pts := [Vector2(side * w / 2, -h - 8)]
		for i in range(7):
			pts.append(Vector2(side * (w / 2 - 14 - (i % 2) * 8 - i * 3), -h + i * h / 6))
		pts.append(Vector2(side * (w / 2 + 6), 0))
		pts.append(Vector2(side * (w / 2 + 6), -h - 8))
		shape(pts)
		for i in range(3):
			L([Vector2(side * (w / 2 - 4 - i * 6), -h + 10), Vector2(side * (w / 2 - 6 - i * 8), -10)])
	L([Vector2(-w / 2 - 20, -h - 10), Vector2(w / 2 + 20, -h - 10)])


func clock(r: float) -> void:
	ellipse(Vector2(0, -r), Vector2(r, r))
	ellipse(Vector2(0, -r), Vector2(r * 0.85, r * 0.85), false)
	for i in range(12):
		var a := TAU * i / 12.0
		L([Vector2(0, -r) + Vector2.from_angle(a) * r * 0.72, Vector2(0, -r) + Vector2.from_angle(a) * r * 0.82])
	L([Vector2(0, -r), Vector2(0, -r) + Vector2.from_angle(R(0, TAU)) * r * 0.55])
	L([Vector2(0, -r), Vector2(0, -r) + Vector2.from_angle(R(0, TAU)) * r * 0.4])


func frame(w: float, h: float) -> void:
	rect(-w / 2, -h, w / 2, 0)
	rect(-w / 2 + 8, -h + 8, w / 2 - 8, -8, false)
	# 안의 그림: 산과 해, 또는 꽃병
	if chance(0.5):
		L([Vector2(-w / 2 + 8, -20), Vector2(-w * 0.1, -h * 0.6), Vector2(w * 0.1, -h * 0.35), Vector2(w * 0.25, -h * 0.55), Vector2(w / 2 - 8, -22)])
		ellipse(Vector2(-w * 0.25, -h * 0.72), Vector2(9, 9), false)
	else:
		shape([Vector2(-w * 0.12, -12), Vector2(w * 0.12, -12), Vector2(w * 0.16, -h * 0.35), Vector2(-w * 0.16, -h * 0.35)])
		for i in range(3):
			var c := Vector2(-w * 0.15 + i * w * 0.15, -h * 0.55 - (i % 2) * 10)
			shape(bumpy_pts(c, Vector2(10, 10), 5, 0.3), false)
	L([Vector2(-w * 0.2, -h), Vector2(0, -h - 22), Vector2(w * 0.2, -h)])


func board(w: float, h: float) -> void:
	rect(-w / 2, -h, w / 2, 0)
	rect(-w / 2 + 8, -h + 8, w / 2 - 8, -8, false)
	for i in range(rng.randi_range(4, 7)):
		var c := Vector2(R(-w / 2 + 35, w / 2 - 35), R(-h + 35, -35))
		var nw := R(36, 56)
		var nh := R(30, 50)
		push(c, 1.0)
		var rot := R(-0.25, 0.25)
		var pts := []
		for p in [Vector2(-nw / 2, -nh / 2), Vector2(nw / 2, -nh / 2), Vector2(nw / 2, nh / 2), Vector2(-nw / 2, nh / 2)]:
			pts.append(p.rotated(rot))
		shape(pts)
		for k in range(2):
			L([(Vector2(-nw / 2 + 6, -nh / 2 + 12 + k * 10)).rotated(rot), (Vector2(nw / 2 - 6, -nh / 2 + 12 + k * 10)).rotated(rot)])
		dot(Vector2(0, -nh / 2 + 4).rotated(rot), 3)
		pop()


func bunting(w: float) -> void:
	# 양 끝이 높고 가운데가 처진 줄 + 줄에 매달린 세모 깃발
	var pts := arc_pts(Vector2(0, -60), Vector2(w / 2, 40), 180, 0, 12)
	L(pts)
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		shape([a, b, a.lerp(b, 0.5) + Vector2(0, 34)])


# ═══════════════ 가구 ═══════════════

func bookshelf(w: float, h: float) -> void:
	rect(-w / 2, -h, w / 2, 0)
	var shelves := rng.randi_range(3, 4)
	var sh := (h - 20) / shelves
	for k in range(shelves):
		var y_bottom := -10 - k * sh
		L([Vector2(-w / 2, y_bottom), Vector2(w / 2, y_bottom)])
		var x := -w / 2 + 8
		while x < w / 2 - 20:
			var bw := R(12, 26)
			var bh := sh * R(0.55, 0.9)
			if chance(0.1):
				x += R(10, 30)   # 빈칸
				continue
			if chance(0.12) and x + bh < w / 2 - 8:
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
	L([Vector2(-w / 2 - 6, -h), Vector2(w / 2 + 6, -h)])


func table(w: float, h: float, items: bool = true) -> void:
	# 다리
	for x in [-w / 2 + 12, w / 2 - 22]:
		rect(x, -h, x + 10, 0)
	var d := 34.0
	shape([Vector2(-w / 2, -h), Vector2(w / 2, -h), Vector2(w / 2 - 22, -h - d), Vector2(-w / 2 + 22, -h - d)])
	rect(-w / 2, -h, w / 2, -h + 12)
	if items:
		var n := rng.randi_range(1, 3)
		for i in range(n):
			var x := lerpf(-w / 2 + 40, w / 2 - 40, (i + 0.5) / n) + R(-10, 10)
			push(Vector2(x, -h - d * 0.4), 0.55)
			match rng.randi_range(0, 4):
				0: book_stack()
				1: globe()
				2: plant(true)
				3: open_book_flat()
				_: basket()
			pop()


func desk(w: float, h: float) -> void:
	rect(-w / 2, -h, w / 2, 0)
	rect(w * 0.05, -h + 14, w / 2 - 10, -10, false)
	for k in range(3):
		var y := -h + 14 + k * (h - 24) / 3.0
		L([Vector2(w * 0.05, y), Vector2(w / 2 - 10, y)])
		dot(Vector2(w * 0.27, y + (h - 24) / 6.0), 3)
	var d := 30.0
	shape([Vector2(-w / 2, -h), Vector2(w / 2, -h), Vector2(w / 2 - 18, -h - d), Vector2(-w / 2 + 18, -h - d)])
	push(Vector2(-w * 0.2, -h - d * 0.4), 0.5)
	if chance(0.5):
		book_stack()
	else:
		lamp_small()
	pop()


func chair(h: float) -> void:
	var w := h * 0.42
	for x in [-w / 2, w / 2 - 6]:
		rect(x, -h * 0.48, x + 6, 0)
	shape([Vector2(-w / 2, -h * 0.48), Vector2(w / 2, -h * 0.48), Vector2(w / 2 - 10, -h * 0.56), Vector2(-w / 2 + 10, -h * 0.56)])
	rect(-w / 2 + 6, -h, w / 2 - 6, -h * 0.56)
	for k in range(3):
		var x := lerpf(-w / 2 + 14, w / 2 - 14, k / 2.0)
		L([Vector2(x, -h + 10), Vector2(x, -h * 0.6)])


func stool(h: float) -> void:
	var w := h * 0.55
	L([Vector2(-w * 0.35, -h * 0.9), Vector2(-w * 0.5, 0)])
	L([Vector2(w * 0.35, -h * 0.9), Vector2(w * 0.5, 0)])
	L([Vector2(0, -h * 0.9), Vector2(0, -6)])
	L([Vector2(-w * 0.42, -h * 0.4), Vector2(w * 0.42, -h * 0.4)])
	ellipse(Vector2(0, -h * 0.92), Vector2(w / 2, w * 0.16))


func floor_lamp(h: float) -> void:
	ellipse(Vector2(0, -6), Vector2(30, 8))
	rect(-3, -h * 0.75, 3, -6)
	shape([Vector2(-h * 0.13, -h * 0.72), Vector2(h * 0.13, -h * 0.72), Vector2(h * 0.08, -h), Vector2(-h * 0.08, -h)])
	L([Vector2(h * 0.06, -h * 0.72), Vector2(h * 0.06, -h * 0.6)])
	dot(Vector2(h * 0.06, -h * 0.58), 3)


func lamp_small() -> void:
	ellipse(Vector2(0, -6), Vector2(26, 8))
	L([Vector2(0, -6), Vector2(-20, -60), Vector2(10, -100)])
	shape([Vector2(0, -95), Vector2(40, -110), Vector2(30, -75)])


func plant(small: bool = false) -> void:
	var s := 0.7 if small else 1.0
	shape([Vector2(-34 * s, -60 * s), Vector2(34 * s, -60 * s), Vector2(26 * s, 0), Vector2(-26 * s, 0)])
	rect(-38 * s, -72 * s, 38 * s, -60 * s)
	var n := rng.randi_range(5, 8)
	for i in range(n):
		var a := deg_to_rad(lerpf(-160, -20, float(i) / (n - 1)) + R(-8, 8))
		var l := R(60, 110) * s
		var base := Vector2(0, -72 * s)
		var tip := base + Vector2.from_angle(a) * l
		var mid := base.lerp(tip, 0.5)
		var nrm := (tip - base).orthogonal().normalized() * l * 0.18
		shape([base, mid + nrm, tip, mid - nrm])
		L([base, tip.lerp(base, 0.15)])


func box(w: float, h: float) -> void:
	var d := w * 0.3
	rect(-w / 2, -h, w / 2, 0)
	shape([Vector2(-w / 2, -h), Vector2(w / 2, -h), Vector2(w / 2 + d * 0.6, -h - d * 0.5), Vector2(-w / 2 + d * 0.6, -h - d * 0.5)])
	shape([Vector2(w / 2, -h), Vector2(w / 2 + d * 0.6, -h - d * 0.5), Vector2(w / 2 + d * 0.6, -d * 0.5), Vector2(w / 2, 0)])
	L([Vector2(-w / 2 + d * 0.3 + w / 2, -h - d * 0.25), Vector2(d * 0.3, -h - d * 0.25)])
	L([Vector2(0, -h), Vector2(0, -h * 0.6)])
	if chance(0.4):
		# 상자 위로 책이 삐져나옴
		for i in range(2):
			var x := R(-w / 2 + 10, w / 2 - 30)
			shape([Vector2(x, -h - 2), Vector2(x + 18, -h - 2), Vector2(x + 28, -h - R(30, 50)), Vector2(x + 10, -h - R(30, 50))])
	else:
		L([Vector2(-w * 0.3, -h * 0.5), Vector2(w * 0.2, -h * 0.5)])
		L([Vector2(-w * 0.3, -h * 0.4), Vector2(w * 0.1, -h * 0.4)])


func book_stack() -> void:
	var y := 0.0
	for i in range(rng.randi_range(3, 6)):
		var bw := R(70, 100)
		var bh := R(12, 20)
		var off := R(-10, 10)
		rect(-bw / 2 + off, y - bh, bw / 2 + off, y)
		L([Vector2(bw / 2 + off - 8, y - bh + 4), Vector2(bw / 2 + off - 8, y - 4)])
		y -= bh


func open_book_flat() -> void:
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
		pts.append(Vector2(p.x, p.y * 0.45).rotated(rot * 0.3) + Vector2(0, -h * 0.25))
	shape(pts)
	L([pts[0].lerp(pts[3], 0.0) + (pts[1] - pts[0]) * 0.12, pts[3] + (pts[2] - pts[3]) * 0.12])


func paper(w: float) -> void:
	var rot := R(-0.8, 0.8)
	var pts := []
	for p in [Vector2(-w / 2, -w * 0.35), Vector2(w / 2, -w * 0.35), Vector2(w / 2, w * 0.35), Vector2(-w / 2, w * 0.35)]:
		var q: Vector2 = p.rotated(rot)
		pts.append(Vector2(q.x, q.y * 0.5))
	shape(pts)
	for k in range(3):
		var t := 0.25 + k * 0.22
		L([pts[0].lerp(pts[3], t) + (pts[1] - pts[0]) * 0.15, pts[1].lerp(pts[2], t) - (pts[1] - pts[0]) * 0.15])


func rug(w: float) -> void:
	ellipse(Vector2(0, 0), Vector2(w / 2, w * 0.13), true, 28)
	ellipse(Vector2(0, 0), Vector2(w * 0.4, w * 0.1), false, 24)
	ellipse(Vector2(0, 0), Vector2(w * 0.25, w * 0.06), false, 20)
	for i in range(16):
		var a := TAU * i / 16.0
		var p := Vector2(cos(a) * w / 2, sin(a) * w * 0.13)
		L([p, p * 1.07])


func ball(r: float) -> void:
	ellipse(Vector2(0, -r), Vector2(r, r))
	arc(Vector2(-r * 0.9, -r), Vector2(r * 0.6, r), -60, 60, 8)
	arc(Vector2(r * 0.9, -r), Vector2(r * 0.6, r), 120, 240, 8)


func blocks() -> void:
	# 장난감 쌓기 블록 (글자 대신 줄무늬)
	for i in range(rng.randi_range(2, 4)):
		var x := R(-40, 40)
		var y := -i * 30.0
		rect(x - 15, y - 30, x + 15, y)
		shape([Vector2(x - 15, y - 30), Vector2(x + 15, y - 30), Vector2(x + 22, y - 36), Vector2(x - 8, y - 36)])
		L([Vector2(x - 8, y - 20), Vector2(x + 8, y - 10)])


func backpack(h: float) -> void:
	var w := h * 0.7
	var pts := arc_pts(Vector2(0, -h + w / 2), Vector2(w / 2, w / 2), 180, 360, 10)
	pts.append(Vector2(w / 2, -6))
	pts.append(Vector2(-w / 2, -6))
	shape(pts)
	rect(-w * 0.35, -h * 0.42, w * 0.35, -10)
	L([Vector2(-w * 0.3, -h * 0.3), Vector2(w * 0.3, -h * 0.3)])
	arc(Vector2(0, -h), Vector2(w * 0.18, 14), 180, 360, 8)
	L([Vector2(-w / 2 + 6, -h * 0.7), Vector2(-w / 2 - 6, -h * 0.25)])


func globe() -> void:
	ellipse(Vector2(0, -12), Vector2(36, 8))
	L([Vector2(0, -12), Vector2(0, -40)])
	arc(Vector2(0, -90), Vector2(56, 56), 30, 150, 10)
	ellipse(Vector2(0, -90), Vector2(46, 46))
	arc(Vector2(0, -90), Vector2(20, 46), -90, 90, 10)
	L([Vector2(-46, -90), Vector2(46, -90)])
	var blob := bumpy_pts(Vector2(-14, -100), Vector2(16, 12), 5, 0.35)
	blob.append(blob[0])
	L(blob)


func basket() -> void:
	shape([Vector2(-50, -50), Vector2(50, -50), Vector2(38, 0), Vector2(-38, 0)])
	for k in range(1, 4):
		var y := -50 + k * 12.5
		L([Vector2(-50 + k * 3, y), Vector2(50 - k * 3, y)])
	for k in range(-3, 4):
		L([Vector2(k * 13, -50), Vector2(k * 10, 0)])
	arc(Vector2(0, -50), Vector2(42, 40), 180, 360, 12)


func bin() -> void:
	shape([Vector2(-34, -80), Vector2(34, -80), Vector2(26, 0), Vector2(-26, 0)])
	for k in range(-2, 3):
		L([Vector2(k * 12, -76), Vector2(k * 9, -4)])
	for i in range(rng.randi_range(1, 3)):
		var c := Vector2(R(-20, 20), -86 - i * 6)
		shape(bumpy_pts(c, Vector2(14, 11), 6, 0.3))
		L([c + Vector2(-6, -2), c + Vector2(4, 3)])


# ═══════════════ 사람과 동물 ═══════════════

# 서 있는 아이. 머리 모양·옷 무늬·팔 자세가 무작위로 달라진다.
func kid() -> void:
	var skirt := chance(0.4)
	# 다리와 신발
	if skirt:
		L([Vector2(-12, -60), Vector2(-14, -6)])
		L([Vector2(12, -60), Vector2(14, -6)])
	else:
		rect(-24, -92, -3, -6)
		rect(3, -92, 24, -6)
	ellipse(Vector2(-16, -5), Vector2(14, 7))
	ellipse(Vector2(16, -5), Vector2(14, 7))
	# 몸통
	if skirt:
		shape([Vector2(-26, -150), Vector2(26, -150), Vector2(42, -56), Vector2(-42, -56)])
	else:
		shape([Vector2(-28, -158), Vector2(28, -158), Vector2(30, -88), Vector2(-30, -88)])
	match rng.randi_range(0, 3):
		0:
			for k in range(3):
				L([Vector2(-27, -140 + k * 16), Vector2(27, -140 + k * 16)])
		1:
			for k in range(5):
				dot(Vector2(R(-18, 18), R(-145, -100)), 3)
		2:
			rect(6, -140, 20, -124, false)
		_:
			L([Vector2(0, -158), Vector2(0, -92)])
			for k in range(3):
				dot(Vector2(-5, -146 + k * 18), 2.5)
	# 팔
	var pose := rng.randi_range(0, 3)
	for side in [-1.0, 1.0]:
		var sh := Vector2(side * 28, -152)
		var hand: Vector2
		match pose:
			0: hand = Vector2(side * 44, -96)                     # 내림
			1: hand = Vector2(side * 52, -206) if side > 0 else Vector2(-44, -96)  # 한 손 들기
			2: hand = Vector2(side * 14, -118)                    # 앞으로 (책 들기)
			_: hand = Vector2(side * 60, -150)                    # 벌림
		L([sh, sh.lerp(hand, 0.5) + Vector2(side * 6, 0), hand])
		ellipse(hand, Vector2(7, 7))
	if pose == 2:
		shape([Vector2(-34, -128), Vector2(34, -128), Vector2(30, -96), Vector2(-30, -96)])
		L([Vector2(0, -128), Vector2(0, -96)])
	# 머리
	var hc := Vector2(0, -192)
	ellipse(hc, Vector2(32, 32))
	_hair(hc)
	dot(hc + Vector2(-11, 2), 3)
	dot(hc + Vector2(11, 2), 3)
	arc(hc + Vector2(0, 10), Vector2(9, 6), 20, 160, 6)
	if chance(0.5):
		arc(hc + Vector2(-20, 12), Vector2(5, 3), 0, 360, 6)
		arc(hc + Vector2(20, 12), Vector2(5, 3), 0, 360, 6)


func _hair(hc: Vector2) -> void:
	match rng.randi_range(0, 3):
		0:  # 단발
			shape(arc_pts(hc, Vector2(36, 36), 180, 360, 12) + [hc + Vector2(36, 18), hc + Vector2(24, 4), hc + Vector2(-24, 4), hc + Vector2(-36, 18)])
			L([hc + Vector2(-10, -34), hc + Vector2(-4, -14)])
		1:  # 삐죽 머리
			var pts := []
			for i in range(9):
				var a := deg_to_rad(lerpf(190, 350, i / 8.0))
				var r := 44.0 if i % 2 == 1 else 30.0
				pts.append(hc + Vector2(cos(a), sin(a)) * r)
			L(pts)
		2:  # 묶은 머리
			arc(hc, Vector2(34, 34), 190, 350, 10)
			L([hc + Vector2(-30, -16), hc + Vector2(10, -22), hc + Vector2(30, -14)])
			ellipse(hc + Vector2(40, -16), Vector2(12, 16))
			ellipse(hc + Vector2(-40, -16), Vector2(12, 16))
		_:  # 곱슬
			var pts := bumpy_pts(hc + Vector2(0, -12), Vector2(36, 26), 9, 0.25)
			var top := []
			for p in pts:
				if p.y < hc.y - 4:
					top.append(p)
			L(top)


# 바닥에 앉아 책 읽는 아이
func kid_sitting() -> void:
	# 다리 (앞으로 뻗음)
	rect(-10, -26, 70, -6)
	rect(-10, -48, 64, -28)
	ellipse(Vector2(76, -16), Vector2(8, 12))
	ellipse(Vector2(70, -38), Vector2(8, 12))
	shape([Vector2(-34, -120), Vector2(14, -120), Vector2(20, -20), Vector2(-40, -20)])
	if chance(0.5):
		for k in range(3):
			L([Vector2(-36, -100 + k * 22), Vector2(16, -100 + k * 22)])
	# 책
	shape([Vector2(4, -70), Vector2(40, -86), Vector2(40, -40), Vector2(4, -26)])
	shape([Vector2(4, -70), Vector2(-24, -84), Vector2(-24, -40), Vector2(4, -26)])
	L([Vector2(-30, -110), Vector2(-20, -60)])
	L([Vector2(10, -110), Vector2(30, -66)])
	var hc := Vector2(-10, -152)
	ellipse(hc, Vector2(30, 30))
	_hair(hc)
	arc(hc + Vector2(-10, 4), Vector2(5, 3), 20, 160, 5)
	arc(hc + Vector2(10, 4), Vector2(5, 3), 20, 160, 5)
	arc(hc + Vector2(0, 14), Vector2(6, 4), 20, 160, 5)


func cat() -> void:
	ellipse(Vector2(0, -38), Vector2(30, 36))
	var tail := []
	for i in range(8):
		var t := i / 7.0
		tail.append(Vector2(26 + t * 30, -10 - sin(t * PI) * 40 - t * 20))
	L(tail)
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
	ellipse(Vector2(0, -50), Vector2(52, 28))
	for x in [-34, -18, 20, 36]:
		rect(x - 6, -36, x + 6, 0)
	L([Vector2(50, -60), Vector2(68, -84), Vector2(72, -78)])
	var hc := Vector2(-54, -82)
	ellipse(hc, Vector2(26, 23))
	ellipse(hc + Vector2(-22, 8), Vector2(14, 10))
	dot(hc + Vector2(-34, 6), 4)
	dot(hc + Vector2(-6, -6), 2.5)
	shape([hc + Vector2(8, -16), hc + Vector2(24, -10), hc + Vector2(22, 22), hc + Vector2(10, 18)])
	arc(hc + Vector2(-20, 18), Vector2(8, 5), 20, 160, 5)


func bear() -> void:
	ellipse(Vector2(0, -40), Vector2(34, 38))
	ellipse(Vector2(-26, -8), Vector2(14, 10))
	ellipse(Vector2(26, -8), Vector2(14, 10))
	ellipse(Vector2(0, -36), Vector2(16, 18), false)
	var hc := Vector2(0, -96)
	ellipse(hc + Vector2(-22, -20), Vector2(11, 11))
	ellipse(hc + Vector2(22, -20), Vector2(11, 11))
	ellipse(hc, Vector2(28, 25))
	ellipse(hc + Vector2(0, 8), Vector2(11, 8), false)
	dot(hc + Vector2(0, 4), 3)
	dot(hc + Vector2(-10, -6), 2.5)
	dot(hc + Vector2(10, -6), 2.5)
	L([Vector2(-30, -60), Vector2(-46, -40)])
	L([Vector2(30, -60), Vector2(46, -40)])


func rabbit() -> void:
	ellipse(Vector2(0, -30), Vector2(26, 30))
	var hc := Vector2(0, -74)
	ellipse(hc + Vector2(-9, -40), Vector2(7, 24))
	ellipse(hc + Vector2(9, -40), Vector2(7, 24))
	ellipse(hc, Vector2(20, 18))
	dot(hc + Vector2(-7, -2), 2.5)
	dot(hc + Vector2(7, -2), 2.5)
	L([hc + Vector2(-3, 7), hc + Vector2(0, 9), hc + Vector2(3, 7)])
	ellipse(Vector2(24, -16), Vector2(8, 8))
