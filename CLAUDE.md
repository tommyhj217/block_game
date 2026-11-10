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
  - 버튼 4개 ◀ ▶ ↻ ▼. ▼는 `DROP_HOLD_TIME`보다 짧게 누르면 바로 떨어뜨리기, 길게 누르면 누르는 동안 내려가기.
  - 떨어질 자리 미리 보기는 꺼 둠(`GHOST_ENABLED`). 줄 레벨 + `SECONDS_PER_LEVEL`초마다 레벨이 올라 빨라진다.
- `scripts/fx.gd` (`Fx`): 손맛 연출 층(조각 튀기, 번쩍임, 떠오르는 글자, 날아가는 공). 흔들림은 game.gd가 내 판 위치를 흔든다. 진동은 폰에서만.
- `scripts/sfx.gd` (autoload `Sfx`): 효과음을 처음 켤 때 코드로 합성한다. `assets/sounds/<이름>.wav|.ogg`가 있으면 그 파일을 쓴다. 이름: move, rotate, drop, clear1~4, item_get, item_use, send, hit, block, level, win, lose, danger.
- `scripts/lobby.gd`: 이름, 방 만들기, 방 찾기(자동 + 번호 입력), 혼자 연습.
- `scripts/net.gd` (autoload `Net`): ENet 연결(방장 = 서버, 아이디 1). 방 찾기는 손님이 UDP `FIND`를 브로드캐스트하고 방장이 `ROOM`으로 답장. 게임 중에는 각자 자기 판을 계산하고 판 모양(`_state`, 0.1초 간격 + 1초마다), 공격(`_attack`), 탈락(`_out`)만 주고받는다.

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
