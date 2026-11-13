# 숨은그림 찾기 그림 한 장을 만드는 스크립트. (그리기·터치는 하지 않는다)
# 같은 seed와 같은 단계면 언제나 똑같은 그림이 나온다 → 대결할 때 모두 같은 그림을 받는다.
#
# 진짜 숨은그림 찾기(잡지의 숨은그림, 월리를 찾아라)처럼 만드는 방법
# 1) 한 장의 큰 장면(도서관·교실 같은 방)에 여러 가지 그림을 빽빽하게 그린다.
#    뒷벽(창문, 시계, 액자, 게시판, 깃발, 책장) → 바닥의 납작한 것(깔개, 종이, 책) → 서 있는 것(아이들,
#    동물, 책상, 의자, 상자, 화분…)을 뒤에서부터 앞으로 그린다. 각 그림 안쪽은 종이색으로 채워서
#    앞의 그림이 뒤의 그림을 가린다 → 실제 일러스트처럼 겹쳐 보인다. (HiddenProps가 그림을 그림)
# 2) 모든 선은 한 가지 색·한 가지 굵기의 흑백 선이고, 손으로 그린 것처럼 살짝 흔든다.
# 3) 숨길 물건(HiddenShapes)도 같은 색·굵기·흔들림의 선으로, 채우기 없이 윤곽만 그린다.
# 4) 물건마다 자리 후보를 여러 개(크기·기울기·위치) 만들어, 물건 윤곽선이 장면의 선과 얼마나 맞닿는지 잰다.
#    많이 맞닿을수록 장면의 선에 섞여 안 보인다. 단계가 높을수록 잘 숨는 자리를 고른다.
# 5) 쉬운 단계는 물건 안쪽의 장면 선을 지워 모양을 또렷하게, 어려운 단계는 장면 선이 물건을 가로지르게 둔다.
# 6) 찾지 않아도 되는 다른 물건도 숨겨서 헷갈리게 한다.
class_name HiddenPuzzle
extends RefCounted

const CELL := 4.0          # 선이 지나간 자리를 기록하는 칸 크기 (겹침 계산용)
const COARSE := 40.0       # 빽빽함을 세는 큰 칸 크기
const OCC_CELL := 3.0      # 가림 계산 칸 크기
const CANDIDATES := 48     # 물건 하나당 시험해 보는 자리 후보 수

var world_size := Config.HIDDEN_WORLD
var lines: Array = []      # 최종 선들 (PackedVector2Array 목록, 가려진 부분은 이미 지워짐)
var fills: Array = []      # 색칠 모양들 {"poly", "color"} — 뒤에서 앞 순서. 이 순서대로 칠하면 앞 그림이 뒤를 덮는다
# 찾을 물건: {"shape", "name", "pos", "size", "rot", "flip", "strokes"(그림 좌표 선 목록), "found"}
var targets := []

var _rng := RandomNumberGenerator.new()
var _props: HiddenProps
var _layers := []          # 뒤에서 앞으로 그리는 순서의 그림들 {"fills", "strokes"}
var _wall_h := 0.0         # 벽과 바닥의 경계 y
var _occ := PackedByteArray()       # 칸마다 선이 지나갔는지 (조금 넓혀 둠)
var _dense := PackedInt32Array()    # 큰 칸마다 선이 지나간 양
var _gw := 0
var _gh := 0
var _cw := 0
var _ch := 0


static func stage_settings(stage: int) -> Dictionary:
	return Config.HIDDEN_STAGES[clampi(stage, 0, Config.HIDDEN_STAGES.size() - 1)]


static func make(seed_value: int, stage: int) -> HiddenPuzzle:
	var p := HiddenPuzzle.new()
	p._build(seed_value, stage_settings(stage))
	return p


