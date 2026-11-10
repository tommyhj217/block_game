# 숨은그림으로 숨길 물건들의 선 그림 모음.
# 모든 물건은 가운데가 (0, 0)이고 가로·세로 -0.5 ~ 0.5 안에 들어가는 "선(획)" 목록으로 되어 있다.
# 실제 그림에 넣을 때는 크기만큼 늘이고 돌려서 배경과 같은 굵기·같은 색의 선으로 그린다.
# (진짜 숨은그림 찾기처럼 색이나 채우기 없이 윤곽선만 있어야 배경 선 속에 섞여 숨는다)
class_name HiddenShapes
extends RefCounted

# static var: 클래스 전체가 함께 쓰는 변수 (한 번 만든 모양을 다시 쓰려고 저장)
static var _cache := {}


# 모양 이름표 목록
static func ids() -> Array:
	return all().keys()


# 이름표 → {"name": 한글 이름, "strokes": [선, 선, ...]}
static func all() -> Dictionary:
	if _cache.is_empty():
		_cache = _build()
	return _cache


# 모양을 위치 pos, 크기 size, 기울기 rot(라디안), 좌우 뒤집기 flip으로 옮긴 선 목록
static func placed(id: String, pos: Vector2, size: float, rot: float, flip: bool = false) -> Array:
	var result := []
	for stroke in all()[id]["strokes"]:
		var out := PackedVector2Array()
		for p in stroke:
			var q: Vector2 = p
			if flip:
				q.x = -q.x
			out.append(pos + (q * size).rotated(rot))
		result.append(out)
	return result


# ─── 선 만들기 도우미 ───

