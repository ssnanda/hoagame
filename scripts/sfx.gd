extends Node
## Autoload: small procedural sounds so the game has audio without asset files.
## Uses the ambient audio session on iOS, so the silent switch is respected.

const RATE := 22050

var _players: Array = []
var _bank: Dictionary = {}
var _music: AudioStreamPlayer


func _ready() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_bank = {
		"tap": _tone([880.0], 0.05, 0.35),
		"notify": _tone([660.0, 880.0], 0.16, 0.4),
		"good": _tone([523.0, 659.0, 784.0], 0.28, 0.4),
		"bad": _tone([330.0, 262.0], 0.3, 0.4),
		"shutter": _noise(0.07),
		"step": _noise(0.03, 0.18),
	}
	_music = AudioStreamPlayer.new()
	_music.stream = _pad()
	_music.volume_db = -22.0
	add_child(_music)
	apply_settings()


func apply_settings() -> void:
	if Settings.music and not _music.playing:
		_music.play()
	elif not Settings.music:
		_music.stop()


func play(name: String) -> void:
	if not Settings.sound or not _bank.has(name):
		return
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = _bank[name]
			p.play()
			return


func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav


func _tone(freqs: Array, seconds: float, volume: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var step := int(float(i) / float(n) * freqs.size())
		var f: float = freqs[mini(step, freqs.size() - 1)]
		var env := minf(1.0, float(i) / 200.0) * (1.0 - float(i) / n)
		s[i] = sin(TAU * f * t) * env * volume
	return _wav(s)


func _noise(seconds: float, volume := 0.3) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		s[i] = rng.randf_range(-1.0, 1.0) * (1.0 - float(i) / n) * volume
	return _wav(s)


## A quiet suburban chord pad that loops without a click.
func _pad() -> AudioStreamWAV:
	var seconds := 6.0
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * 220.0 * t) + sin(TAU * 277.18 * t) * 0.8 + sin(TAU * 329.63 * t) * 0.7
		s[i] = v * 0.08 * (0.75 + 0.25 * sin(TAU * t / seconds))
	return _wav(s, true)