func _build(seed_value: int, s: Dictionary) -> void:
	_rng.seed = seed_value
	_props = HiddenProps.new(_rng)

	# 1) 장면 그리기 (뒤에서 앞으로)
	_room()
	_wall_items()
	_floor_items(int(s["props"]), int(s["clutter"]))
	# 2) 가려진 선 지우기 → 최종 선
	_flatten()
	_index()

	# 3) 숨길 물건 고르기: 찾을 물건 + 헷갈리게 하는 다른 물건
	var ids := HiddenShapes.ids()
	_shuffle(ids)
	var target_ids := ids.slice(0, s["targets"])
	var extra_ids := ids.slice(s["targets"], s["targets"] + s["extras"])
	var placed := []
	# 다른 물건부터 숨기고, 그 선도 장면에 넣어 찾을 물건이 거기에도 섞이게 한다
	for id in extra_ids:
		placed.append(_place(id, s, placed))
	for item in placed:
		lines.append_array(item["strokes"])
	_index()
	var target_start := placed.size()
	for id in target_ids:
		placed.append(_place(id, s, placed))

	# 4) 쉬운 단계: 물건 안쪽 장면 선 지우기 (물건 선은 따로 있어서 안 지워진다)
	for item in placed:
		if _rng.randf() < float(s["clear"]):
			_clear_circle(item["pos"], item["size"] * 0.34)

	for k in range(target_start, placed.size()):
		var item: Dictionary = placed[k]
		targets.append({
			"shape": item["id"], "name": HiddenShapes.all()[item["id"]]["name"],
			"pos": item["pos"], "size": item["size"], "rot": item["rot"], "flip": item["flip"],
			"strokes": item["strokes"], "found": false,
		})


# ═══════════════ 장면 ═══════════════

func _layer() -> void:
	_layers.append(_props.end())


# 벽(무늬)과 원근감 있는 마룻바닥
func _room() -> void:
	var w := world_size.x
	var h := world_size.y
	_wall_h = h * _rng.randf_range(0.27, 0.31)
	_props.begin(Vector2.ZERO, 1.0)
	var P := _props
	# 벽, 걸레받이 색 (판마다 다른 색)
	var wall_c := P.pick(["#fbe7c6", "#d8f0e4", "#dcecf9", "#f9e0e6", "#ece4f7", "#fdf3c4"])
	var floor_c := P.pick(["#e2b983", "#d9a86c", "#e8c79a", "#cfa070"])
	P.col(wall_c)
	P.F([Vector2(0, 0), Vector2(w, 0), Vector2(w, _wall_h), Vector2(0, _wall_h)])
	P.col(wall_c.darkened(0.25))
	P.F([Vector2(0, _wall_h - 24), Vector2(w, _wall_h - 24), Vector2(w, _wall_h), Vector2(0, _wall_h)])
	# 벽지 줄무늬: 한 칸 걸러 조금 진하게
	var stripe := 0
	var sx0 := 0.0
	while sx0 < w:
		if stripe % 2 == 0:
			P.col(wall_c.darkened(0.06))
			P.F([Vector2(sx0, 0), Vector2(sx0 + 60, 0), Vector2(sx0 + 60, _wall_h - 24), Vector2(sx0, _wall_h - 24)])
		sx0 += 60
		stripe += 1
	P.L([Vector2(0, _wall_h), Vector2(w, _wall_h)])
	P.L([Vector2(0, _wall_h - 24), Vector2(w, _wall_h - 24)])   # 걸레받이
	# 벽지: 세로 줄과 작은 무늬
	var x := 0.0
	var motif := _rng.randi_range(0, 2)
	while x < w:
		var y := _rng.randf_range(20, 50)
		while y < _wall_h - 50:
			var c := Vector2(x + 30, y)
			match motif:
				0: P.L([c + Vector2(-5, 0), c + Vector2(0, -6), c + Vector2(5, 0), c + Vector2(0, 6), c + Vector2(-5, 0)])
				1: P.L(P.arc_pts(c, Vector2(4, 4), 0, 360, 6))
				_: P.L([c + Vector2(-5, -3), c + Vector2(5, 3)])
			y += 70
		x += 60
	# 마루: 멀수록 촘촘한 가로줄 + 엇갈린 이음매
	var y := _wall_h
	var row := 0
	while y < h:
		var gap := lerpf(45, 115, (y - _wall_h) / (h - _wall_h))
		var ny := y + gap
		# 마루 널빤지: 이음매마다 나무 색을 조금씩 다르게 칠한다
		var sx := -_rng.randf_range(0, 250)
		while sx < w:
			var nx := sx + _rng.randf_range(260, 420)
			P.col(floor_c.lerp(Color("#fff3dc"), _rng.randf_range(0.0, 0.3)))
			P.F([Vector2(maxf(sx, 0), y), Vector2(minf(nx, w), y), Vector2(minf(nx, w), minf(ny, h)), Vector2(maxf(sx, 0), minf(ny, h))])
			if sx > 0:
				P.L([Vector2(sx, y), Vector2(sx, ny)])
			sx = nx
		P.L([Vector2(0, ny), Vector2(w, ny)])
		y = ny
		row += 1
	_layer()


