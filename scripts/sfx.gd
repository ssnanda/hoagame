extends Node
## Autoload: small procedural sounds so the game has audio without asset files.
## Uses the ambient audio session on iOS, so the silent switch is respected.

const RATE := 22050

var _players: Array = []
var _bank: Dictionary = {}
var _music: AudioStreamPlayer
var _mood := "calm"
var _pads: Dictionary = {}
var _mood_tween: Tween
var _loops: Dictionary = {}
const LOOP_DB := {"hum": -20.0, "traffic": -22.0, "blower": -20.0, "sprinkler": -24.0, "murmur": -23.0, "rain": -24.0, "wind": -26.0}


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
		"bark": _bark(),
		"chirp": _chirp(),
		"thunder": _thunder(),
		"door": _door(),
	}
	var loop_banks := {"hum": _periodic([92.0, 184.0, 276.0], [1.0, 0.5, 0.25], 1.0), "traffic": _rumble(),
			"blower": _buzz(), "sprinkler": _sprinkler(), "murmur": _murmur(), "rain": _rain(), "wind": _wind()}
	for key in loop_banks:
		var p := AudioStreamPlayer.new()
		p.stream = loop_banks[key]
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_loops[key] = p
	_music = AudioStreamPlayer.new()
	_pads = {"calm": _pad(), "tense": _pad_tense(), "absurd": _pad_absurd(), "triumph": _pad_triumph()}
	_music.stream = _pads.calm
	_music.volume_db = -22.0
	add_child(_music)
	apply_settings()


## Context music: calm (neighborhood), tense (hearings, meetings), absurd (comic scenes), triumph.
func set_mood(mood: String) -> void:
	if mood == _mood or not _pads.has(mood) or _music == null:
		return
	_mood = mood
	if _mood_tween != null:
		_mood_tween.kill()
	var target := -22.0 + linear_to_db(maxf(Settings.music_volume, 0.01))
	_mood_tween = create_tween()
	_mood_tween.tween_property(_music, "volume_db", -60.0, 0.35)
	_mood_tween.tween_callback(func():
		_music.stream = _pads[_mood]
		if Settings.music:
			_music.play())
	_mood_tween.tween_property(_music, "volume_db", target, 0.6)


func apply_settings() -> void:
	_music.volume_db = -22.0 + linear_to_db(maxf(Settings.music_volume, 0.01))
	if Settings.music and not _music.playing:
		_music.play()
	elif not Settings.music:
		_music.stop()


## Continuous ambience layers: `level` 0..1 fades a loop in and out. All respect the sound setting.
func set_loop(name: String, level: float) -> void:
	if not _loops.has(name):
		return
	var p: AudioStreamPlayer = _loops[name]
	level *= Settings.sfx_volume
	var on := Settings.sound and level > 0.02
	var target := lerpf(-60.0, float(LOOP_DB[name]), clampf(level, 0.0, 1.0)) if on else -80.0
	p.volume_db = lerpf(p.volume_db, target, 0.35)
	if not p.playing:
		p.play()


func play(name: String) -> void:
	if not Settings.sound or not _bank.has(name):
		return
	for p: AudioStreamPlayer in _players:
		if not p.playing:
			p.stream = _bank[name]
			p.volume_db = -8.0 + linear_to_db(maxf(Settings.sfx_volume, 0.01))
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


