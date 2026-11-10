# 블록 판 하나의 규칙만 담당하는 스크립트. (화면 그리기, 시간 재기, 네트워크는 하지 않는다)
# - 칸 저장, 블록 생성·이동·회전, 굳히기, 줄 지우기, 방해 줄 넣기, 아이템 칸
# 그림이나 시간에 묶여 있지 않아서 테스트 스크립트에서 바로 시험해 볼 수 있다.
#
# extends RefCounted: 화면에 나오지 않는 가벼운 객체. 아무도 안 쓰면 자동으로 지워진다.
#                     (Python의 보통 클래스와 비슷하다)
class_name Board
extends RefCounted

# ─── 블록 모양 7가지 ───
# 각 모양은 상자(BOX 크기) 안에서 칸 4개의 (x, y) 위치. y는 아래로 갈수록 커진다.
# 순서대로 칸 색 번호 1~7이 된다. (Config.CELL_COLORS 참고)
const SHAPES := [
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],  # 1: 막대
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],  # 2: 네모
	[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # 3: ㅗ 모양
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],  # 4: 계단(오른쪽 위)
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],  # 5: 계단(왼쪽 위)
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # 6: ㄴ 모양
	[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # 7: ㄱ 모양
]
# 각 모양을 돌릴 때 기준이 되는 상자 크기 (막대 4, 네모 2, 나머지 3)
const BOX := [4, 2, 3, 3, 3, 3, 3]
# 돌렸는데 벽이나 블록에 걸리면 옆이나 위로 살짝 밀어서 다시 시도하는 순서
const ROTATE_KICKS := [
	Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1),
	Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-1, -1), Vector2i(1, -1),
]

# ─── 판 상태 ───
# 칸은 한 줄로 펼친 바이트 배열. 칸 (x, y)는 y * COLS + x 번째.
# 칸 값 = 색 번호(0~8, 아래 4비트) + 아이템 번호 * 16 (위 4비트).
#   예) 색 3 + 아이템 2번 → 3 + 2*16 = 35
var cells := PackedByteArray()

# 지금 떨어지는 블록
var piece_type := -1          # 모양 번호 0~6. -1이면 지금 떨어지는 블록이 없음
var piece_rot := 0            # 돌린 횟수 0~3 (시계 방향)
var piece_pos := Vector2i.ZERO  # 상자의 왼쪽 위 칸 위치. 화면 위로 벗어나 y가 음수일 수 있다
var piece_item := 0           # 블록에 붙은 아이템 번호 (0이면 없음)
var piece_item_cell := 0      # 블록 칸 4개 중 몇 번째 칸에 아이템이 붙었는지

var next_queue: Array[int] = []  # 다음에 나올 블록 모양 번호들
var lines_total := 0             # 이 판에서 지운 줄 수 합계
var game_over := false

# 아이템 설정. 혼자 연습할 때는 나에게 쓰는 아이템만 나오게 바꿀 수 있다.
var item_chance := Config.ITEM_CHANCE
var item_pool: Array = Config.ITEM_ORDER.duplicate()

var _rng := RandomNumberGenerator.new()
var _bag: Array[int] = []  # 7가지 모양을 한 번씩 섞어 담은 주머니


# 판을 비우고 새로 시작한다. seed_value가 같으면 블록 순서도 같다.
func reset(seed_value: int) -> void:
	_rng.seed = seed_value
	cells.resize(Config.COLS * Config.ROWS)
	cells.fill(0)
	piece_type = -1
	next_queue.clear()
	_bag.clear()
	lines_total = 0
	game_over = false
	_fill_queue()


# ─── 칸 읽기·쓰기 도우미 ───

func get_cell(x: int, y: int) -> int:
	return cells[y * Config.COLS + x]


func set_cell(x: int, y: int, value: int) -> void:
	cells[y * Config.COLS + x] = value


# 칸 값에서 색 번호만 꺼낸다. (& 15: 아래 4비트만 남김)
static func color_of(value: int) -> int:
	return value & 15


# 칸 값에서 아이템 번호만 꺼낸다. (>> 4: 위 4비트를 아래로 내림)
static func item_of(value: int) -> int:
	return value >> 4


# 아이템 번호(1부터) → 아이템 이름표("garbage" 등)
static func item_key(item_number: int) -> String:
	return Config.ITEM_ORDER[item_number - 1]


# ─── 블록 모양 계산 ───