func _wall_items() -> void:
	var w := world_size.x
	var P := _props
	# 깃발 장식 (벽 위쪽 가로질러)
	P.begin(Vector2(w / 2, 50), 1.0)
	P.bunting(w * 0.9)
	_layer()
	# 창문, 시계, 액자, 게시판을 벽에 나란히 (겹치지 않게 칸을 나눠서)
	var slots := 4
	var kinds := ["window", "window", "clock", "frame", "board", "frame"]
	_shuffle(kinds)
	for i in range(slots):
		var cx := (i + 0.5) * w / slots + _rng.randf_range(-30, 30)
		match kinds[i]:
			"window":
				P.begin(Vector2(cx, _wall_h * 0.62), 1.0)
				P.window(_rng.randf_range(170, 220), _rng.randf_range(150, 190))
			"clock":
				P.begin(Vector2(cx, _wall_h * 0.5), 1.0)
				P.clock(_rng.randf_range(40, 55))
			"frame":
				P.begin(Vector2(cx, _wall_h * 0.55), 1.0)
				P.frame(_rng.randf_range(110, 150), _rng.randf_range(90, 120))
			_:
				P.begin(Vector2(cx, _wall_h * 0.62), 1.0)
				P.board(_rng.randf_range(200, 250), _rng.randf_range(140, 170))
		_layer()
	# 벽 앞 책장들 (바닥에 서 있음)
	var x := _rng.randf_range(-40, 60)
	while x < w:
		var bw := _rng.randf_range(190, 280)
		if _rng.randf() < 0.75:
			P.begin(Vector2(x + bw / 2, _wall_h + _rng.randf_range(20, 40)), 1.0)
			P.bookshelf(bw, _rng.randf_range(250, 330))
			_layer()
		x += bw + _rng.randf_range(10, 120)


# 바닥의 납작한 것(깔개, 종이, 책) → 서 있는 것(사람, 동물, 가구)
func _floor_items(prop_count: int, clutter_count: int) -> void:
	var w := world_size.x
	var h := world_size.y
	var top := _wall_h + 60.0
	var P := _props
	# 깔개 한두 개
	for i in range(_rng.randi_range(1, 2)):
		var y := _rng.randf_range(top + 200, h - 200)
		P.begin(Vector2(_rng.randf_range(250, w - 250), y), _scale_at(y))
		P.rug(_rng.randf_range(380, 520))
		_layer()
	# 납작한 잡동사니 (뒤에서 앞으로)
	var flat := []
	for i in range(clutter_count):
		flat.append(Vector2(_rng.randf_range(40, w - 40), _rng.randf_range(top, h - 20)))
	flat.sort_custom(func(a, b): return a.y < b.y)
	for p in flat:
		P.begin(p, _scale_at(p.y), _rng.randf() < 0.5)
		match _rng.randi_range(0, 2):
			0: P.paper(_rng.randf_range(60, 90))
			1: P.flat_book(_rng.randf_range(70, 100))
			_: P.open_book_flat()
		_layer()
	# 서 있는 것: 바닥을 칸으로 나눠 고르게 흩뿌린다
	var cols := 5
	var rows := ceili(float(prop_count) / cols)
	var spots := []
	for r in range(rows):
		for c in range(cols):
			if spots.size() >= prop_count:
				break
			var cx := (c + _rng.randf_range(0.1, 0.9)) * w / cols
			var cy := top + 40 + (r + _rng.randf_range(0.1, 0.9)) * (h - top - 40) / rows
			spots.append(Vector2(cx, cy))
	spots.sort_custom(func(a, b): return a.y < b.y)
	# 소품 종류와 나오는 비율
	var kinds := {"kid": 18, "kid_sitting": 8, "cat": 4, "dog": 4, "bear": 3, "rabbit": 3, "table": 7,
			"desk": 4, "chair": 8, "stool": 4, "plant": 6, "box": 7, "book_stack": 8, "backpack": 4,
			"globe": 2, "basket": 3, "bin": 3, "ball": 3, "blocks": 3, "floor_lamp": 2}
	for p in spots:
		var kind := _pick(kinds)
		P.begin(p, _scale_at(p.y), _rng.randf() < 0.5)
		match kind:
			"kid": P.kid()
			"kid_sitting": P.kid_sitting()
			"cat": P.cat()
			"dog": P.dog()
			"bear": P.bear()
			"rabbit": P.rabbit()
			"table": P.table(_rng.randf_range(200, 260), _rng.randf_range(100, 130))
			"desk": P.desk(_rng.randf_range(200, 250), _rng.randf_range(110, 130))
			"chair": P.chair(_rng.randf_range(150, 180))
			"stool": P.stool(_rng.randf_range(80, 110))
			"plant": P.plant()
			"box": P.box(_rng.randf_range(90, 130), _rng.randf_range(70, 100))
			"book_stack": P.book_stack()
			"backpack": P.backpack(_rng.randf_range(80, 100))
			"globe": P.globe()
			"basket": P.basket()
			"bin": P.bin()
			"ball": P.ball(_rng.randf_range(18, 28))
			"blocks": P.blocks()
			_: P.floor_lamp(_rng.randf_range(220, 280))
		_layer()