## A looping sum of whole-hertz sines repeats seamlessly with no click.
func _periodic(freqs: Array, amps: Array, seconds: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += sin(TAU * float(freqs[k]) * t) * float(amps[k])
		s[i] = v * 0.12
	return _wav(s, true)


func _rumble() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var freqs: Array = []
	var amps: Array = []
	for k in 14:
		freqs.append(float(rng.randi_range(28, 150)))
		amps.append(rng.randf_range(0.3, 1.0) * (1.0 - float(k) / 20.0))
	return _periodic(freqs, amps, 2.0)


func _buzz() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var freqs: Array = []
	var amps: Array = []
	for k in 18:
		freqs.append(float(rng.randi_range(110, 700)))
		amps.append(rng.randf_range(0.2, 1.0))
	return _periodic(freqs, amps, 1.0)


func _murmur() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var freqs: Array = []
	var amps: Array = []
	for k in 16:
		freqs.append(float(rng.randi_range(90, 420)))
		amps.append(rng.randf_range(0.2, 0.8))
	return _periodic(freqs, amps, 4.0)


func _sprinkler() -> AudioStreamWAV:
	var seconds := 1.2
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in n:
		var gate := clampf(sin(PI * float(i) / n * 3.0), 0.0, 1.0) if i < n * 2 / 3 else 0.0
		s[i] = rng.randf_range(-1.0, 1.0) * gate * 0.25
	return _wav(s, true)


func _bark() -> AudioStreamWAV:
	var n := int(RATE * 0.36)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var burst := 0.0
		for start in [0.0, 0.17]:
			var local := t - float(start)
			if local >= 0.0 and local < 0.1:
				burst += sin(TAU * (420.0 - 600.0 * local) * local) * (1.0 - local / 0.1) + sin(TAU * 840.0 * local) * 0.3 * (1.0 - local / 0.1)
		s[i] = burst * 0.4
	return _wav(s)


func _chirp() -> AudioStreamWAV:
	var n := int(RATE * 0.14)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / n
		var f := 2600.0 + 1100.0 * t
		s[i] = sin(TAU * f * float(i) / RATE) * sin(PI * t) * 0.25
	return _wav(s)


func _rain() -> AudioStreamWAV:
	var n := int(RATE * 1.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var last := 0.0
	for i in n:
		last = lerpf(last, rng.randf_range(-1.0, 1.0), 0.55)   # softened hiss
		s[i] = last * 0.3
	return _wav(s, true)


func _wind() -> AudioStreamWAV:
	var n := int(RATE * 3.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var last := 0.0
	for i in n:
		last = lerpf(last, rng.randf_range(-1.0, 1.0), 0.06)
		var swell := 0.55 + 0.45 * sin(TAU * float(i) / n)   # loops cleanly: one swell per cycle
		s[i] = last * swell * 1.3
	return _wav(s, true)


func _thunder() -> AudioStreamWAV:
	var n := int(RATE * 1.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var last := 0.0
	for i in n:
		var t := float(i) / n
		last = lerpf(last, rng.randf_range(-1.0, 1.0), 0.04)
		s[i] = last * pow(1.0 - t, 1.6) * 1.8 * (1.0 if t > 0.03 else t / 0.03)
	return _wav(s)


func _door() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var knock := 0.0
		for start in [0.0, 0.1]:
			var local := t - float(start)
			if local >= 0.0 and local < 0.08:
				knock += sin(TAU * 140.0 * local) * exp(-local * 60.0)
		s[i] = knock * 0.6
	return _wav(s)


func _chord_pad(freqs: Array, amps: Array, seconds: float, trem_hz: float, vib: float) -> AudioStreamWAV:
	var n := int(RATE * seconds)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			var f: float = freqs[k]
			v += sin(TAU * f * t + vib * sin(TAU * 4.0 * t)) * float(amps[k])
		# Whole-number tremolo rate over the loop length keeps the loop seamless.
		s[i] = v * 0.08 * (0.8 + 0.2 * sin(TAU * trem_hz * t))
	return _wav(s, true)


func _pad_tense() -> AudioStreamWAV:
	return _chord_pad([164.0, 196.0, 233.0, 98.0], [0.9, 0.8, 0.6, 0.7], 6.0, 0.5, 0.0)


func _pad_absurd() -> AudioStreamWAV:
	return _chord_pad([261.0, 329.0, 392.0, 523.0], [0.7, 0.7, 0.6, 0.4], 6.0, 2.0, 0.6)


func _pad_triumph() -> AudioStreamWAV:
	return _chord_pad([261.0, 329.0, 392.0, 523.0, 659.0], [0.8, 0.8, 0.7, 0.5, 0.3], 6.0, 0.5, 0.0)
