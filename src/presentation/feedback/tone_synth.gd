class_name ToneSynth
extends Node
## Every sound in the game, synthesised at start-up: no audio assets to
## license, and the echo chain can climb a musical scale.
##
## A smash lands with a boom and a glassy marimba note; each consecutive
## smash climbs a D-major pentatonic scale, so a chain becomes a little melody.
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
var _coil: AudioStreamWAV
var _dive: AudioStreamWAV
var _boom: AudioStreamWAV
var _crack: AudioStreamWAV
var _boing: AudioStreamWAV
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
	_coil = _render(0.07, _coil_sample)
	_dive = _render(0.16, _dive_sample)
	_boom = _render(0.5, _boom_sample)
	_crack = _render(0.09, _crack_sample, 0.9)
	_boing = _render(0.2, _boing_sample)
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


## The smash's wind-up: a quick rising zip.
func play_coil() -> void:
	_play(_coil, -13.0)


## The dive: a falling whistle.
func play_dive() -> void:
	_play(_dive, -12.0)


## Smash number `chain` (1, 2, 3 ...) hits the floor with `power` in [0, 1]:
## a sub boom, a crack on top, and the chain's note. From the top of the
## arc adds a bell overtone.
func play_smash(chain: int, power: float, top: bool) -> void:
	var index := clampi(chain - 1, 0, _notes.size() - 1)
	_play(_boom, lerpf(-6.0, 0.0, power), lerpf(1.15, 0.9, power))
	_play(_crack, lerpf(-10.0, -4.0, power), lerpf(1.1, 0.95, power))
	_play(_notes[index], -6.0)
	if top:
		_play(_sparkles[index], -11.0)


## The bounce back up.
func play_bounce(height_fraction: float) -> void:
	_play(_boing, -13.0, lerpf(0.9, 1.2, height_fraction))


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


static func _coil_sample(t: float) -> float:
	var hz := lerpf(320.0, 1100.0, t / 0.07)
	var envelope := minf(t / 0.004, 1.0) * (1.0 - t / 0.07)
	return sin(TAU * hz * t) * envelope * 0.45


static func _dive_sample(t: float) -> float:
	var u := t / 0.16
	var hz := lerpf(1400.0, 260.0, u * u)
	var envelope := sin(PI * clampf(u, 0.0, 1.0)) * (0.4 + 0.6 * u)
	return (sin(TAU * hz * t) * 0.35 + (randf() * 2.0 - 1.0) * 0.3) * envelope


## A deep, short boom: the pitch drops as it decays, like a kick drum.
static func _boom_sample(t: float) -> float:
	var phase := TAU * (38.0 * t + 70.0 * 0.045 * (1.0 - exp(-t / 0.045)))
	var envelope := minf(t / 0.0015, 1.0) * exp(-t / 0.16)
	var body := sin(phase) + 0.25 * sin(phase * 2.0) * exp(-t / 0.05)
	return clampf(body * envelope * 1.3, -1.0, 1.0)


## Gritty noise with a fast decay: the floor cracking.
static func _crack_sample(t: float) -> float:
	var envelope := minf(t / 0.001, 1.0) * exp(-t / 0.022)
	var grit := signf(randf() - 0.5) * (0.6 + 0.4 * randf())
	return grit * envelope * 0.7


static func _boing_sample(t: float) -> float:
	var hz := lerpf(170.0, 560.0, pow(t / 0.2, 0.5))
	var envelope := minf(t / 0.003, 1.0) * exp(-t / 0.08)
	return sin(TAU * hz * t + 0.8 * sin(TAU * 31.0 * t)) * envelope * 0.5


## Renders a generator into a 16-bit mono stream. `smoothing` is the
## one-pole low-pass amount (1 = none).
static func _render(seconds: float, generator: Callable, smoothing: float = 0.35) -> AudioStreamWAV:
	var count := int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smoothed := 0.0
	for i in count:
		var sample: float = generator.call(float(i) / MIX_RATE)
		# One-pole low-pass keeps noise-based sounds soft.
		smoothed = lerpf(smoothed, sample, smoothing)
		data.encode_s16(i * 2, int(clampf(smoothed, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
