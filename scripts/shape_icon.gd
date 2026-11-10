# 찾을 목록 칸에 숨은 물건의 모양(선 그림)을 똑바로 세워 그리는 작은 그림.
class_name ShapeIcon
extends Control

var shape_id := ""
var color := Color("#2b2620")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_shape(id: String) -> void:
	shape_id = id
	queue_redraw()


func _draw() -> void:
	if shape_id == "":
		return
	var s := minf(size.x, size.y) * 0.9
	for stroke in HiddenShapes.placed(shape_id, size / 2.0, s, 0.0):
		draw_polyline(stroke, color, 2.5, true)
