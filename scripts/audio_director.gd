extends Node
## AudioDirector - the ONE node that owns every game sound (SLICE "Kenney baseline COMPLETION",
## FRONT 3). It builds a small pool of AudioStreamPlayer voices from AudioLibrary, exposes stable
## typed slot methods that table.gd connects the EXISTING gameplay signals to, and plays the music
## bed. AUDIO ONLY: it never reads or writes a collider, layer, kick vector, or layout coordinate
## (physics is FROZEN this slice) and invents NO new gameplay signal. It listens to the ones the
## table already emits (bumper kicked, target scored, ball launched, ball drained, score changed)
## and POLLS the existing flipper INPUT ACTIONS (reading input is not a new signal).
##
## SCENE PLACEMENT: table.gd instances ONE AudioDirector as a child of the Table root (see
## table._build_audio) and wires it in table._wire_signals, exactly like GameFlow and the HUD. It is
## NOT an autoload (this project has none; systems live under Table so Table.tscn tests reach them).
##
## VOICE MODEL: one dedicated AudioStreamPlayer per semantic event (AudioLibrary.SFX_EVENTS) plus
## one music player. One voice per event keeps each event's volume independent and means a rapid
## re-trigger restarts only THAT voice (arcade-standard: a second bumper hit re-strikes the bell).
## If the retail polish later needs overlapping tails on the impacts, add a tiny round-robin pool
## behind play_event WITHOUT changing its signature - the public contract holds (see _build_voices).
##
## WEB AUDIO UNLOCK: browsers keep audio muted until the first user gesture. Building the players
## and even calling play() before that gesture does NOT error (it is silently inaudible); the menu
## PLAY click is the natural first gesture, so to the player sound "just starts working" on PLAY.
## Nothing here errors before that unlock - every load is null-guarded (AudioLibrary.load_stream).
##
## HEADLESS: GUT runs with no audio device; the players still instance and is_playing() still flips
## true on play(), so the WIRING is fully testable (a voice exists, its stream is a real loaded
## resource, firing the signal calls play()). Headless CANNOT hear - the audio evidence is the
## wiring test + the event-to-sound table, never a listening claim.
##
## OWNERSHIP: lead-programmer scaffolds + owns the voice pool and the slot contract. The
## gameplay-programmer copies the .ogg files, tunes the mix (AudioLibrary.EVENT_VOLUME_DB), confirms
## the score-blip policy, and adds the UI-click call sites in layout_editor.gd. The test-builder
## fills the wiring tests. HOUSE STYLE: typed GDScript, snake_case, WHY comments, lines <= 100.
##
## MUSIC ON/OFF (Gate 0 play-test follow-up): a player-facing toggle, distinct from set_muted, that
## turns ONLY the music bed off, persisted at user:// so the choice survives a reload/relaunch. See
## set_music_enabled / is_music_enabled and the MUSIC PREFERENCE section near the bottom of this
## file. The play-bar button in layout_editor.gd is the only caller.

## user:// ConfigFile path the music preference is persisted to. user:// is a real file on desktop
## and an IndexedDB-backed virtual filesystem on the web export, so this works unmodified in both.
const MUSIC_CONFIG_PATH: String = "user://audio_settings.cfg"
const MUSIC_CONFIG_SECTION: String = "audio"
const MUSIC_CONFIG_KEY: String = "music_enabled"

## The per-event SFX voices, keyed by AudioLibrary event StringName. Built in _ready. Typed as Node
## values in the Dictionary (GDScript Dictionaries are untyped-valued) but every entry is an
## AudioStreamPlayer; player_for() returns the typed handle.
var _voices: Dictionary = {}

## The single looping music player (the bed). Null until _build_music runs.
var _music: AudioStreamPlayer = null

## True while a ball is actually in play (table.set_play_view drives it). Gates the flipper thwack:
## a flipper keypress in a menu must not thwack, and a test can drive the poll deterministically.
var _gameplay_active: bool = false

## Master mute (e.g. a future options toggle). When true, play_event/start_music are no-ops so the
## table can be silenced without tearing down the voices. Kept simple; no per-bus routing here.
var _muted: bool = false

