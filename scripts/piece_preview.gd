# "다음에 나올 블록"을 위에서 아래로 그려 주는 작은 칸.
class_name PiecePreview
extends Control

var types: Array[int] = []   # 보여 줄 블록 모양 번호들 (Board.next_queue 앞부분)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_types(list: Array[int]) -> void:
	types = list.duplicate()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Config.BOARD_BG)
	if types.is_empty():
		return
	# 블록 하나가 쓰는 세로 공간
	var slot_h := size.y / types.size()
	var cs := floorf(minf(size.x / 5.0, slot_h / 3.0))
	for i in range(types.size()):
		var t: int = types[i]
		var list := Board.shape_cells(t, 0)
		# 모양이 차지하는 범위를 구해서 칸 가운데에 놓는다
		var min_p := Vector2i(9, 9)
		var max_p := Vector2i(-9, -9)
		for c in list:
			min_p = Vector2i(mini(min_p.x, c.x), mini(min_p.y, c.y))
			max_p = Vector2i(maxi(max_p.x, c.x), maxi(max_p.y, c.y))
		var shape_size := Vector2(max_p - min_p + Vector2i.ONE) * cs
		var origin := Vector2((size.x - shape_size.x) / 2.0, i * slot_h + (slot_h - shape_size.y) / 2.0)
		var color: Color = Config.CELL_COLORS[t + 1]
		for c in list:
			var r := Rect2(origin + Vector2(c - min_p) * cs, Vector2(cs, cs)).grow(-1)
			draw_rect(r, color)
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.18)), color.lightened(0.35))
