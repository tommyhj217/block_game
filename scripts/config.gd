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
const SOFT_DROP_INTERVAL := 0.04  # ⬇ 버튼을 누르고 있을 때 한 칸 내려가는 시간(초)
const LOCK_DELAY := 0.5        # 바닥에 닿은 뒤 굳기까지 기다리는 시간(초)
const LOCK_RESET_LIMIT := 15   # 바닥에서 움직여 굳는 시간을 다시 늘릴 수 있는 횟수

# ─── 버튼을 누르고 있을 때 반복 이동 ───
const MOVE_REPEAT_DELAY := 0.17  # 처음 누르고 반복이 시작되기까지(초)
const MOVE_REPEAT_RATE := 0.05   # 반복할 때 한 칸 움직이는 간격(초)

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
const ITEM_SWEEP_LINES := 2    # 🧹 아이템이 지우는 내 아래 줄 수
const FAST_MULTIPLIER := 0.3   # ⚡ 아이템을 맞으면 떨어지는 시간이 이만큼으로 줄어듦

# 아이템 목록. 칸에 저장할 때는 1부터 시작하는 번호(ITEM_ORDER에서의 위치 + 1)를 쓴다.
# target: true면 상대에게 쓰는 아이템, false면 나에게 쓰는 아이템.
const ITEM_ORDER := ["garbage", "fast", "fog", "sweep", "shield"]
const ITEMS := {
	"garbage": {"icon": "🧱", "name": "방해 줄", "target": true},
	"fast":    {"icon": "⚡", "name": "빨라져라", "target": true},
	"fog":     {"icon": "🌫", "name": "안개", "target": true},
	"sweep":   {"icon": "🧹", "name": "아래 청소", "target": false},
	"shield":  {"icon": "🛡", "name": "방패", "target": false},
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

# ─── 네트워크 ───
const GAME_PORT := 47000        # 게임 연결(ENet)에 쓰는 포트
const DISCOVERY_PORT := 47001   # 방 자동 찾기(UDP)에 쓰는 포트
const MAX_PLAYERS := 6          # 한 방에 들어올 수 있는 최대 인원(방장 포함)
const DISCOVERY_INTERVAL := 1.0 # 방 찾기 신호를 보내는 간격(초)
const STATE_SEND_INTERVAL := 0.1  # 내 판 모양을 상대에게 보내는 최소 간격(초)
const DISCOVERY_TAG := "WRR1"   # 다른 앱의 신호와 섞이지 않게 붙이는 표시