## Player-facing MUSIC on/off (the play-bar toggle button), distinct from _muted: muting silences
## every voice including impacts, while this gates ONLY the music bed. Defaults true (music plays
## out of the box, matching the existing default); false only after the player explicitly turns it
## off. Loaded from user:// in _ready and persisted on every change - see _load_music_preference /
## _save_music_preference.
var _music_enabled: bool = true

## Last score seen by on_score_changed, so the subtle score blip fires only on an INCREASE (never on
## the score_changed(0) that GameFlow emits at game start / restart). See on_score_changed.
var _last_score: int = 0


func _ready() -> void:
	_load_music_preference()  ## before _build_music so a saved "off" is already in effect
	_build_voices()
	_build_music()


## Build one AudioStreamPlayer per SFX event, cache its stream + mix level once. A missing (not yet
## copied) .ogg leaves stream = null (load_stream is null-guarded); the voice still exists so wiring
## never null-derefs, it is just silent until the file lands.
## TODO(retail polish, optional): if impact tails need to overlap, swap the single player for a
## small round-robin pool behind play_event - do NOT change play_event's signature.
func _build_voices() -> void:
	for event: StringName in AudioLibrary.SFX_EVENTS:
		var player := AudioStreamPlayer.new()
		player.name = "Voice_" + String(event)
		player.stream = AudioLibrary.load_stream(AudioLibrary.stream_path_for(event))
		player.volume_db = AudioLibrary.volume_db_for(event)
		add_child(player)
		_voices[event] = player


## Build the looping music player. The stream loops (set defensively in code in case the .import did
## not carry the loop flag) at the bed level, so it sits under every SFX. Not started here: music
## begins when play starts (set_play_view(true) -> start_music) so the menu is quiet by default.
##
## PROCESS_MODE_ALWAYS on the music player ONLY: opening the menu from play PAUSES the SceneTree
## (layout_editor._enter_menu -> get_tree().paused = true) for the translucent pause overlay. A
## PAUSABLE AudioStreamPlayer stops sounding when the tree is paused, so without this the bed would
## cut out under the overlay - contradicting what set_play_view promises. ALWAYS keeps the bed
## playing under the pause overlay (the intended feel) and is engine-version-robust (explicit, not a
## default we hope for). The SFX voices stay PAUSABLE on purpose: the flipper-thwack poll
## (_physics_process) freezes with the tree and no gameplay event fires while paused, so no SFX
## should sound - only the bed continues.
func _build_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "MusicBed"
	_music.volume_db = AudioLibrary.MUSIC_VOLUME_DB
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)


# --- PUBLIC CONTRACT (STABLE SIGNATURES - tests + table.gd depend on these) -----------------------


## Play the voice bound to `event`. Restarts the voice if it is already playing (arcade re-strike).
## A no-op when muted, when the event is unknown, or when the voice has no stream (file not copied
## yet) - it must never error before the web audio unlock. STABLE SIGNATURE.
func play_event(event: StringName) -> void:
	if _muted:
		return
	var player: AudioStreamPlayer = player_for(event)
	if player == null or player.stream == null:
		return
	player.play()


## Start (or restart) the looping music bed. `bed` selects which loop (defaults to the DESIGN
## recommendation, AudioLibrary.MUSIC_BED_DEFAULT). Idempotent-ish: re-calling with the same bed
## while
## it is already playing does nothing so a re-entry does not stutter the music. A no-op while muted
## OR while the player has turned music off (_music_enabled) - both gates are respected here so
## every caller (set_gameplay_active, set_muted's unmute branch, set_music_enabled) gets the same
## behaviour for free. STABLE SIGNATURE.
func start_music(bed: String = AudioLibrary.MUSIC_BED_DEFAULT) -> void:
	if _muted or not _music_enabled or _music == null:
		return
	var stream: AudioStream = AudioLibrary.load_stream(bed)
	if stream == null:
		return  ## file not copied yet - stay silent, never error
	# Ensure the bed loops even if the import preset did not set it (Ogg Vorbis exposes `loop`).
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var same: bool = _music.stream == stream
	if same and _music.playing:
		return
	_music.stream = stream
	_music.play()


