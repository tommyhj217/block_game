# 숨은그림 찾기 그림 한 장을 만드는 스크립트. (그리기·터치는 하지 않는다)
# 같은 seed와 같은 단계면 언제나 똑같은 그림이 나온다 → 대결할 때 모두 같은 그림을 받는다.
#
# 어렵게 만드는 방법
# - 찾을 그림과 같은 무리(예: 🍎를 찾을 때 🍅🍒🍓)의 닮은꼴을 많이, 특히 정답 바로 근처에 뿌린다
# - 크기·기울기·좌우 뒤집기·흐림·색 바꾸기를 섞는다
# - 정답 그림을 그리는 순서를 중간에 끼워 넣어 다른 그림에 일부가 가려지게 한다 (다 가려지지는 않게)
# - 찾을 그림은 그림 안에 딱 하나만 있다 (가짜 그림에는 정답과 똑같은 그림을 쓰지 않는다)
class_name HiddenPuzzle
extends RefCounted

# 닮은꼴끼리 묶은 그림 무리. 같은 무리에서 가짜 그림을 고른다.
const GROUPS := [
	["🍎", "🍅", "🍒", "🍓", "🍑", "🍊", "🍋", "🍐", "🍏", "🥝"],
	["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵"],
	["🐟", "🐠", "🐡", "🦈", "🐙", "🦑", "🦀", "🐚", "🐳", "🐬"],
	["🐞", "🐜", "🐝", "🦋", "🐛", "🐌"],
	["🔑", "🗝", "🔒", "🔓", "✂", "📎", "📌", "📍", "🔍", "🔎"],
	["🔨", "🔧", "⛏", "🔩", "⚙", "🧲"],
	["🎸", "🎻", "🎺", "🎷", "🥁", "🎹"],
	["⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🎱"],
	["☀", "🌙", "⭐", "🌟", "✨", "☁", "⚡", "❄"],
	["🌸", "🌼", "🌻", "🌺", "🌷", "🍀", "🌿", "🍁", "🍂"],
	["🚗", "🚕", "🚙", "🚌", "🚓", "🚑", "🚒", "🚚"],
	["⌚", "⏰", "⏱", "🕰", "📱", "💡", "🔦", "🕯"],
]

# 그림 속 물건 하나: {"e": 이모지, "pos": 위치, "rot": 기울기(라디안), "size": 크기(px),
#                   "alpha": 진하기, "flip": 좌우 뒤집힘, "tint": 색, "target": 찾을 그림 번호(아니면 -1)}
var objects := []
# 찾을 그림: {"e": 이모지, "obj": objects 안의 위치, "silhouette": 목록에 그림자로 보여 줄지, "found": 찾았는지}
var targets := []
# 바탕 무늬: {"kind": "circle"|"rect", "pos", "size", "rot", "color"}
var background := []
var world_size := Config.HIDDEN_WORLD

var _rng := RandomNumberGenerator.new()


# 단계 번호(0부터) → 그 단계 설정. 표를 넘으면 마지막 줄.
static func stage_settings(stage: int) -> Dictionary:
	return Config.HIDDEN_STAGES[clampi(stage, 0, Config.HIDDEN_STAGES.size() - 1)]


# static func: 객체를 만들지 않고 `HiddenPuzzle.make(...)`처럼 부르는 함수 (Python의 @staticmethod)
static func make(seed_value: int, stage: int) -> HiddenPuzzle:
	var p := HiddenPuzzle.new()
	p._build(seed_value, stage_settings(stage))
	return p


