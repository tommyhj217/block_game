# 프로젝트: 와르르 블록 대전

같은 핫스팟/와이파이에 연결한 안드로이드 폰끼리 하는 낙하 블록 대전 게임. (고양이 마을과는 별도 앱)

## 기본 정보
- 엔진: Godot 4.7, 언어: GDScript
- 개발자: Python 경험만 있는 초보 개발자 → 코드에 **한국어 주석을 충분히** 단다. Python과 다른 GDScript 문법이 처음 나오면 짧게 설명한다.
- 플랫폼: Android 폰, 세로 화면, 터치 조작. APK를 폰에 직접 설치한다.
- 이름과 모습은 이 게임만의 것으로 만든다. (다른 유명 게임의 이름·그림·색 구성을 베끼지 않는다)

## 구조
- `scripts/config.gd` (`Config`): 모든 설정값(판 크기, 속도, 방해 줄 표, 아이템, 포트). 숫자는 여기서만 바꾼다.
- `scripts/board.gd` (`Board`): 판 규칙만. 칸 값 = 색(아래 4비트) + 아이템 번호×16. 7개씩 섞은 주머니로 블록을 뽑는다.
- `scripts/board_view.gd` (`BoardView`): 칸 값 배열을 그린다. 내 판·상대 판 공통. 안개·탈락·목표·방패 표시.
- `scripts/game.gd`: 게임 화면. 중력·굳히기·조작(여러 손가락 터치를 `_input`에서 직접 처리)·공격·아이템·승패. 화면 요소는 720x1280 `stage` 안에 놓고 가운데 정렬.
  - 버튼 4개 ◀ ▶ ↻ ▼. ▼는 ◀ ▶ 와 같은 규칙: 한 번 = 한 칸, 꾹 = 쭉(`SOFT_DROP_DELAY` 뒤부터).
    바닥까지 쾅(되돌릴 수 없음)은 ▼ 톡톡 두 번(`DOUBLE_TAP_TIME`) 또는 판을 아래로 휙(`SWIPE_*`)으로만.
    첫 번째 톡 뒤에는 ▼ 그림이 금색 ⤓로 바뀌어 "한 번 더 = 쾅"을 알려 준다. 쾅 직후 `DROP_COOLDOWN` 동안 ▼ 무시,
    ▼를 누른 채 새 블록이 나오면 손을 뗐다 다시 눌러야 내려간다.
  - 떨어질 자리 미리 보기는 꺼 둠(`GHOST_ENABLED`). 줄 레벨 + `SECONDS_PER_LEVEL`초마다 레벨이 올라 빨라진다.
- `scripts/fx.gd` (`Fx`): 손맛 연출 층(조각 튀기, 번쩍임, 떠오르는 글자, 날아가는 공). 흔들림은 game.gd가 내 판 위치를 흔든다. 진동은 폰에서만.
- `scripts/sfx.gd` (autoload `Sfx`): 효과음을 처음 켤 때 코드로 합성한다. `assets/sounds/<이름>.wav|.ogg`가 있으면 그 파일을 쓴다. 이름: move, rotate, drop, clear1~4, item_get, item_use, send, hit, block, level, win, lose, danger.
- `scripts/lobby.gd`: 이름, 방 만들기, 방 찾기(자동 + 번호 입력), 혼자 연습.
- `scripts/net.gd` (autoload `Net`): ENet 연결(방장 = 서버, 아이디 1). 방 찾기는 손님이 UDP `FIND`를 브로드캐스트하고 방장이 `ROOM`으로 답장. 게임 중에는 각자 자기 판을 계산하고 판 모양(`_state`, 0.1초 간격 + 1초마다), 공격(`_attack`), 탈락(`_out`)만 주고받는다.