# 타원의 일부(호). 각도는 도 단위, 0도 = 오른쪽, 90도 = 아래쪽
static func _arc(c: Vector2, r: Vector2, a0: float, a1: float, n: int = 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(n + 1):
		var a := deg_to_rad(lerpf(a0, a1, float(i) / n))
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return out


static func _circle(c: Vector2, r: float, n: int = 18) -> PackedVector2Array:
	return _arc(c, Vector2(r, r), 0, 360, n)


static func _ellipse(c: Vector2, r: Vector2, n: int = 18) -> PackedVector2Array:
	return _arc(c, r, 0, 360, n)


# 점들을 이은 선. closed면 처음 점으로 돌아와 닫는다
static func _line(points: Array, closed: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	if closed:
		out.append(points[0])
	return out


static func _rect(a: Vector2, b: Vector2) -> PackedVector2Array:
	return _line([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)], true)


# ─── 물건들 ───

static func _build() -> Dictionary:
	var s := {}

	s["banana"] = {"name": "바나나", "strokes": [
		_arc(Vector2(0, -0.25), Vector2(0.46, 0.6), 15, 165),
		_arc(Vector2(0, -0.38), Vector2(0.38, 0.52), 25, 155),
		_line([Vector2(0.44, -0.09), Vector2(0.34, -0.12)]),
		_line([Vector2(-0.44, -0.09), Vector2(-0.34, -0.12)]),
		_line([Vector2(0.44, -0.09), Vector2(0.5, -0.2)]),
	]}
	s["key"] = {"name": "열쇠", "strokes": [
		_circle(Vector2(-0.3, 0), 0.17), _circle(Vector2(-0.3, 0), 0.06, 10),
		_line([Vector2(-0.13, -0.04), Vector2(0.46, -0.04), Vector2(0.46, 0.04), Vector2(-0.13, 0.04)]),
		_line([Vector2(0.28, 0.04), Vector2(0.28, 0.17), Vector2(0.34, 0.17), Vector2(0.34, 0.04)]),
		_line([Vector2(0.4, 0.04), Vector2(0.4, 0.13), Vector2(0.46, 0.13)]),
	]}
	s["fish"] = {"name": "물고기", "strokes": [
		_ellipse(Vector2(-0.07, 0), Vector2(0.32, 0.2)),
		_line([Vector2(0.22, 0), Vector2(0.48, -0.18), Vector2(0.46, 0.18)], true),
		_circle(Vector2(-0.24, -0.04), 0.035, 8),
		_arc(Vector2(-0.02, 0), Vector2(0.08, 0.17), -70, 70, 8),
	]}
	s["cup"] = {"name": "컵", "strokes": [
		_line([Vector2(-0.3, -0.3), Vector2(-0.24, 0.32), Vector2(0.18, 0.32), Vector2(0.24, -0.3)]),
		_ellipse(Vector2(-0.03, -0.3), Vector2(0.27, 0.06), 14),
		_arc(Vector2(0.25, 0.0), Vector2(0.15, 0.15), -80, 80, 10),
		_arc(Vector2(0.24, 0.0), Vector2(0.08, 0.08), -70, 70, 8),
	]}
	s["pencil"] = {"name": "연필", "strokes": [
		_rect(Vector2(-0.46, -0.08), Vector2(0.24, 0.08)),
		_line([Vector2(0.24, -0.08), Vector2(0.46, 0), Vector2(0.24, 0.08)]),
		_line([Vector2(0.38, -0.025), Vector2(0.46, 0), Vector2(0.38, 0.025)], true),
		_line([Vector2(-0.34, -0.08), Vector2(-0.34, 0.08)]),
		_line([Vector2(-0.3, -0.08), Vector2(-0.3, 0.08)]),
	]}
	var heart := PackedVector2Array()
	for i in range(31):
		var t := TAU * i / 30.0
		heart.append(Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) / 34.0)
	s["heart"] = {"name": "하트", "strokes": [heart]}
	var star := []
	for i in range(10):
		var a := deg_to_rad(-90 + 36 * i)
		var r := 0.48 if i % 2 == 0 else 0.2
		star.append(Vector2(cos(a), sin(a)) * r)
	s["star"] = {"name": "별", "strokes": [_line(star, true)]}
	s["moon"] = {"name": "초승달", "strokes": [
		_arc(Vector2(0, 0), Vector2(0.45, 0.45), 62.7, 297.3, 20),
		_arc(Vector2(0.2, 0), Vector2(0.4, 0.4), 89.1, 270.9, 16),
	]}
	s["umbrella"] = {"name": "우산", "strokes": [
		_arc(Vector2(0, 0), Vector2(0.46, 0.36), 180, 360, 18),
		_arc(Vector2(-0.31, 0), Vector2(0.15, 0.07), 180, 360, 6),
		_arc(Vector2(0, 0), Vector2(0.16, 0.07), 180, 360, 6),
		_arc(Vector2(0.31, 0), Vector2(0.15, 0.07), 180, 360, 6),
		_line([Vector2(0, -0.36), Vector2(0, 0.4)]),
		_arc(Vector2(-0.08, 0.4), Vector2(0.08, 0.08), 0, 180, 8),
	]}
	s["bell"] = {"name": "종", "strokes": [
		_line([Vector2(-0.06, -0.38), Vector2(-0.2, -0.3), Vector2(-0.25, -0.1), Vector2(-0.28, 0.1), Vector2(-0.4, 0.25),
				Vector2(0.4, 0.25), Vector2(0.28, 0.1), Vector2(0.25, -0.1), Vector2(0.2, -0.3), Vector2(0.06, -0.38)], true),
		_circle(Vector2(0, -0.43), 0.05, 8),
		_circle(Vector2(0, 0.33), 0.07, 10),
		_line([Vector2(-0.3, 0.15), Vector2(0.3, 0.15)]),
	]}
	s["mitten"] = {"name": "벙어리장갑", "strokes": [
		_line([Vector2(-0.24, 0.46), Vector2(-0.28, -0.1), Vector2(-0.24, -0.36), Vector2(-0.05, -0.46), Vector2(0.15, -0.36),
				Vector2(0.22, -0.08), Vector2(0.36, -0.18), Vector2(0.46, -0.08), Vector2(0.32, 0.14), Vector2(0.2, 0.46)], true),
		_line([Vector2(-0.26, 0.3), Vector2(0.22, 0.3)]),
	]}
	s["hat"] = {"name": "모자", "strokes": [
		_ellipse(Vector2(0, 0.26), Vector2(0.48, 0.1)),
		_line([Vector2(-0.25, 0.22), Vector2(-0.22, -0.3), Vector2(0.22, -0.3), Vector2(0.25, 0.22)]),
		_line([Vector2(-0.24, 0.1), Vector2(0.24, 0.1)]),
	]}
	s["spoon"] = {"name": "숟가락", "strokes": [
		_ellipse(Vector2(0, -0.28), Vector2(0.15, 0.2)),
		_line([Vector2(-0.03, -0.08), Vector2(-0.045, 0.47), Vector2(0.045, 0.47), Vector2(0.03, -0.08)]),
	]}
	s["carrot"] = {"name": "당근", "strokes": [
		_line([Vector2(-0.12, -0.24), Vector2(0, 0.48), Vector2(0.12, -0.24)]),
		_arc(Vector2(0, -0.24), Vector2(0.12, 0.05), 180, 360, 8),
		_line([Vector2(0, -0.27), Vector2(-0.14, -0.48)]), _line([Vector2(0, -0.27), Vector2(0, -0.5)]), _line([Vector2(0, -0.27), Vector2(0.14, -0.48)]),
		_line([Vector2(-0.08, -0.05), Vector2(0.0, -0.03)]), _line([Vector2(0.06, 0.12), Vector2(-0.02, 0.14)]),
	]}
	s["sock"] = {"name": "양말", "strokes": [
		_line([Vector2(-0.16, -0.46), Vector2(0.1, -0.46), Vector2(0.1, 0.1), Vector2(0.36, 0.2), Vector2(0.44, 0.34), Vector2(0.32, 0.46),
				Vector2(-0.1, 0.42), Vector2(-0.16, 0.2)], true),
		_line([Vector2(-0.16, -0.3), Vector2(0.1, -0.3)]),
		_arc(Vector2(-0.08, 0.32), Vector2(0.1, 0.1), 90, 200, 6),
	]}
	s["ring"] = {"name": "반지", "strokes": [
		_circle(Vector2(0, 0.12), 0.3), _circle(Vector2(0, 0.12), 0.23),
		_line([Vector2(-0.1, -0.2), Vector2(0, -0.34), Vector2(0.1, -0.2), Vector2(0, -0.14)], true),
	]}
	s["envelope"] = {"name": "편지봉투", "strokes": [
		_rect(Vector2(-0.46, -0.3), Vector2(0.46, 0.3)),
		_line([Vector2(-0.46, -0.3), Vector2(0, 0.06), Vector2(0.46, -0.3)]),
	]}
	s["kite"] = {"name": "연", "strokes": [
		_line([Vector2(0, -0.46), Vector2(0.26, -0.12), Vector2(0, 0.26), Vector2(-0.26, -0.12)], true),
		_line([Vector2(0, -0.46), Vector2(0, 0.26)]), _line([Vector2(-0.26, -0.12), Vector2(0.26, -0.12)]),
		_line([Vector2(0, 0.26), Vector2(0.06, 0.32), Vector2(-0.02, 0.38), Vector2(0.06, 0.44), Vector2(0.0, 0.5)]),
	]}
	s["boot"] = {"name": "장화", "strokes": [
		_line([Vector2(-0.2, -0.46), Vector2(0.1, -0.46), Vector2(0.1, 0.1), Vector2(0.42, 0.2), Vector2(0.46, 0.42), Vector2(-0.22, 0.42)], true),
		_line([Vector2(-0.21, 0.32), Vector2(0.45, 0.32)]),
		_line([Vector2(-0.2, -0.36), Vector2(0.1, -0.36)]),
	]}
	s["candle"] = {"name": "양초", "strokes": [
		_rect(Vector2(-0.12, -0.08), Vector2(0.12, 0.46)),
		_line([Vector2(0, -0.46), Vector2(0.08, -0.27), Vector2(0.05, -0.18), Vector2(0, -0.15), Vector2(-0.05, -0.18), Vector2(-0.08, -0.27)], true),
		_line([Vector2(0, -0.15), Vector2(0, -0.08)]),
		_line([Vector2(0.12, 0.0), Vector2(0.08, 0.08), Vector2(0.08, 0.16)]),
	]}
	s["icecream"] = {"name": "아이스크림", "strokes": [
		_line([Vector2(-0.22, -0.04), Vector2(0, 0.48), Vector2(0.22, -0.04)], true),
		_line([Vector2(-0.15, 0.1), Vector2(0.06, 0.32)]), _line([Vector2(0.15, 0.1), Vector2(-0.06, 0.32)]),
		_arc(Vector2(0, -0.06), Vector2(0.25, 0.34), 180, 360, 16),
	]}
	var leaf := PackedVector2Array()
	for p in _ellipse(Vector2(0, 0), Vector2(0.44, 0.19), 20):
		leaf.append(p.rotated(deg_to_rad(-25)))
	s["leaf"] = {"name": "나뭇잎", "strokes": [
		leaf,
		_line([Vector2(-0.4, 0.19), Vector2(0.4, -0.19)]),
		_line([Vector2(-0.4, 0.19), Vector2(-0.5, 0.26)]),
		_line([Vector2(-0.1, 0.05), Vector2(-0.05, -0.1)]), _line([Vector2(0.12, -0.05), Vector2(0.17, -0.18)]),
	]}
	s["hammer"] = {"name": "망치", "strokes": [
		_rect(Vector2(-0.34, -0.44), Vector2(0.2, -0.22)),
		_line([Vector2(0.2, -0.4), Vector2(0.4, -0.48)]), _line([Vector2(0.2, -0.26), Vector2(0.4, -0.2)]),
		_rect(Vector2(-0.06, -0.22), Vector2(0.06, 0.48)),
	]}
	s["arrow"] = {"name": "화살", "strokes": [
		_line([Vector2(-0.44, 0.44), Vector2(0.42, -0.42)]),
		_line([Vector2(0.22, -0.4), Vector2(0.42, -0.42), Vector2(0.4, -0.22)]),
		_line([Vector2(-0.44, 0.44), Vector2(-0.44, 0.28)]), _line([Vector2(-0.44, 0.44), Vector2(-0.28, 0.44)]),
		_line([Vector2(-0.36, 0.36), Vector2(-0.36, 0.22)]), _line([Vector2(-0.36, 0.36), Vector2(-0.22, 0.36)]),
	]}
	s["glasses"] = {"name": "안경", "strokes": [
		_circle(Vector2(-0.25, 0.05), 0.18), _circle(Vector2(0.25, 0.05), 0.18),
		_arc(Vector2(0, 0.05), Vector2(0.07, 0.06), 200, 340, 6),
		_line([Vector2(-0.43, 0.02), Vector2(-0.5, -0.1)]), _line([Vector2(0.43, 0.02), Vector2(0.5, -0.1)]),
	]}
	s["mushroom"] = {"name": "버섯", "strokes": [
		_arc(Vector2(0, 0.02), Vector2(0.46, 0.38), 180, 360, 18),
		_line([Vector2(-0.46, 0.02), Vector2(0.46, 0.02)]),
		_line([Vector2(-0.12, 0.02), Vector2(-0.14, 0.46), Vector2(0.14, 0.46), Vector2(0.12, 0.02)]),
		_circle(Vector2(-0.18, -0.15), 0.06, 8), _circle(Vector2(0.12, -0.22), 0.05, 8),
	]}
	s["drop"] = {"name": "물방울", "strokes": [
		_line([Vector2(0, -0.46), Vector2(0.18, -0.12), Vector2(0.26, 0.1), Vector2(0.2, 0.32), Vector2(0, 0.42),
				Vector2(-0.2, 0.32), Vector2(-0.26, 0.1), Vector2(-0.18, -0.12)], true),
		_arc(Vector2(-0.05, 0.14), Vector2(0.12, 0.14), 110, 200, 5),
	]}
	s["needle"] = {"name": "바늘", "strokes": [
		_line([Vector2(-0.48, 0.03), Vector2(0.36, 0.03), Vector2(0.36, -0.03), Vector2(-0.48, 0.03)]),
		_ellipse(Vector2(0.28, 0), Vector2(0.05, 0.015), 8),
		_line([Vector2(0.36, 0), Vector2(0.42, 0.06), Vector2(0.46, -0.04), Vector2(0.5, 0.05)]),
	]}
	s["toothbrush"] = {"name": "칫솔", "strokes": [
		_line([Vector2(-0.48, 0.06), Vector2(0.2, 0.0), Vector2(0.46, 0.0), Vector2(0.46, 0.06), Vector2(0.2, 0.06), Vector2(-0.48, 0.12)], true),
		_line([Vector2(0.24, 0.0), Vector2(0.24, -0.12)]), _line([Vector2(0.31, 0.0), Vector2(0.31, -0.12)]),
		_line([Vector2(0.38, 0.0), Vector2(0.38, -0.12)]), _line([Vector2(0.45, 0.0), Vector2(0.45, -0.12)]),
	]}
	s["pizza"] = {"name": "피자 조각", "strokes": [
		_line([Vector2(0, 0.46), Vector2(-0.32, -0.3), Vector2(0.32, -0.3)], true),
		_arc(Vector2(0, -0.3), Vector2(0.32, 0.1), 180, 360, 10),
		_circle(Vector2(-0.05, -0.1), 0.06, 8), _circle(Vector2(0.1, 0.05), 0.05, 8), _circle(Vector2(-0.1, 0.12), 0.04, 8),
	]}
	s["bone"] = {"name": "뼈다귀", "strokes": [
		_line([Vector2(-0.3, -0.05), Vector2(0.3, -0.05)]), _line([Vector2(-0.3, 0.05), Vector2(0.3, 0.05)]),
		_arc(Vector2(-0.36, -0.08), Vector2(0.09, 0.09), 30, 300, 8), _arc(Vector2(-0.36, 0.08), Vector2(0.09, 0.09), 60, 330, 8),
		_arc(Vector2(0.36, -0.08), Vector2(0.09, 0.09), 240, 510, 8), _arc(Vector2(0.36, 0.08), Vector2(0.09, 0.09), -150, 120, 8),
	]}
	s["sailboat"] = {"name": "돛단배", "strokes": [
		_line([Vector2(-0.42, 0.18), Vector2(0.42, 0.18), Vector2(0.28, 0.4), Vector2(-0.28, 0.4)], true),
		_line([Vector2(0, 0.18), Vector2(0, -0.48)]),
		_line([Vector2(0, -0.44), Vector2(0.32, 0.1), Vector2(0, 0.1)]),
		_line([Vector2(-0.04, -0.3), Vector2(-0.28, 0.1), Vector2(-0.04, 0.1)]),
	]}
	s["bowtie"] = {"name": "나비넥타이", "strokes": [
		_line([Vector2(-0.46, -0.26), Vector2(-0.08, -0.06), Vector2(-0.08, 0.06), Vector2(-0.46, 0.26)], true),
		_line([Vector2(0.46, -0.26), Vector2(0.08, -0.06), Vector2(0.08, 0.06), Vector2(0.46, 0.26)], true),
		_rect(Vector2(-0.08, -0.08), Vector2(0.08, 0.08)),
	]}
	return s
