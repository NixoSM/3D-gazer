class_name ToneSynth
extends Node
## Every sound in the game, synthesised at start-up: no audio assets to
## license, and the echo chain can climb a musical scale.
##
## Echo jumps play a glassy marimba note; each consecutive echo climbs a
## D-major pentatonic scale, so a long chain becomes a little melody.
## Replace any generator below with an imported .wav/.ogg when a sound
## designer joins; the public play_* API stays the same.

const MIX_RATE := 32000
const VOICES := 10
## D major pentatonic, in semitones above D4.
const SCALE := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26, 28, 31]
const ROOT_HZ := 293.66

var _notes: Array[AudioStreamWAV] = []
var _sparkles: Array[AudioStreamWAV] = []
var _thud: AudioStreamWAV
var _whoosh: AudioStreamWAV
var _fall: AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0


func _ready() -> void:
	for semitones in SCALE:
		var hz := ROOT_HZ * pow(2.0, semitones / 12.0)
		_notes.append(_render(0.9, func(t: float) -> float: return _glass(t, hz)))
		_sparkles.append(_render(0.6, func(t: float) -> float: return _bell(t, hz * 2.0)))
	_thud = _render(0.18, _thud_sample)
	_whoosh = _render(0.22, _whoosh_sample)
	_fall = _render(0.9, _fall_sample)
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


## Echo jump number `chain` (1, 2, 3 ...). Perfect timing adds a bell overtone.
func play_echo(chain: int, perfect: bool) -> void:
	var index := clampi(chain - 1, 0, _notes.size() - 1)
	_play(_notes[index], -6.0)
	if perfect:
		_play(_sparkles[index], -12.0)


func play_land(strength: float = 1.0) -> void:
	_play(_thud, linear_to_db(clampf(strength, 0.1, 1.0)) - 4.0)


func play_jump(height_fraction: float) -> void:
	_play(_whoosh, -14.0, lerpf(0.85, 1.25, height_fraction))


func play_fall() -> void:
	_play(_fall, -7.0)


## A rising arpeggio for finishing a level.
func play_finish() -> void:
	for i in 6:
		get_tree().create_timer(i * 0.09).timeout.connect(func() -> void: _play(_notes[i * 2], -8.0))
	get_tree().create_timer(0.6).timeout.connect(func() -> void: _play(_sparkles[10], -10.0))


func _play(stream: AudioStreamWAV, volume_db: float, pitch: float = 1.0) -> void:
	if not Settings.sound_enabled:
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


# --- Generators: functions of time (s) returning a sample in [-1, 1] ---------

static func _glass(t: float, hz: float) -> float:
	var envelope := minf(t / 0.003, 1.0) * exp(-t / 0.32)
	var body := sin(TAU * hz * t) + 0.32 * sin(TAU * hz * 2.0 * t) * exp(-t / 0.12)
	var shimmer := 0.12 * sin(TAU * hz * 3.98 * t) * exp(-t / 0.06)
	return (body + shimmer) * envelope * 0.55


static func _bell(t: float, hz: float) -> float:
	var envelope := minf(t / 0.002, 1.0) * exp(-t / 0.18)
	var modulator := sin(TAU * hz * 1.4 * t) * 2.2 * exp(-t / 0.1)
	return sin(TAU * hz * t + modulator) * envelope * 0.4


static func _thud_sample(t: float) -> float:
	var hz := lerpf(95.0, 48.0, minf(t / 0.12, 1.0))
	var envelope := minf(t / 0.002, 1.0) * exp(-t / 0.05)
	var click := (randf() * 2.0 - 1.0) * exp(-t / 0.004) * 0.3
	return sin(TAU * hz * t) * envelope * 0.9 + click


static func _whoosh_sample(t: float) -> float:
	var envelope := sin(PI * clampf(t / 0.22, 0.0, 1.0))
	return (randf() * 2.0 - 1.0) * envelope * 0.35


static func _fall_sample(t: float) -> float:
	var hz := lerpf(420.0, 70.0, pow(t / 0.9, 0.6))
	var envelope := minf(t / 0.01, 1.0) * (1.0 - t / 0.9)
	return sin(TAU * hz * t + 0.6 * sin(TAU * 7.0 * t)) * envelope * 0.5


## Renders a generator into a 16-bit mono stream.
static func _render(seconds: float, generator: Callable) -> AudioStreamWAV:
	var count := int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed := 0.0
	for i in count:
		var sample: float = generator.call(float(i) / MIX_RATE)
		# One-pole low-pass keeps noise-based sounds soft.
		smoothed = lerpf(smoothed, sample, 0.35)
		data.encode_s16(i * 2, int(clampf(smoothed, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