## Stop the music bed (e.g. returning to the menu). Safe if it is already stopped. STABLE SIGNATURE.
func stop_music() -> void:
	if _music != null:
		_music.stop()


## True while the music bed is playing. Test seam + a guard for callers. STABLE SIGNATURE.
func is_music_playing() -> bool:
	return _music != null and _music.playing


## Mute / unmute all audio. Muting also stops the music so the table goes fully quiet; unmuting
## restarts the bed if a ball is in play, so the method is symmetric (mute then unmute mid-play
## returns to the same audible state, never a silent-music limbo where the bed stays dead). STABLE.
func set_muted(muted: bool) -> void:
	_muted = muted
	if muted:
		stop_music()
	elif _gameplay_active:
		start_music()


## Player-facing MUSIC on/off (the play-bar toggle button). Distinct from set_muted: this touches
## ONLY the music bed, never the SFX voices, so turning music off still leaves bumpers/targets/
## flippers/etc audible. OFF stops the bed immediately; ON mirrors set_muted's own unmute branch and
## restarts the bed ONLY while a ball is in play (toggling music on from the main menu should not
## start a bed that set_gameplay_active would otherwise be gating off). The choice is saved to
## user:// immediately so it survives a reload. STABLE SIGNATURE (layout_editor.gd's play-bar toggle
## calls this).
func set_music_enabled(on: bool) -> void:
	_music_enabled = on
	_save_music_preference()
	if on:
		if _gameplay_active:
			start_music()
	else:
		stop_music()


## True while the player has music turned ON (independent of whether the bed is currently sounding -
## e.g. still true while paused at the in-play menu). The play-bar toggle reads this once at build
## time to draw its correct initial on/off state. STABLE SIGNATURE.
func is_music_enabled() -> bool:
	return _music_enabled


## Mark play active/inactive. table.set_play_view drives this: true gates the flipper thwack ON and
## starts the music; false stops the music and gates the thwack OFF. STABLE SIGNATURE.
func set_gameplay_active(active: bool) -> void:
	_gameplay_active = active
	if active:
		start_music()
	else:
		stop_music()


## The AudioStreamPlayer voice for `event`, or null if unknown. Test seam: a wiring test asserts
## player_for(EVENT_BUMPER).stream is a non-null loaded AudioStream and is_playing() after the
## signal
## fires. STABLE SIGNATURE.
func player_for(event: StringName) -> AudioStreamPlayer:
	if _voices.has(event):
		return _voices[event] as AudioStreamPlayer
	return null


# --- SIGNAL SLOTS (table.gd connects the EXISTING gameplay signals to these) ----------------------
# Each slot's parameter list MATCHES the source signal exactly so connect() binds with no adapter.
# Unused args are underscore-prefixed (Godot 4 does not drop them on connect). Each just voices its
# event - the mapping is the DESIGN event-to-sound table, made literal.


## pop_bumper.kicked(direction) -> the bell pop. Fired once per bumper hit (the base class cooldown
## already blocks per-frame farming, so this never machine-guns). STABLE SIGNATURE.
func on_bumper_kicked(_direction: Vector3) -> void:
	play_event(AudioLibrary.EVENT_BUMPER)


## slingshot.kicked(direction) -> the plank snap. Same kicked(Vector3) contract as the bumper, but a
## distinct voice so a sling does not sound like a bumper. STABLE SIGNATURE.
func on_slingshot_kicked(_direction: Vector3) -> void:
	play_event(AudioLibrary.EVENT_SLINGSHOT)


## target.scored(points) -> the tin hit (a metallic voice distinct from the bumper bell). STABLE.
func on_target_scored(_points: int) -> void:
	play_event(AudioLibrary.EVENT_TARGET)


## plunger.ball_launched -> the laser release whoosh. STABLE SIGNATURE.
func on_ball_launched() -> void:
	play_event(AudioLibrary.EVENT_LAUNCH)


## drain.ball_drained (and the OOB failsafe) -> the low loss thud. STABLE SIGNATURE.
func on_ball_drained() -> void:
	play_event(AudioLibrary.EVENT_DRAIN)


