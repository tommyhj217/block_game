# 숨은그림 한 장(HiddenPuzzle)을 그리는 노드. 크기는 그림 전체 크기.
# 확대·이동은 이 노드의 scale과 position을 바꿔서 한다 (그림을 다시 그리지 않아도 돼서 빠르다).
# _draw()는 그림이 바뀔 때(처음, 찾았을 때, 힌트)만 다시 부른다.
class_name HiddenWorld
extends Control

const GLYPH_SIZE := 64   # 이모지를 이 글자 크기로 그리고 늘이거나 줄인다 (글자 모양 저장을 한 크기만 쓰려고)

var puzzle: HiddenPuzzle
var hint_pos := Vector2.ZERO   # 힌트 동그라미 가운데 (그림 좌표)
var hint_on := false
var reveal_all := false        # 끝났을 때 못 찾은 정답을 빨간 동그라미로 보여 줌


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_puzzle(p: HiddenPuzzle) -> void:
	puzzle = p
	size = p.world_size
	queue_redraw()


func _draw() -> void:
	if puzzle == null:
		return
	# 바탕색과 무늬
	draw_rect(Rect2(Vector2.ZERO, size), Color("#f4ecd8"))
	for b in puzzle.background:
		draw_set_transform(b["pos"], b["rot"], Vector2.ONE)
		var s: float = b["size"]
		if b["kind"] == "circle":
			draw_circle(Vector2.ZERO, s / 2.0, b["color"])
		else:
			draw_rect(Rect2(-Vector2(s, s * 0.6) / 2.0, Vector2(s, s * 0.6)), b["color"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 물건들 (앞에 있는 것부터 그려서 뒤의 것이 위에 덮인다)
	var font := get_theme_default_font()
	for obj in puzzle.objects:
		_draw_emoji(font, obj)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 찾은 그림에는 초록 동그라미
	for t in puzzle.targets:
		var obj: Dictionary = puzzle.objects[t["obj"]]
		var r: float = obj["size"] * 0.7
		if t["found"]:
			draw_arc(obj["pos"], r, 0, TAU, 40, Color("#2ecc71"), 6.0, true)
		elif reveal_all:
			draw_arc(obj["pos"], r, 0, TAU, 40, Color("#ff4d4d"), 6.0, true)

	# 힌트: 이 동그라미 어딘가에 있다
	if hint_on:
		draw_arc(hint_pos, Config.HIDDEN_HINT_RADIUS, 0, TAU, 64, Color(1, 0.85, 0.2, 0.9), 8.0, true)
		draw_circle(hint_pos, Config.HIDDEN_HINT_RADIUS, Color(1, 0.9, 0.3, 0.12))


# 이모지 하나를 위치·기울기·크기·뒤집기·흐림·색을 맞춰 그린다
func _draw_emoji(font: Font, obj: Dictionary) -> void:
	var s: float = obj["size"] / GLYPH_SIZE
	var sx := -s if obj["flip"] else s
	# draw_set_transform: 이 뒤로 그리는 것들의 기준점·회전·배율을 바꾼다
	draw_set_transform(obj["pos"], obj["rot"], Vector2(sx, s))
	var e: String = obj["e"]
	var w := font.get_string_size(e, HORIZONTAL_ALIGNMENT_LEFT, -1, GLYPH_SIZE).x
	var color: Color = obj["tint"]
	color.a = obj["alpha"]
	# 글자는 기준선(아랫줄)에 맞춰 그려지므로 가운데가 pos에 오게 옮긴다
	draw_string(font, Vector2(-w / 2.0, GLYPH_SIZE * 0.36), e, HORIZONTAL_ALIGNMENT_LEFT, -1, GLYPH_SIZE, color)