# 바닥 위치 y에 따른 크기 (멀리 있으면 작게)
func _scale_at(y: float) -> float:
	var t := clampf((y - _wall_h) / (world_size.y - _wall_h), 0.0, 1.0)
	return lerpf(0.8, 1.4, t)


func _pick(weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += int(weights[k])
	var r := _rng.randi_range(1, total)
	for k in weights:
		r -= int(weights[k])
		if r <= 0:
			return k
	return weights.keys()[0]


# ═══════════════ 가림 처리 ═══════════════

# 뒤에서 앞으로 그린 그림들 중, 앞 그림의 채우기 모양 아래에 들어간 뒤 그림의 선을 지운다.
# 방법: 그림 전체를 작은 칸으로 나누고, 칸마다 "가장 앞에서 덮은 그림 번호"를 적는다.
#       선의 점이 있는 칸에 자기보다 앞의 그림 번호가 적혀 있으면 가려진 것.
func _flatten() -> void:
	var ow := int(world_size.x / OCC_CELL) + 1
	var oh := int(world_size.y / OCC_CELL) + 1
	var owner := PackedInt32Array()
	owner.resize(ow * oh)
	owner.fill(-1)
	for i in range(_layers.size()):
		for f in _layers[i]["fills"]:
			# 그림자처럼 비치는 색칠(ghost)은 뒤의 선을 가리지 않는다
			if not f["ghost"]:
				_raster_poly(f["poly"], i, owner, ow, oh)
			# 화면에 칠할 수 있는 모양(세모로 나눌 수 있는 모양)만 색칠 목록에 넣는다
			if not Geometry2D.triangulate_polygon(f["poly"]).is_empty():
				fills.append(f)
	lines = []
	for i in range(_layers.size()):
		for stroke in _layers[i]["strokes"]:
			var pts := _fine(_wobble(stroke), 5.0)
			var cur := PackedVector2Array()
			for p in pts:
				var cx := clampi(int(p.x / OCC_CELL), 0, ow - 1)
				var cy := clampi(int(p.y / OCC_CELL), 0, oh - 1)
				var visible := owner[cy * ow + cx] <= i and p.x >= 0 and p.y >= 0 and p.x <= world_size.x and p.y <= world_size.y
				if visible:
					cur.append(p)
				else:
					if cur.size() >= 2:
						lines.append(cur)
					cur = PackedVector2Array()
			if cur.size() >= 2:
				lines.append(cur)
	_layers = []


# 다각형 안쪽 칸에 번호 id를 적는다 (가로줄마다 테두리와 만나는 점을 구해 그 사이를 채움)
func _raster_poly(poly: PackedVector2Array, id: int, owner: PackedInt32Array, ow: int, oh: int) -> void:
	if poly.size() < 3:
		return
	var y_min := INF
	var y_max := -INF
	for p in poly:
		y_min = minf(y_min, p.y)
		y_max = maxf(y_max, p.y)
	var r0 := maxi(0, int(y_min / OCC_CELL))
	var r1 := mini(oh - 1, int(y_max / OCC_CELL))
	var n := poly.size()
	for row in range(r0, r1 + 1):
		var y := (row + 0.5) * OCC_CELL
		var xs := []
		for k in range(n):
			var a := poly[k]
			var b := poly[(k + 1) % n]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var c0 := maxi(0, int(xs[k] / OCC_CELL) + 1)
			var c1 := mini(ow - 1, int(xs[k + 1] / OCC_CELL) - 1)
			for c in range(c0, c1 + 1):
				owner[row * ow + c] = id


# 선을 step 간격의 점으로 잘게 나눈다
func _fine(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var n := maxi(1, int(a.distance_to(b) / step))
		for k in range(n):
			out.append(a.lerp(b, float(k) / n))
	if points.size() > 0:
		out.append(points[points.size() - 1])
	return out


# 손으로 그린 것처럼 살짝 흔든다
func _wobble(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 18.0))
		var normal := (b - a).orthogonal().normalized()
		for k in range(n):
			var p := a.lerp(b, float(k) / n)
			if i > 0 or k > 0:
				p += normal * _rng.randf_range(-0.9, 0.9)
			out.append(p)
	if points.size() > 0:
		out.append(points[points.size() - 1])
	return out


# ═══════════════ 숨기기 ═══════════════

# 선이 지나간 칸을 기록한다. _occ는 한 칸씩 넓혀서 "선 근처(약 4~8px)"인지 바로 알 수 있게 한다.
func _index() -> void:
	_gw = int(world_size.x / CELL) + 1
	_gh = int(world_size.y / CELL) + 1
	_cw = int(world_size.x / COARSE) + 1
	_ch = int(world_size.y / COARSE) + 1
	var raw := PackedByteArray()
	raw.resize(_gw * _gh)
	raw.fill(0)
	_dense.resize(_cw * _ch)
	_dense.fill(0)
	for stroke in lines:
		_mark_stroke(stroke, raw)
	_occ.resize(_gw * _gh)
	_occ.fill(0)
	for y in range(1, _gh - 1):
		for x in range(1, _gw - 1):
			if raw[y * _gw + x] != 0:
				for dy in range(-1, 2):
					var row := (y + dy) * _gw
					_occ[row + x - 1] = 1
					_occ[row + x] = 1
					_occ[row + x + 1] = 1


func _mark_stroke(stroke: PackedVector2Array, raw: PackedByteArray) -> void:
	for i in range(stroke.size() - 1):
		var a := stroke[i]
		var b := stroke[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 3.0))
		for k in range(n + 1):
			var p := a.lerp(b, float(k) / n)
			var gx := int(p.x / CELL)
			var gy := int(p.y / CELL)
			if gx >= 0 and gy >= 0 and gx < _gw and gy < _gh:
				if raw[gy * _gw + gx] == 0:
					raw[gy * _gw + gx] = 1
					_dense[int(p.y / COARSE) * _cw + int(p.x / COARSE)] += 1


