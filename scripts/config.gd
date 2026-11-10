# 게임 설정값을 한곳에 모아 둔 파일.
# 숫자를 바꾸고 싶으면 다른 스크립트가 아니라 여기만 고치면 된다.
#
# class_name: 이 스크립트에 이름을 붙여서 다른 스크립트에서 `Config.COLS`처럼 바로 쓸 수 있게 한다.
#             (Python에서 모듈을 import 하지 않아도 되는 전역 이름이라고 생각하면 된다)
class_name Config
extends RefCounted

# ─── 판 크기 ───
const COLS := 10   # 가로 칸 수
const ROWS := 20   # 세로 칸 수

# ─── 떨어지는 속도 ───
const FALL_START := 0.8        # 처음에 한 칸 떨어지는 데 걸리는 시간(초)
const FALL_STEP := 0.07        # 레벨이 하나 오를 때마다 줄어드는 시간(초)
const FALL_MIN := 0.08         # 아무리 빨라져도 이보다 빠르지는 않음(초)
const LINES_PER_LEVEL := 10    # 이만큼 줄을 지우면 레벨이 하나 오름
const SECONDS_PER_LEVEL := 25.0  # 줄을 못 지워도 이 시간(초)이 지날 때마다 레벨이 하나 오름 (판이 길어지면 점점 빨라짐)
const GHOST_ENABLED := false   # true면 블록이 떨어질 자리를 테두리로 미리 보여 줌 (너무 쉬워서 꺼 둠)
const SOFT_DROP_INTERVAL := 0.04  # ⬇ 버튼을 누르고 있을 때 한 칸 내려가는 시간(초)
const LOCK_DELAY := 0.5        # 바닥에 닿은 뒤 굳기까지 기다리는 시간(초)
const LOCK_RESET_LIMIT := 15   # 바닥에서 움직여 굳는 시간을 다시 늘릴 수 있는 횟수

# ─── 버튼을 누르고 있을 때 반복 이동 ───
const MOVE_REPEAT_DELAY := 0.17  # 처음 누르고 반복이 시작되기까지(초)
const MOVE_REPEAT_RATE := 0.05   # 반복할 때 한 칸 움직이는 간격(초)
# ▼ 버튼은 ◀ ▶ 와 똑같이 동작한다: 한 번 누르면 한 칸, 누르고 있으면 쭉.
# 바닥까지 쾅(되돌릴 수 없는 동작)은 실수로 안 나오게 "톡톡 두 번" 또는 "판을 아래로 휙"으로만 한다.
const SOFT_DROP_DELAY := 0.15    # ▼를 누르고 이 시간(초)이 지나면 쭉 내려가기 시작
const DOUBLE_TAP_TIME := 0.3     # ▼를 이 시간(초) 안에 두 번 누르면 바닥까지 쾅
const DROP_COOLDOWN := 0.25      # 쾅 한 뒤 이 시간(초) 동안은 ▼를 무시 (다음 블록까지 실수로 떨어뜨리지 않게)
const SWIPE_MIN_DISTANCE := 110.0  # 판 위에서 아래로 이만큼(px) 이상
const SWIPE_MAX_TIME := 0.3        # 이 시간(초) 안에 휙 쓸면 쾅

# ─── 손맛 (연출) ───
const VIBRATION := true          # 폰 진동 쓰기
const DANGER_ROWS := 5           # 블록이 꼭대기에서 이 줄 수 안까지 차면 판 테두리가 빨갛게 깜빡임
const SHAKE_DROP := 5.0          # 바닥에 쾅 떨어뜨릴 때 흔들림 크기(px)
const SHAKE_PER_LINE := 5.0      # 줄 하나 지울 때마다 더해지는 흔들림(px)
const SHAKE_HIT := 12.0          # 방해 줄이 올라올 때 흔들림(px)

# ─── 대전 ───
# 한 번에 지운 줄 수 → 상대에게 보내는 방해 줄 수. (인덱스 = 지운 줄 수)
# 1줄은 0, 2줄은 1, 3줄은 2, 4줄은 4줄을 보낸다.
const GARBAGE_FOR_LINES := [0, 0, 1, 2, 4]
const GARBAGE_MAX_PENDING := 12   # 쌓여서 기다리는 방해 줄의 최대 개수
const NEXT_PREVIEW := 2           # 미리 보여 주는 다음 블록 개수