# 모양 type을 시계 방향으로 rot번 돌렸을 때 상자 안 칸 위치 4개.
# 칸 순서는 돌려도 그대로라서, 아이템이 붙은 칸이 돌린 뒤에도 같은 칸을 따라간다.
static func shape_cells(type: int, rot: int) -> Array[Vector2i]:
	var n: int = BOX[type]
	var result: Array[Vector2i] = []
	for c in SHAPES[type]:
		var p: Vector2i = c
		# 시계 방향 90도 돌리기: (x, y) → (n-1-y, x)
		for i in range(rot % 4):
			p = Vector2i(n - 1 - p.y, p.x)
		result.append(p)
	return result


# 지금 떨어지는 블록의 판 위 칸 위치 4개
func piece_cells() -> Array[Vector2i]:
	return cells_at(piece_type, piece_rot, piece_pos)


func cells_at(type: int, rot: int, pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in shape_cells(type, rot):
		result.append(c + pos)
	return result


# 블록이 그 자리에 들어갈 수 있는지. 화면 위쪽(y < 0)은 비어 있다고 본다.
func fits(type: int, rot: int, pos: Vector2i) -> bool:
	for c in cells_at(type, rot, pos):
		if c.x < 0 or c.x >= Config.COLS or c.y >= Config.ROWS:
			return false
		if c.y >= 0 and get_cell(c.x, c.y) != 0:
			return false
	return true


# ─── 블록 만들기와 움직이기 ───

# 7가지 모양을 섞은 주머니에서 하나씩 꺼내 다음 블록 줄을 채운다.
# (그냥 무작위로 뽑으면 같은 모양만 계속 나올 수 있어서 주머니 방식을 쓴다)
func _fill_queue() -> void:
	while next_queue.size() < Config.NEXT_PREVIEW + 1:
		if _bag.is_empty():
			_bag = [0, 1, 2, 3, 4, 5, 6]
			# 직접 섞기: rng를 써야 seed가 같을 때 결과가 같다
			for i in range(_bag.size() - 1, 0, -1):
				var j := _rng.randi_range(0, i)
				var t := _bag[i]
				_bag[i] = _bag[j]
				_bag[j] = t
		next_queue.append(_bag.pop_back())


# 새 블록을 맨 위 가운데에 내보낸다. 들어갈 자리가 없으면 게임 끝(false).
func spawn() -> bool:
	piece_type = next_queue.pop_front()
	_fill_queue()
	piece_rot = 0
	# 모양의 가장 윗칸이 판 맨 윗줄(y=0)에 오도록 위치를 맞춘다.
	var top := 99
	for c in shape_cells(piece_type, 0):
		top = mini(top, c.y)
	piece_pos = Vector2i((Config.COLS - BOX[piece_type]) / 2, -top)
	# 아이템이 붙을지 정한다
	piece_item = 0
	if not item_pool.is_empty() and _rng.randf() < item_chance:
		var key: String = item_pool[_rng.randi_range(0, item_pool.size() - 1)]
		piece_item = Config.ITEM_ORDER.find(key) + 1
		piece_item_cell = _rng.randi_range(0, 3)
	if not fits(piece_type, piece_rot, piece_pos):
		game_over = true
		return false
	return true


# 블록을 (dx, dy)만큼 옮긴다. 막히면 그대로 두고 false.
func try_move(dx: int, dy: int) -> bool:
	if piece_type < 0:
		return false
	var p := piece_pos + Vector2i(dx, dy)
	if fits(piece_type, piece_rot, p):
		piece_pos = p
		return true
	return false


# 블록을 돌린다. dir = 1이면 시계 방향, -1이면 반대 방향.
func try_rotate(dir: int) -> bool:
	if piece_type < 0 or piece_type == 1:  # 네모(1)는 돌려도 똑같다
		return false
	var r := (piece_rot + dir + 4) % 4
	for k in ROTATE_KICKS:
		if fits(piece_type, r, piece_pos + k):
			piece_rot = r
			piece_pos += k
			return true
	return false


# 블록이 지금 위치에서 바닥까지 몇 칸 떨어질 수 있는지 (그림자 위치 계산에 씀)
func drop_distance() -> int:
	var d := 0
	while fits(piece_type, piece_rot, piece_pos + Vector2i(0, d + 1)):
		d += 1
	return d


# 바닥까지 한 번에 떨어뜨리고 굳힌다.
func hard_drop() -> Dictionary:
	piece_pos.y += drop_distance()
	return lock_piece()


# 블록을 판에 굳히고 꽉 찬 줄을 지운다.
# 돌려주는 값: {"lines": 지운 줄 수, "items": 얻은 아이템 이름표 배열}
func lock_piece() -> Dictionary:
	var result := {"lines": 0, "items": []}
	if piece_type < 0:
		return result
	var list := piece_cells()
	for i in range(list.size()):
		var c := list[i]
		if c.y < 0:
			# 블록이 판 위로 삐져나온 채 굳음 → 꽉 찼다
			game_over = true
			continue
		var value := piece_type + 1
		if piece_item > 0 and i == piece_item_cell:
			value += piece_item * 16
		set_cell(c.x, c.y, value)
	piece_type = -1
	_clear_full_lines(result)
	return result


func _clear_full_lines(result: Dictionary) -> void:
	var y := Config.ROWS - 1
	while y >= 0:
		var full := true
		for x in range(Config.COLS):
			if get_cell(x, y) == 0:
				full = false
				break
		if full:
			# 이 줄에 있던 아이템을 얻는다
			for x in range(Config.COLS):
				var item := item_of(get_cell(x, y))
				if item > 0:
					result["items"].append(item_key(item))
			_remove_row(y)
			result["lines"] += 1
			lines_total += 1
			# 위 줄이 내려왔으니 같은 y를 한 번 더 검사한다
		else:
			y -= 1


# y줄을 지우고 그 위 줄들을 한 칸씩 내린다. 맨 윗줄은 빈 줄이 된다.
func _remove_row(row: int) -> void:
	for y in range(row, 0, -1):
		for x in range(Config.COLS):
			set_cell(x, y, get_cell(x, y - 1))
	for x in range(Config.COLS):
		set_cell(x, 0, 0)


# ─── 대전과 아이템 ───

# 아래에서 방해 줄 n개를 밀어 올린다. hole 칸만 비어 있는 회색 줄이다.
# 위로 밀려 나간 칸에 블록이 있었으면 게임 끝.
func add_garbage(n: int, hole: int) -> void:
	n = mini(n, Config.ROWS)
	if n <= 0:
		return
	# 맨 위 n줄에 블록이 있으면 판 밖으로 밀려나므로 끝
	for y in range(n):
		for x in range(Config.COLS):
			if get_cell(x, y) != 0:
				game_over = true
	# 모든 줄을 n칸씩 위로 올린다
	for y in range(0, Config.ROWS - n):
		for x in range(Config.COLS):
			set_cell(x, y, get_cell(x, y + n))
	# 아래 n줄을 방해 줄로 채운다
	for y in range(Config.ROWS - n, Config.ROWS):
		for x in range(Config.COLS):
			set_cell(x, y, 0 if x == hole else Config.GARBAGE_COLOR_INDEX)
	# 떨어지던 블록이 방해 줄과 겹치면 겹치지 않을 때까지 위로 올린다
	if piece_type >= 0:
		for i in range(n + 1):
			if fits(piece_type, piece_rot, piece_pos):
				break
			piece_pos.y -= 1


# 방해 줄 구멍 위치를 이 판의 난수로 정한다.
func random_hole() -> int:
	return _rng.randi_range(0, Config.COLS - 1)


# 맨 아래 n줄을 지운다 (🧹 아이템). 지운 줄의 아이템은 얻지 않는다.
func clear_bottom(n: int) -> void:
	for i in range(n):
		_remove_row(Config.ROWS - 1)


# 지금 레벨 (지운 줄 수에 따라 0부터 오름)
func level() -> int:
	return lines_total / Config.LINES_PER_LEVEL


# 블록이 쌓인 높이 (빈 판이면 0)
func stack_height() -> int:
	for y in range(Config.ROWS):
		for x in range(Config.COLS):
			if get_cell(x, y) != 0:
				return Config.ROWS - y
	return 0


# 판 모양을 바이트 배열로 복사한다. include_piece면 떨어지는 블록도 그려 넣는다.
# 상대에게 내 판을 보여 줄 때 이 값을 보낸다.
func snapshot(include_piece: bool = true) -> PackedByteArray:
	var copy := cells.duplicate()
	if include_piece and piece_type >= 0:
		var list := piece_cells()
		for i in range(list.size()):
			var c := list[i]
			if c.y >= 0:
				var value := piece_type + 1
				if piece_item > 0 and i == piece_item_cell:
					value += piece_item * 16
				copy[c.y * Config.COLS + c.x] = value
	return copy