# 물건 하나를 숨길 자리를 고른다. 후보를 여러 개 만들어 "장면 선과 맞닿는 정도"를 재고,
# 단계의 camo 값에 따라 잘 숨는 자리를 고른다.
func _place(id: String, s: Dictionary, placed: Array) -> Dictionary:
	var cands := []
	for attempt in range(CANDIDATES * 3):
		if cands.size() >= CANDIDATES:
			break
		var size := _rng.randf_range(float(s["size"][0]), float(s["size"][1]))
		var pos := Vector2(_rng.randf_range(size * 0.6, world_size.x - size * 0.6),
				_rng.randf_range(size * 0.6, world_size.y - size * 0.6))
		var ok := true
		for q in placed:
			if pos.distance_to(q["pos"]) < (size + q["size"]) * 0.55:
				ok = false
				break
		if not ok:
			continue
		var rot := deg_to_rad(_rng.randf_range(-float(s["rot"]), float(s["rot"])))
		var flip := _rng.randf() < float(s["flip"])
		var strokes := []
		for st in HiddenShapes.placed(id, pos, size, rot, flip):
			strokes.append(_wobble(st))
		var score := _alignment(strokes) + 0.3 * _local_density(pos, size * 0.6)
		cands.append({"id": id, "pos": pos, "size": size, "rot": rot, "flip": flip, "strokes": strokes, "score": score})
	if cands.is_empty():
		var size := float(s["size"][0])
		var pos := Vector2(_rng.randf_range(size, world_size.x - size), _rng.randf_range(size, world_size.y - size))
		var strokes := []
		for st in HiddenShapes.placed(id, pos, size, 0.0, false):
			strokes.append(_wobble(st))
		return {"id": id, "pos": pos, "size": size, "rot": 0.0, "flip": false, "strokes": strokes}
	cands.sort_custom(func(a, b): return a["score"] < b["score"])
	var idx := clampi(int(round(float(s["camo"]) * (cands.size() - 1))), 0, cands.size() - 1)
	return cands[idx]


