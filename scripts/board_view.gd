# 블록 판을 화면에 그리는 스크립트. 내 큰 판과 상대의 작은 판 모두 이걸 쓴다.
# 규칙(Board)은 모르고, 받은 칸 값만 그린다. 그래서 네트워크로 받은 상대 판도 그대로 그릴 수 있다.
#
# extends Control: 화면에 자리(위치·크기)를 차지하는 UI 노드.
# _draw(): Godot가 그림을 다시 그려야 할 때 부르는 함수. queue_redraw()를 부르면 다음 프레임에 다시 그린다.
class_name BoardView
extends Control

var cells := PackedByteArray()      # 칸 값들 (Board.snapshot()과 같은 형식)
var active: Array[Vector2i] = []    # 떨어지는 중인 블록 칸 (안개가 있어도 보이게)
var ghost: Array[Vector2i] = []     # 블록이 떨어질 자리 (테두리만 그림)
var fog := false                    # 🌫 안개를 맞았을 때 쌓인 블록을 가린다
var dimmed := false                 # 탈락한 판은 어둡게
var highlighted := false            # 공격 목표로 고른 상대 판은 노란 테두리
var shielded := false               # 🛡 방패 중이면 파란 테두리


func _ready() -> void:
	# 판은 누르는 대상이 아니므로 터치를 통과시킨다
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cells.is_empty():
		cells.resize(Config.COLS * Config.ROWS)
		cells.fill(0)


func set_cells(data: PackedByteArray) -> void:
	if data.size() != Config.COLS * Config.ROWS:
		return  # 크기가 다른 데이터는 무시 (잘못 온 신호)
	cells = data
	queue_redraw()


# 칸 하나의 크기(px). 판이 자기 영역 안에 다 들어가는 가장 큰 크기.
func cell_size() -> float:
	return floorf(minf(size.x / Config.COLS, size.y / Config.ROWS))


func _draw() -> void:
	var cs := cell_size()
	var board_size := Vector2(cs * Config.COLS, cs * Config.ROWS)
	# 판을 영역 가운데에 놓는다
	var origin := ((size - board_size) / 2.0).floor()

	# 바탕
	draw_rect(Rect2(origin, board_size), Config.BOARD_BG)
	# 격자선 (칸이 작으면 지저분해 보여서 생략)
	if cs >= 16:
		for x in range(1, Config.COLS):
			var px := origin.x + x * cs
			draw_line(Vector2(px, origin.y), Vector2(px, origin.y + board_size.y), Config.BOARD_GRID)
		for y in range(1, Config.ROWS):
			var py := origin.y + y * cs
			draw_line(Vector2(origin.x, py), Vector2(origin.x + board_size.x, py), Config.BOARD_GRID)

	# 쌓인 칸과 떨어지는 블록
	for y in range(Config.ROWS):
		for x in range(Config.COLS):
			var value: int = cells[y * Config.COLS + x] if cells.size() > 0 else 0
			if value != 0:
				_draw_cell(origin, cs, x, y, value, 1.0)

	# 🌫 안개: 판 전체를 덮고, 떨어지는 블록만 다시 그려서 보이게 한다
	if fog:
		draw_rect(Rect2(origin, board_size), Color(0.75, 0.78, 0.85, 0.94))
		for c in active:
			if c.y >= 0:
				_draw_cell(origin, cs, c.x, c.y, cells[c.y * Config.COLS + c.x], 1.0)

	# 그림자: 블록이 떨어질 자리를 테두리로 보여 줌
	for c in ghost:
		if c.y >= 0 and not active.has(c):
			var r := Rect2(origin + Vector2(c.x, c.y) * cs, Vector2(cs, cs)).grow(-2)
			draw_rect(r, Color(1, 1, 1, 0.35), false, 2.0)

	# 테두리
	var border := Color("#3a4260")
	var width := 2.0
	if highlighted:
		border = Color("#ffd84a")
		width = 5.0
	if shielded:
		border = Color("#6cc6ff")
		width = 6.0
	draw_rect(Rect2(origin, board_size).grow(width / 2.0), border, false, width)

	# 탈락한 판은 어둡게 덮는다
	if dimmed:
		draw_rect(Rect2(origin, board_size), Color(0, 0, 0, 0.6))


# 칸 하나를 그린다: 색 네모 + 위쪽 밝은 띠 + (있으면) 아이템 그림
func _draw_cell(origin: Vector2, cs: float, x: int, y: int, value: int, alpha: float) -> void:
	var color_index := Board.color_of(value)
	var item := Board.item_of(value)
	var color: Color = Config.CELL_COLORS[color_index]
	color.a = alpha
	var gap := 1.0 if cs >= 12 else 0.5
	var r := Rect2(origin + Vector2(x, y) * cs, Vector2(cs, cs)).grow(-gap)
	draw_rect(r, color)
	# 위쪽 밝은 띠로 살짝 입체감
	draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(1.0, r.size.y * 0.18))), color.lightened(0.35))
	if item > 0:
		if cs >= 14:
			# 아이템 칸은 하얀 바탕에 아이템 그림
			draw_rect(r.grow(-cs * 0.08), Color(1, 1, 1, 0.85))
			var icon: String = Config.ITEMS[Board.item_key(item)]["icon"]
			var font := get_theme_default_font()
			var fs := int(cs * 0.62)
			# draw_string은 글자의 아랫줄(기준선) 위치를 받으므로 조금 아래로 내려 그린다
			draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.78), icon,
					HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs)
		else:
			# 작은 판에서는 하얀 점으로만 표시
			draw_circle(r.get_center(), cs * 0.3, Color.WHITE)