# ─── 아이템 ───
const ITEM_CHANCE := 0.22   # 새 블록에 아이템이 붙어 나올 확률 (0~1)
const ITEM_MAX := 3         # 한 번에 들고 있을 수 있는 아이템 수
const ITEM_DURATION := 8.0  # 빠르게·안개·방패가 이어지는 시간(초)
const ITEM_GARBAGE_LINES := 3  # 🧱 아이템이 보내는 방해 줄 수
const ITEM_ALL_LINES := 2      # 💥 아이템이 모든 상대에게 보내는 방해 줄 수
const ITEM_SWEEP_LINES := 2    # 🧹 아이템이 지우는 내 아래 줄 수
const ITEM_BARS_COUNT := 3     # 🎁 아이템을 쓰면 다음 블록 몇 개가 막대가 되는지
const FAST_MULTIPLIER := 0.3   # ⚡ 아이템을 맞으면 떨어지는 시간이 이만큼으로 줄어듦

# 아이템 목록. 칸에 저장할 때는 1부터 시작하는 번호(ITEM_ORDER에서의 위치 + 1)를 쓴다. (최대 15개)
# target: true면 상대에게 쓰는 아이템, false면 나에게 쓰는 아이템.
# weight: 나오는 비율. 클수록 자주 나온다.
const ITEM_ORDER := ["garbage", "fast", "fog", "sweep", "shield", "magnet", "bars", "steal", "all"]
const ITEMS := {
	"garbage": {"icon": "🧱", "name": "방해 줄", "target": true, "weight": 3},
	"fast":    {"icon": "⚡", "name": "빨라져라", "target": true, "weight": 2},
	"fog":     {"icon": "🌫", "name": "안개", "target": true, "weight": 2},
	"sweep":   {"icon": "🧹", "name": "아래 청소", "target": false, "weight": 2},
	"shield":  {"icon": "🛡", "name": "방패", "target": false, "weight": 2},
	# 아래는 새 아이템
	"magnet":  {"icon": "🧲", "name": "끌어내리기", "target": false, "weight": 2},  # 내 칸이 모두 아래로 떨어져 구멍이 메워짐
	"bars":    {"icon": "🎁", "name": "막대 선물", "target": false, "weight": 2},   # 다음 블록 3개가 막대
	"steal":   {"icon": "🦝", "name": "훔치기", "target": true, "weight": 2},       # 상대 아이템 하나를 가져옴
	"all":     {"icon": "💥", "name": "모두 공격", "target": true, "weight": 1},     # 모든 상대에게 방해 줄
}

# ─── 블록 색 (칸 번호 1~7은 블록 종류, 8은 방해 줄) ───
const GARBAGE_COLOR_INDEX := 8
const CELL_COLORS := [
	Color(0, 0, 0, 0),        # 0: 빈칸 (쓰지 않음)
	Color("#5ec8e5"),         # 1: 막대
	Color("#f2c84b"),         # 2: 네모
	Color("#b583e0"),         # 3: ㅗ 모양
	Color("#7ccf7a"),         # 4: 계단(오른쪽)
	Color("#ef7f7f"),         # 5: 계단(왼쪽)
	Color("#6f8ff0"),         # 6: ㄴ 모양
	Color("#f2a35b"),         # 7: ㄱ 모양
	Color("#8a8f99"),         # 8: 방해 줄
]
const BOARD_BG := Color("#1f2433")      # 판 바탕색
const BOARD_GRID := Color("#2a3042")    # 판 격자선 색
const SCREEN_BG := Color("#151925")     # 화면 바탕색