## game_flow.score_changed(score) -> the subtle score blip, but ONLY on an INCREASE. GameFlow emits
## score_changed(0) at game start and restart; blipping on those would be a phantom chime, so we
## track the last score and voice only when it rose. A decrease/reset just re-baselines silently.
## TODO(gameplay/qa): confirm this "blip on increase only, kept subtle (EVENT_SCORE mix is well
## under the impacts)" policy reads right on the artifact; the score also drives the bell/tin on the
## same hit, so the blip is meant to LAYER under, not stand alone. STABLE SIGNATURE.
func on_score_changed(score: int) -> void:
	if score > _last_score:
		play_event(AudioLibrary.EVENT_SCORE)
	_last_score = score


## A UI button was pressed. table.play_ui_click forwards here from layout_editor's button handlers.
## `secondary` picks the second click voice (RESET BALL) vs the primary (MENU / PLAY), so the two
## buttons sound distinct. The PLAY click is typically the first-gesture web audio unlock. STABLE.
func on_ui_pressed(secondary: bool = false) -> void:
	if secondary:
		play_event(AudioLibrary.EVENT_UI_SECONDARY)
	else:
		play_event(AudioLibrary.EVENT_UI_PRIMARY)


# --- FLIPPER THWACK (polled, not a signal) --------------------------------------------------------


## Poll the EXISTING flipper input actions and thwack on the just-pressed edge, but only while play
## is active (a flipper keypress in a menu should not thwack). Polling reads input actions the game
## already defines (project.godot: left_flipper, right_flipper) - it invents no gameplay signal, and
## it also catches the touch controls, which drive the SAME actions via Input.action_press
## (layout_editor._handle_play_touch). We poll in _physics_process (not _process) so the thwack
## lands on the same physics frame the flipper drive reads the press (flipper.gd also polls in
## _physics_process too), so cause and effect land on the same frame - no input-to-sound lag.
func _physics_process(_delta: float) -> void:
	if not _gameplay_active:
		return
	if _flipper_action_just_pressed("left_flipper") or _flipper_action_just_pressed("right_flipper"):
		play_event(AudioLibrary.EVENT_FLIPPER)


## True if the action exists AND was just pressed this frame. The has_action guard keeps a headless
## test that has not loaded the input map from erroring.
func _flipper_action_just_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


# --- MUSIC PREFERENCE (persisted at user://, Gate 0 play-test follow-up) -------------------------
# The player's music on/off choice needs to survive a reload (closing and reopening the browser tab,
# or relaunching a desktop build), so it is not just an in-memory flag. ConfigFile at user:// is the
# simplest engine-native key/value store that works the same on every export target: a real file on
# desktop/native, and an IndexedDB-backed virtual filesystem on the web export (Godot handles that
# translation - this code never touches the browser storage APIs directly, unlike layout_editor's
# JavaScriptBridge localStorage calls for the table layout.


## Load the saved music on/off preference from user:// (ConfigFile), called once from _ready before
## the very first possible start_music() call. A missing file (first run, nothing saved yet) or any
## read error (e.g. a web browser blocking storage in private mode) both leave _music_enabled at its
## true default - this must never crash or block _ready, so any non-OK load result is treated as
## "no preference saved" rather than an error to surface.
func _load_music_preference() -> void:
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(MUSIC_CONFIG_PATH)
	if err == OK:
		_music_enabled = bool(cfg.get_value(MUSIC_CONFIG_SECTION, MUSIC_CONFIG_KEY, true))


## Save the current music on/off preference to user:// (ConfigFile). Called every time
## set_music_enabled changes the value. Best-effort: on the web export the write can fail (private
## browsing, storage quota, IndexedDB not yet ready) - a failed save just means the toggle will not
## be remembered next session, which degrades gracefully instead of erroring, so the return Error is
## intentionally not checked further here.
func _save_music_preference() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(MUSIC_CONFIG_SECTION, MUSIC_CONFIG_KEY, _music_enabled)
	cfg.save(MUSIC_CONFIG_PATH)
