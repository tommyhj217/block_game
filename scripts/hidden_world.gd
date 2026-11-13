# 숨은그림 한 장(HiddenPuzzle)을 그리는 노드. 크기는 그림 전체 크기.
# 확대·이동은 이 노드의 scale과 position을 바꿔서 한다 (그림을 다시 그리지 않아도 돼서 빠르다).
# _draw()는 그림이 바뀔 때(처음, 찾았을 때, 힌트)만 다시 부른다.
#
# 배경 선과 숨은 물건 선을 똑같은 색·똑같은 굵기로 그린다. 그래야 물건이 배경에 섞여 숨는다.
class_name HiddenWorld
extends Control

var puzzle: HiddenPuzzle
var hint_pos := Vector2.ZERO   # 힌트 동그라미 가운데 (그림 좌표)
var hint_on := false
var reveal_all := false        # 끝났을 때 못 찾은 물건을 빨간 선으로 보여 줌


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_puzzle(p: HiddenPuzzle) -> void:
	puzzle = p
	size = p.world_size
	queue_redraw()


func _draw() -> void:
	if puzzle == null:
		return
	# 종이 바탕, 그 위에 색칠 모양을 뒤에서 앞 순서로 칠한다 (앞 그림이 뒤 그림을 덮는다)
	draw_rect(Rect2(Vector2.ZERO, size), Color("#fdfcf7"))
	# 넣어 둔 그림 파일 장면이면 그 그림을 장면 크기에 맞춰 깐다
	if puzzle.image != null:
		draw_texture_rect(puzzle.image, Rect2(Vector2.ZERO, size), false)
	for f in puzzle.fills:
		draw_colored_polygon(f["poly"], f["color"])
	# 장면 선
	var ink := Config.HIDDEN_INK
	var w := Config.HIDDEN_INK_WIDTH
	for stroke in puzzle.lines:
		draw_polyline(stroke, ink, w, true)
	# 숨은 물건 (찾을 물건) — 배경과 똑같이 그린다
	for t in puzzle.targets:
		var color := ink
		var width := w
		if t["found"]:
			color = Color("#1e9e55")
			width = w * 2.0
		elif reveal_all:
			color = Color("#e04040")
			width = w * 1.6
		for stroke in t["strokes"]:
			draw_polyline(stroke, color, width, true)
		if t["found"]:
			draw_arc(t["pos"], t["size"] * 0.62, 0, TAU, 40, Color("#2ecc71"), 5.0, true)
		elif reveal_all:
			draw_arc(t["pos"], t["size"] * 0.62, 0, TAU, 40, Color("#ff4d4d"), 4.0, true)
	# 힌트: 이 동그라미 어딘가에 있다
	if hint_on:
		draw_circle(hint_pos, Config.HIDDEN_HINT_RADIUS, Color(1, 0.85, 0.2, 0.14))
		draw_arc(hint_pos, Config.HIDDEN_HINT_RADIUS, 0, TAU, 64, Color(0.95, 0.7, 0.1, 0.95), 7.0, true)