## 숨은그림 찾기 (성인 난이도)
- 잡지 숨은그림·월리를 찾아라 방식: 한 장의 빽빽한 색칠 일러스트 장면 안에 물건을 장면과 같은 선으로 숨긴다.
- 색칠: 소품은 `col(색)`으로 칠하고(`HiddenProps`의 BRIGHT·PASTEL·WOOD·SKIN·HAIR 색 모음), `HiddenPuzzle.fills`에 뒤→앞 순서로 모인다. `HiddenWorld`가 색칠을 먼저 칠하고 그 위에 선을 그린다. 그림자(`shadow`)는 ghost 색칠이라 뒤의 선을 가리지 않는다.
- `scripts/hidden_props.gd` (`HiddenProps`): 장면 소품 선 그림(아이들, 동물, 책장, 책상, 의자, 화분, 상자, 책, 벽 장식…). 소품마다 "채우기(종이색, 뒤를 가림) + 선". 숨길 물건과 같은 모양의 소품은 넣지 않는다.
- `scripts/hidden_shapes.gd` (`HiddenShapes`): 숨길 물건 33개의 선 그림(-0.5~0.5 좌표)과 한글 이름.
- `scripts/hidden_puzzle.gd` (`HiddenPuzzle`): seed + 단계로 장면을 만든다(같은 seed면 같은 그림 → 대결에서 모두 같은 그림). 벽 → 바닥 납작한 것 → 서 있는 것 순서로 그리고, 3px 칸 가림 계산으로 앞 그림 뒤의 선을 지운다(`_flatten`). 물건은 후보 48개 중 윤곽선이 장면 선과 맞닿는 비율(`_alignment`)이 단계의 `camo`에 맞는 자리에 숨긴다. `clear` 확률로 물건 안쪽 장면 선을 지운다.
- `scripts/hidden_world.gd` (`HiddenWorld`): 그림을 그린다. 장면 선과 물건 선은 같은 색(`HIDDEN_INK`)·굵기. 확대·이동은 노드 scale/position으로 해서 다시 그리지 않는다. `scripts/shape_icon.gd`는 찾을 목록 칸의 물건 그림.
- `scripts/hidden_game.gd`: 한 손가락 끌기 = 이동, 두 손가락 = 확대(PC는 휠), 톡 = 찾기. 엉뚱한 곳을 누르면 잠깐 못 누름(+혼자 하기는 시간 벌칙). 💡 힌트는 근처 동그라미만 보여 줌. 시작 전 3·2·1.
- 혼자 하기(오락실 방식): 50단계. 난이도는 `Config.HIDDEN_STAGE_FIRST` → `HIDDEN_STAGE_LAST` 사이를 단계만큼 섞는다(`HiddenPuzzle.stage_settings`). 제한 시간(시간 막대), 하트 3개(실수하면 하나 줄어듦), 점수(찾기 + 연속 + 남은 시간·하트 보너스). 단계(`[hidden] level`)와 최고 총점(`best_score`)을 `user://settings.cfg`에 저장, 이어서 하는 총점은 `Net.hidden_run_score`.
- 장면 4종: 우주 낙서(`_space`, 흑백 선 그림. 낙서를 겹치지 않게 흩뿌리고 물건은 작게, 빈 곳에 고르게 놓음 — `s["free"]`), 교실(`_room`), 공원(`_park`), 넣어 둔 그림 파일(`_image_scene`). `assets/scenes/`에 png·jpg를 넣으면 그림의 어두운 선·색 경계를 선 자리로 읽어 그 위에 물건을 숨긴다(방법은 `assets/scenes/README.txt`).
- 대결: `Net.start_match("hidden")`. 찾을 때마다 `Net.send_score`, 방장이 처음 다 찾은 사람을 `declare_winner`로 정함. 🏠로 나가면 점수 -1(그만둠).
- `Net.match_mode`("blocks"/"hidden")로 어느 화면을 열지 정한다.

## 대전 규칙
- 한 번에 지운 줄 → 방해 줄: `Config.GARBAGE_FOR_LINES` (2줄→1, 3줄→2, 4줄→4). 받을 방해 줄이 있으면 먼저 상쇄하고, 줄을 못 지우고 굳으면 아래에서 올라온다.
- 아이템은 블록 칸에 붙어 나오고(`ITEM_CHANCE`, 종류별 `weight`), 그 줄을 지우면 얻는다(최대 3개).
  - 상대에게: 🧱 방해 줄 3개, ⚡ 빨라져라, 🌫 안개, 🦝 훔치기(상대 첫 아이템을 가져옴, 답장은 `gift` 공격), 💥 모두 공격(모든 상대에게 2줄)
  - 나에게: 🧹 아래 2줄 청소, 🛡 방패, 🧲 끌어내리기(모든 칸이 떨어져 구멍을 메우고 꽉 찬 줄은 지워져 공격도 됨), 🎁 막대 선물(다음 블록 3개가 막대)
  - 혼자 연습에서는 나에게 쓰는 아이템만 나온다.
- 공격 목표는 자동(살아 있는 상대 중 무작위). 상대 판을 누르면 그 상대로 고정, 다시 누르면 자동.
- 마지막까지 남은 사람이 승리. 방장은 "한 판 더"로 바로 다시 시작한다.

## 테스트 방법
Godot: `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`
- 스크립트 오류 확인: `--headless --path . --import`
- 규칙 테스트: `--headless --path . --script <테스트.gd>` (테스트 스크립트는 프로젝트 밖에 둔다)
- 대전 테스트: 같은 PC에서 창 두 개를 띄운다(`--script <테스트.gd> -- host`, `-- guest`). 방장이 방 찾기 포트를 열고, 손님이 127.0.0.1과 망 브로드캐스트로 찾는다.
- 화면 확인: `--path . --resolution 720x1280 --script <캡처.gd>`

## APK 만들기
- `--headless --path . --export-debug "Android" build/block_battle.apk` (`build/`는 git에서 무시)
- 패키지 이름 `com.parks.blockbattle`, 디버그 키 `%APPDATA%\Godot\keystores\debug.keystore`
- 권한: 인터넷, 네트워크 상태, 와이파이 상태, 멀티캐스트(방 찾기), 진동