func _build(seed_value: int, s: Dictionary) -> void:
	_rng.seed = seed_value
	_build_background()

	# 1) 찾을 그림 고르기: 서로 다른 무리에서 고르고, 그림 수가 무리 수보다 많으면 같은 무리에서도 고른다
	var target_count: int = s["targets"]
	var group_order := range(GROUPS.size())
	_shuffle(group_order)
	var chosen := []          # 고른 이모지
	var target_groups := []   # 각 찾을 그림의 무리 번호
	var i := 0
	while chosen.size() < target_count:
		var g: int = group_order[i % group_order.size()]
		var options: Array = GROUPS[g].filter(func(e): return not chosen.has(e))
		if not options.is_empty():
			chosen.append(options[_rng.randi_range(0, options.size() - 1)])
			target_groups.append(g)
		i += 1

	# 2) 가짜 그림에 쓸 수 있는 이모지: 찾을 그림과 똑같은 것은 빼야 정답이 딱 하나가 된다
	var decoy_by_group := []
	for g in range(GROUPS.size()):
		decoy_by_group.append(GROUPS[g].filter(func(e): return not chosen.has(e)))
	var all_decoys := []
	for list in decoy_by_group:
		all_decoys.append_array(list)

	var size_min: float = s["size"][0]
	var size_max: float = s["size"][1]
	var margin := size_max

	# 3) 찾을 그림의 자리 정하기 (서로 너무 붙지 않게, 가장자리에서 조금 떨어지게)
	var target_objs := []
	for t in range(target_count):
		var pos := Vector2.ZERO
		for attempt in range(60):
			pos = Vector2(_rng.randf_range(margin * 1.5, world_size.x - margin * 1.5),
					_rng.randf_range(margin * 1.5, world_size.y - margin * 1.5))
			var ok := true
			for other in target_objs:
				if other["pos"].distance_to(pos) < 260.0:
					ok = false
					break
			if ok:
				break
		# 정답은 크기 범위의 작은 쪽으로 (더 찾기 어렵게)
		var obj := _make_object(chosen[t], pos, lerpf(size_min, size_max, _rng.randf() * 0.6), s)
		obj["target"] = t
		target_objs.append(obj)
		targets.append({"e": chosen[t], "obj": -1, "found": false,
				"silhouette": _rng.randf() < float(s["silhouette"])})

	# 4) 가짜 그림: 정답 근처의 닮은꼴 + 전체에 고르게 뿌린 그림 (반은 정답과 같은 무리)
	var decoys := []
	for t in range(target_count):
		var pool: Array = decoy_by_group[target_groups[t]]
		for n in range(int(s["near"])):
			var angle := _rng.randf_range(0, TAU)
			var dist := _rng.randf_range(70.0, 170.0)
			var pos: Vector2 = target_objs[t]["pos"] + Vector2(cos(angle), sin(angle)) * dist
			pos = pos.clamp(Vector2(margin, margin), world_size - Vector2(margin, margin))
			decoys.append(_make_object(pool[_rng.randi_range(0, pool.size() - 1)], pos,
					_rng.randf_range(size_min, size_max), s))
	var rest: int = int(s["objects"]) - target_count - decoys.size()
	for n in range(maxi(rest, 0)):
		var e: String
		if _rng.randf() < 0.5:
			var pool: Array = decoy_by_group[target_groups[_rng.randi_range(0, target_count - 1)]]
			e = pool[_rng.randi_range(0, pool.size() - 1)]
		else:
			e = all_decoys[_rng.randi_range(0, all_decoys.size() - 1)]
		var pos := Vector2(_rng.randf_range(margin * 0.5, world_size.x - margin * 0.5),
				_rng.randf_range(margin * 0.5, world_size.y - margin * 0.5))
		decoys.append(_make_object(e, pos, _rng.randf_range(size_min, size_max), s))
	_shuffle(decoys)

	# 5) 그리는 순서: 가짜 그림 사이에 정답을 끼워 넣는다 (뒤에 그려지는 그림이 위에 덮인다)
	objects = decoys
	for obj in target_objs:
		var at := _rng.randi_range(int(objects.size() * 0.3), int(objects.size() * 0.85))
		objects.insert(at, obj)
	# 정답 위에 그려지는 그림이 정답 한가운데를 다 덮지 않게 살짝 비켜 놓는다
	for k in range(objects.size()):
		var obj: Dictionary = objects[k]
		if obj["target"] < 0:
			continue
		for j in range(k + 1, objects.size()):
			var other: Dictionary = objects[j]
			var d: Vector2 = other["pos"] - obj["pos"]
			var min_d: float = obj["size"] * 0.45
			if d.length() < min_d:
				var dir := d.normalized() if d.length() > 0.1 else Vector2.RIGHT
				other["pos"] = obj["pos"] + dir * min_d
	# 찾을 그림이 objects 몇 번째에 있는지 기록
	for k in range(objects.size()):
		var t: int = objects[k]["target"]
		if t >= 0:
			targets[t]["obj"] = k


func _make_object(e: String, pos: Vector2, obj_size: float, s: Dictionary) -> Dictionary:
	var tint := Color.WHITE
	if s["tint"] and _rng.randf() < 0.6:
		# 색을 살짝 바꿈 (곱하기라서 조금 어둡거나 한쪽 색이 빠진 느낌)
		tint = Color(_rng.randf_range(0.65, 1.0), _rng.randf_range(0.65, 1.0), _rng.randf_range(0.65, 1.0))
	return {
		"e": e, "pos": pos, "size": obj_size, "target": -1,
		"rot": deg_to_rad(_rng.randf_range(-float(s["rot"]), float(s["rot"]))),
		"alpha": _rng.randf_range(float(s["alpha"]), 1.0),
		"flip": _rng.randf() < float(s["flip"]),
		"tint": tint,
	}


# 바탕: 흐릿한 색 동그라미와 네모를 잔뜩 깔아 그림이 바탕에 묻히게 한다
func _build_background() -> void:
	var palette := [Color("#e9d8a6"), Color("#94d2bd"), Color("#ee9b00"), Color("#ca6702"),
			Color("#bb3e03"), Color("#0a9396"), Color("#9b5de5"), Color("#f15bb5"), Color("#00bbf9")]
	for n in range(90):
		var c: Color = palette[_rng.randi_range(0, palette.size() - 1)]
		c.a = _rng.randf_range(0.18, 0.45)
		background.append({
			"kind": "circle" if _rng.randf() < 0.55 else "rect",
			"pos": Vector2(_rng.randf_range(0, world_size.x), _rng.randf_range(0, world_size.y)),
			"size": _rng.randf_range(60.0, 320.0),
			"rot": _rng.randf_range(0, PI),
			"color": c,
		})


# 배열 섞기 (난수 씨앗을 써야 모두 같은 그림이 나온다)
func _shuffle(list: Array) -> void:
	for k in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var t = list[k]
		list[k] = list[j]
		list[j] = t


# 그림 좌표 p를 눌렀을 때 맞힌 찾을 그림 번호. 없으면 -1.
# tolerance: 정답 그림 둘레에서 조금 벗어나도 봐주는 거리 (그림 좌표)
func hit_target(p: Vector2, tolerance: float) -> int:
	var best := -1
	var best_d := INF
	for t in range(targets.size()):
		if targets[t]["found"]:
			continue
		var obj: Dictionary = objects[targets[t]["obj"]]
		var d: float = p.distance_to(obj["pos"])
		if d <= obj["size"] * 0.5 + tolerance and d < best_d:
			best = t
			best_d = d
	return best


func found_count() -> int:
	var n := 0
	for t in targets:
		if t["found"]:
			n += 1
	return n
