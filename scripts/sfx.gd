# 효과음 담당 (autoload 이름: Sfx). 어디서나 `Sfx.play("drop")`처럼 부른다.
# 소리 파일 없이 처음 켤 때 코드로 짧은 소리를 만들어 둔다(합성).
# 나중에 `assets/sounds/<이름>.wav` (또는 .ogg) 파일을 넣으면 만든 소리 대신 그 파일을 쓴다.
extends Node

const RATE := 22050                     # 1초에 몇 개의 소리 값을 쓰는지 (샘플레이트)
const FILE_DIR := "res://assets/sounds/"
const PLAYER_COUNT := 8                 # 동시에 날 수 있는 소리 개수

var enabled := true
var _streams := {}                      # 소리 이름 → 소리 데이터
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0


func _ready() -> void:
	for i in range(PLAYER_COUNT):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_all()


# 소리를 낸다. pitch: 1보다 크면 높게, 작으면 낮게. volume_db: 0이 기본, 음수면 작게.
func play(sound_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not enabled or not _streams.has(sound_name):
		return
	# 쉬고 있는 재생기를 찾고, 없으면 돌아가며 쓴다
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _players[_next_player]
		_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[sound_name]
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


# ─── 소리 만들기 ───

func _build_all() -> void:
	var recipes := {
		# 이동: 아주 짧고 작은 톡
		"move": _tone(900, 900, 0.03, "tri", 0.12),
		# 돌리기: 살짝 올라가는 소리
		"rotate": _tone(600, 950, 0.05, "tri", 0.16),
		# 쾅 떨어뜨리기: 낮은 쿵 + 짧은 잡음
		"drop": _mix([_tone(170, 55, 0.14, "sine", 0.55), _tone(0, 0, 0.05, "noise", 0.12)]),
		# 줄 지우기: 지운 줄 수만큼 음이 올라가는 짧은 멜로디
		"clear1": _notes([660], 0.09, 0.3),
		"clear2": _notes([660, 880], 0.07, 0.3),
		"clear3": _notes([660, 880, 1100], 0.07, 0.3),
		"clear4": _mix([_notes([523, 659, 784, 1047, 1319], 0.06, 0.32), _tone(0, 0, 0.35, "noise", 0.05)]),
		# 아이템 얻기: 반짝
		"item_get": _seq([_tone(1200, 1800, 0.06, "sine", 0.25), _tone(1800, 2600, 0.08, "sine", 0.2)]),
		# 아이템 쓰기: 휘익
		"item_use": _tone(300, 1200, 0.18, "square", 0.1),
		# 공격 보내기: 슝
		"send": _tone(1000, 350, 0.16, "square", 0.1),
		# 공격 맞음: 낮은 쿵
		"hit": _mix([_tone(130, 45, 0.28, "sine", 0.6), _tone(0, 0, 0.12, "noise", 0.15)]),
		# 방패로 막음: 띵
		"block": _notes([1500, 1500], 0.05, 0.2),
		# 레벨 오름
		"level": _notes([784, 1047], 0.1, 0.25),
		# 이김 / 짐
		"win": _notes([523, 659, 784, 1047, 1047], 0.12, 0.3),
		"lose": _seq([_tone(440, 330, 0.2, "tri", 0.3), _tone(330, 220, 0.35, "tri", 0.3)]),
		# 위험 경고: 낮은 삐
		"danger": _tone(220, 220, 0.08, "square", 0.06),
	}
	for sound_name in recipes:
		var stream: AudioStream = null
		for ext in [".wav", ".ogg"]:
			if ResourceLoader.exists(FILE_DIR + sound_name + ext):
				stream = load(FILE_DIR + sound_name + ext)
				break
		if stream == null:
			stream = _to_stream(recipes[sound_name])
		_streams[sound_name] = stream


# 소리 하나: 주파수가 f0에서 f1로 바뀌는 duration초짜리 소리.
# wave: "sine"(부드러움), "tri"(조금 또렷함), "square"(삑삑함), "noise"(치익 잡음)
func _tone(f0: float, f1: float, duration: float, wave: String, volume: float) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / n
		var freq := lerpf(f0, f1, t)
		phase += freq / RATE
		var s := 0.0
		match wave:
			"sine":
				s = sin(phase * TAU)
			"tri":
				s = 1.0 - 4.0 * absf(fposmod(phase, 1.0) - 0.5)
			"square":
				s = 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
			"noise":
				s = randf_range(-1.0, 1.0)
		# 소리 크기 모양: 처음 5ms 동안 커지고, 끝으로 갈수록 작아진다 (딱 소리 방지)
		var attack := clampf(float(i) / (0.005 * RATE), 0.0, 1.0)
		var decay := pow(1.0 - t, 1.6)
		out[i] = s * volume * attack * decay
	return out


# 음 여러 개를 차례로 (각 음 길이 step초)
func _notes(freqs: Array, step: float, volume: float) -> PackedFloat32Array:
	var parts := []
	for i in range(freqs.size()):
		var length := step * (2.5 if i == freqs.size() - 1 else 1.3)  # 마지막 음은 길게
		parts.append([i * step, _mix([_tone(freqs[i], freqs[i], length, "sine", volume),
				_tone(freqs[i] * 2, freqs[i] * 2, length, "tri", volume * 0.25)])])
	return _place(parts)


# 소리들을 이어 붙이기
func _seq(list: Array) -> PackedFloat32Array:
	var parts := []
	var at := 0.0
	for s in list:
		parts.append([at, s])
		at += float(s.size()) / RATE
	return _place(parts)


# 소리들을 겹치기 (동시에)
func _mix(list: Array) -> PackedFloat32Array:
	var parts := []
	for s in list:
		parts.append([0.0, s])
	return _place(parts)


# [시작 시간(초), 소리] 목록을 하나의 소리로 합친다
func _place(parts: Array) -> PackedFloat32Array:
	var total := 0
	for p in parts:
		total = maxi(total, int(p[0] * RATE) + p[1].size())
	var out := PackedFloat32Array()
	out.resize(total)
	out.fill(0.0)
	for p in parts:
		var start := int(p[0] * RATE)
		var s: PackedFloat32Array = p[1]
		for i in range(s.size()):
			out[start + i] += s[i]
	return out


# 숫자 배열(-1~1)을 Godot가 재생할 수 있는 16비트 WAV 소리로 바꾼다
func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