# 물건 윤곽선 위의 점 중 장면 선 바로 옆에 있는 점의 비율 (0~1). 높을수록 장면에 섞여 안 보인다.
func _alignment(strokes: Array) -> float:
	var total := 0
	var hit := 0
	for st in strokes:
		for i in range(st.size() - 1):
			var a: Vector2 = st[i]
			var b: Vector2 = st[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 6.0))
			for k in range(n):
				var p := a.lerp(b, float(k) / n)
				var gx := int(p.x / CELL)
				var gy := int(p.y / CELL)
				total += 1
				if gx >= 0 and gy >= 0 and gx < _gw and gy < _gh and _occ[gy * _gw + gx] != 0:
					hit += 1
	return float(hit) / maxi(total, 1)


# 자리 주변이 얼마나 빽빽한지 (0~1)
func _local_density(pos: Vector2, r: float) -> float:
	var sum := 0
	var cells := 0
	for cy in range(maxi(int((pos.y - r) / COARSE), 0), mini(int((pos.y + r) / COARSE), _ch - 1) + 1):
		for cx in range(maxi(int((pos.x - r) / COARSE), 0), mini(int((pos.x + r) / COARSE), _cw - 1) + 1):
			sum += _dense[cy * _cw + cx]
			cells += 1
	return clampf(float(sum) / maxi(cells, 1) / 40.0, 0.0, 1.0)


# 동그라미 안의 장면 선을 지운다 (선이 동그라미를 지나가면 그 부분만 끊어 낸다)
func _clear_circle(c: Vector2, r: float) -> void:
	var out := []
	for stroke in lines:
		var near := false
		for p in stroke:
			if p.distance_to(c) < r + 30.0:
				near = true
				break
		if not near:
			out.append(stroke)
			continue
		var cur := PackedVector2Array()
		for p in _fine(stroke, 4.0):
			if p.distance_to(c) < r:
				if cur.size() >= 2:
					out.append(cur)
				cur = PackedVector2Array()
			else:
				cur.append(p)
		if cur.size() >= 2:
			out.append(cur)
	lines = out


func _shuffle(list: Array) -> void:
	for k in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var t = list[k]
		list[k] = list[j]
		list[j] = t


# ═══════════════ 게임에서 쓰는 함수 ═══════════════

# 그림 좌표 p를 눌렀을 때 맞힌 찾을 물건 번호. 없으면 -1.
func hit_target(p: Vector2, tolerance: float) -> int:
	var best := -1
	var best_d := INF
	for t in range(targets.size()):
		if targets[t]["found"]:
			continue
		var d: float = p.distance_to(targets[t]["pos"])
		if d <= targets[t]["size"] * 0.45 + tolerance and d < best_d:
			best = t
			best_d = d
	return best


func found_count() -> int:
	var n := 0
	for t in targets:
		if t["found"]:
			n += 1
	return n


# 물건이 얼마나 잘 숨었는지 (시험용): 찾을 물건 각각의 맞닿음 비율
func target_alignments() -> Array:
	var result := []
	for t in targets:
		result.append(_alignment(t["strokes"]))
	return result