# ─── 숨은그림 찾기 ───
const HIDDEN_WORLD := Vector2(1200, 1700)        # 그림 전체 크기 (화면보다 커서 확대해서 찾는다)
const HIDDEN_INK := Color("#2b2620")             # 선 색 (배경과 숨은 물건이 같은 색·같은 굵기여야 숨는다)
const HIDDEN_INK_WIDTH := 3.0                    # 선 굵기 (그림 좌표 px)
const HIDDEN_VIEW_RECT := Rect2(0, 112, 720, 940)  # 그림이 보이는 창 (720x1280 무대 기준)
const HIDDEN_ZOOM_MAX := 3.0        # 가장 크게 확대할 수 있는 배율
const HIDDEN_TAP_TOLERANCE := 14.0  # 정답 그림에서 이만큼(화면 px) 벗어나도 맞은 것으로 봄
const HIDDEN_MISS_FREEZE := 0.8     # 엉뚱한 곳을 누르면 이 시간(초) 동안 못 누름 (마구 누르기 방지)
const HIDDEN_MISS_PENALTY := 3.0    # 혼자 하기: 엉뚱한 곳을 누르면 기록에 더해지는 시간(초)
const HIDDEN_BATTLE_MISS_FREEZE := 1.5  # 대결: 엉뚱한 곳을 누르면 못 누르는 시간(초)
const HIDDEN_HINTS := 1             # 한 판에 쓸 수 있는 💡 힌트 수
const HIDDEN_HINT_PENALTY := 10.0   # 혼자 하기: 힌트를 쓰면 기록에 더해지는 시간(초)
const HIDDEN_HINT_RADIUS := 230.0   # 힌트가 보여 주는 동그라미 크기 (그림 좌표). 정확한 위치는 안 알려 줌
const HIDDEN_COUNTDOWN := 3         # 시작 전 3, 2, 1
const HIDDEN_BATTLE_STAGE := 3      # 대결에서 쓰는 단계 (아래 표의 번호, 0부터)

# 단계별 난이도. 단계가 표 끝을 넘으면 마지막 줄을 계속 쓴다.
#   targets: 찾을 물건 수 / extras: 찾지 않아도 되는 다른 숨은 물건 수 (헷갈리게 함)
#   size: 물건 크기 범위(그림 좌표 px) / rot: 최대 기울기(도) / flip: 좌우 뒤집힐 확률
#   camo: 숨기기 정도 0~1. 자리 후보 중 물건 윤곽이 배경 선과 얼마나 겹치는 자리를 고를지 (1 = 가장 잘 숨는 자리)
#   clear: 물건 안쪽의 배경 선을 지워 줄 확률 (1이면 물건 모양이 또렷, 0이면 배경 선이 물건을 가로질러 더 어려움)
#   props: 바닥에 세워 놓는 소품(사람, 동물, 가구) 수 / clutter: 바닥에 흩어진 납작한 것(종이, 책) 수
const HIDDEN_STAGES := [
	{"targets": 6, "extras": 2, "size": [110, 150], "rot": 25, "flip": 0.0, "camo": 0.5, "clear": 1.0, "props": 26, "clutter": 14},
	{"targets": 7, "extras": 4, "size": [100, 140], "rot": 45, "flip": 0.2, "camo": 0.65, "clear": 0.8, "props": 32, "clutter": 18},
	{"targets": 8, "extras": 6, "size": [90, 125], "rot": 90, "flip": 0.35, "camo": 0.75, "clear": 0.6, "props": 38, "clutter": 22},
	{"targets": 10, "extras": 8, "size": [80, 115], "rot": 180, "flip": 0.5, "camo": 0.85, "clear": 0.4, "props": 44, "clutter": 26},
	{"targets": 12, "extras": 10, "size": [72, 105], "rot": 180, "flip": 0.5, "camo": 0.92, "clear": 0.25, "props": 50, "clutter": 30},
	{"targets": 14, "extras": 12, "size": [64, 95], "rot": 180, "flip": 0.5, "camo": 1.0, "clear": 0.1, "props": 58, "clutter": 34},
]

# ─── 네트워크 ───
const GAME_PORT := 47000        # 게임 연결(ENet)에 쓰는 포트
const DISCOVERY_PORT := 47001   # 방 자동 찾기(UDP)에 쓰는 포트
const MAX_PLAYERS := 6          # 한 방에 들어올 수 있는 최대 인원(방장 포함)
const DISCOVERY_INTERVAL := 1.0 # 방 찾기 신호를 보내는 간격(초)
const STATE_SEND_INTERVAL := 0.1  # 내 판 모양을 상대에게 보내는 최소 간격(초)
const DISCOVERY_TAG := "WRR1"   # 다른 앱의 신호와 섞이지 않게 붙이는 표시
