class_name AudioLibrary
extends RefCounted
## AudioLibrary - the SINGLE typed source of truth for the table's AUDIO identity (SLICE "Kenney
## baseline COMPLETION", FRONT 3). This is the sound twin of palette.gd (colour) and
## kenney_models.gd
## (mesh): it maps the 12 frozen manifest SFX + 3 music loops to res:// paths, binds each loop EVENT
## to its voice, and records the mix (per-voice volume_db) so the music bed sits UNDER the SFX and
## the
## score blip layers subtly beneath an impact. AUDIO ONLY - nothing here reads or writes a collider,
## a physics layer, a kick vector, or a layout coordinate (physics is FROZEN this slice).
##
## WHY THIS FILE EXISTS: audio_director.gd needs one place to look up "what stream plays for the
## bumper event, and how loud", and the wiring tests need one place to assert every stream is a
## real,
## LFS-tracked, non-null loaded resource. Keeping the paths + mix here (not scattered as literals in
## the director) means a sound swap or a mix tweak is a one-line edit, and the event-to-sound
## contract the DESIGN doc locks lives in code the test can read back.
##
## SOURCE OF THE FILES: the 12 .ogg entries in docs/assets/KENNEY_BASELINE_MANIFEST.json, copied
## UNMODIFIED from the read-only Kenney bundle into assets/kenney/baseline/audio/ (engine-generated
## .import sidecars only, never hand-authored). *.ogg is LFS-tracked repo-wide (.gitattributes); the
## copier verifies each file with `git check-attr filter -- <path>` = "filter: lfs".
##
## COPY MAPPING (bundle basename -> repo filename). SFX keep their basename; the 3 music loops
## de-space to snake_case so no res:// path carries a space:
##   impactBell_heavy_000.ogg   -> impact_bell_heavy.ogg      (bundle: Audio/Impact Sounds/Audio/)
##   impactTin_medium_000.ogg   -> impact_tin_medium.ogg      (bundle: Audio/Impact Sounds/Audio/)
##   impactWood_light_000.ogg   -> impact_wood_light.ogg      (bundle: Audio/Impact Sounds/Audio/)
##   impactPlank_medium_000.ogg -> impact_plank_medium.ogg    (bundle: Audio/Impact Sounds/Audio/)
##   laser1.ogg                 -> laser1.ogg                 (bundle: Audio/Digital Audio/Audio/)
##   lowDown.ogg                -> low_down.ogg               (bundle: Audio/Digital Audio/Audio/)
##   click_001.ogg              -> click_001.ogg             (bundle: Audio/Interface Sounds/Audio/)
##   click_002.ogg              -> click_002.ogg             (bundle: Audio/Interface Sounds/Audio/)
##   highUp.ogg                 -> high_up.ogg                (bundle: Audio/Digital Audio/Audio/)
##   Alpha Dance.ogg            -> music_alpha_dance.ogg      (bundle: Audio/Music Loops/Loops/)
##   Cheerful Annoyance.ogg     -> music_cheerful_annoyance.ogg (bundle: Audio/Music Loops/Loops/)
##   Drumming Sticks.ogg        -> music_drumming_sticks.ogg  (bundle: Audio/Music Loops/Loops/)
##
## OWNERSHIP: lead-programmer owns this module + its contract (paths, event map, mix). The
## gameplay-programmer copies the .ogg files and TUNES the volume_db values on the deployed build;
## the test-builder asserts every stream loads. HOUSE STYLE: typed const, UPPER_SNAKE, lines <= 100.

# --- STREAM PATHS --------------------------------------------------------------------------------
# All under assets/kenney/baseline/audio/. Held as const String so this file parses with ZERO disk
# I/O (load happens at runtime in the director, null-guarded); a missing file never crashes parsing.

const AUDIO_DIR: String = "res://assets/kenney/baseline/audio/"

## SFX (the loop's feedback voices).
const SFX_BUMPER: String = AUDIO_DIR + "impact_bell_heavy.ogg"    ## pop bumper hit (the "pop")
const SFX_TARGET: String = AUDIO_DIR + "impact_tin_medium.ogg"    ## standup target hit (metallic)
const SFX_FLIPPER: String = AUDIO_DIR + "impact_wood_light.ogg"   ## flipper actuation (bat thwack)
const SFX_SLINGSHOT: String = AUDIO_DIR + "impact_plank_medium.ogg"  ## slingshot kick (plank snap)
const SFX_LAUNCH: String = AUDIO_DIR + "laser1.ogg"              ## plunger launch (release whoosh)
const SFX_DRAIN: String = AUDIO_DIR + "low_down.ogg"            ## ball drain (the loss thud)
const SFX_SCORE: String = AUDIO_DIR + "high_up.ogg"            ## score tick (subtle, layers under)
const SFX_UI_PRIMARY: String = AUDIO_DIR + "click_001.ogg"     ## MENU / PLAY press
const SFX_UI_SECONDARY: String = AUDIO_DIR + "click_002.ogg"   ## RESET BALL press

## Music loops (import all three; ONE is the in-game bed). Alpha Dance is the manifest's stated
## primary and the DESIGN recommendation; the other two are swappable beds ready in the library.
const MUSIC_ALPHA_DANCE: String = AUDIO_DIR + "music_alpha_dance.ogg"
const MUSIC_CHEERFUL_ANNOYANCE: String = AUDIO_DIR + "music_cheerful_annoyance.ogg"
const MUSIC_DRUMMING_STICKS: String = AUDIO_DIR + "music_drumming_sticks.ogg"

## The default in-game music bed. start_music() with no argument uses this.
const MUSIC_BED_DEFAULT: String = MUSIC_ALPHA_DANCE

# --- EVENT NAMES (the semantic voices the director owns) -----------------------------------------
# StringName keys so a signal slot can call play_event(&"bumper") with no per-call String alloc.
# One voice per event: an event always plays on the SAME AudioStreamPlayer, so its volume is
# independent and a re-trigger restarts only that voice (arcade-standard; see director doc).

const EVENT_BUMPER: StringName = &"bumper"
const EVENT_TARGET: StringName = &"target"
const EVENT_FLIPPER: StringName = &"flipper"
const EVENT_SLINGSHOT: StringName = &"slingshot"
const EVENT_LAUNCH: StringName = &"launch"
const EVENT_DRAIN: StringName = &"drain"
const EVENT_SCORE: StringName = &"score"
const EVENT_UI_PRIMARY: StringName = &"ui_primary"
const EVENT_UI_SECONDARY: StringName = &"ui_secondary"

## Every SFX event the director builds a voice for, in a stable order (the director iterates this to
## build its player pool; a test iterates it to assert each voice exists with a non-null stream).
const SFX_EVENTS: Array[StringName] = [
	EVENT_BUMPER, EVENT_TARGET, EVENT_FLIPPER, EVENT_SLINGSHOT,
	EVENT_LAUNCH, EVENT_DRAIN, EVENT_SCORE, EVENT_UI_PRIMARY, EVENT_UI_SECONDARY,
]

## EVENT -> stream path. The director loads each once at _ready and caches it on the voice's player.
## Dictionary[StringName, String].
const EVENT_STREAM: Dictionary = {
	EVENT_BUMPER: SFX_BUMPER,
	EVENT_TARGET: SFX_TARGET,
	EVENT_FLIPPER: SFX_FLIPPER,
	EVENT_SLINGSHOT: SFX_SLINGSHOT,
	EVENT_LAUNCH: SFX_LAUNCH,
	EVENT_DRAIN: SFX_DRAIN,
	EVENT_SCORE: SFX_SCORE,
	EVENT_UI_PRIMARY: SFX_UI_PRIMARY,
	EVENT_UI_SECONDARY: SFX_UI_SECONDARY,
}

# --- MIX (per-voice volume_db) -------------------------------------------------------------------
# STARTING values that honour the DESIGN mix hierarchy (impacts loudest, music quietest, score
# subtle). These are the gameplay-programmer/QA's to TUNE on the deployed build (headless cannot
# hear); the CONTRACT the tuning must preserve is the ORDER, documented per line:
#   impacts (bumper/target/sling) are the loudest reward/action voices;
#   flipper/launch/drain sit just under the impacts;
#   score is well under (it layers beneath a bell, never competes);
#   music is the quietest, a bed you notice only when the table goes quiet.
# TODO(gameplay/qa): tune the exact dB on the artifact; keep the documented ordering.

const EVENT_VOLUME_DB: Dictionary = {
	EVENT_BUMPER: 0.0,        ## reward voice, full level
	EVENT_TARGET: 0.0,        ## reward voice, full level
	EVENT_SLINGSHOT: -1.0,    ## action voice, just under the reward
	EVENT_FLIPPER: -5.0,      ## the player's action - present, never louder than the reward
	EVENT_LAUNCH: -2.0,       ## first-win beat
	EVENT_DRAIN: -1.0,        ## the loss - lands clearly
	EVENT_SCORE: -12.0,       ## subtle: layers UNDER an impact, never competes with the bell
	EVENT_UI_PRIMARY: -4.0,   ## a crisp click, not a thud
	EVENT_UI_SECONDARY: -4.0,
}

## The music bed volume. Clearly under every SFX above (the quietest thing on the table).
const MUSIC_VOLUME_DB: float = -16.0

# --- SETS FOR THE STRUCTURAL TESTS ---------------------------------------------------------------

## Every SFX path (the wiring test asserts each loads to a non-null AudioStream and is LFS-tracked).
const ALL_SFX_PATHS: Array[String] = [
	SFX_BUMPER, SFX_TARGET, SFX_FLIPPER, SFX_SLINGSHOT,
	SFX_LAUNCH, SFX_DRAIN, SFX_SCORE, SFX_UI_PRIMARY, SFX_UI_SECONDARY,
]

## Every music path (import all three so a bed swap needs no new copy).
const ALL_MUSIC_PATHS: Array[String] = [
	MUSIC_ALPHA_DANCE, MUSIC_CHEERFUL_ANNOYANCE, MUSIC_DRUMMING_STICKS,
]


## Load the AudioStream at `path`, or null if it is missing / not yet copied. A pure convenience so
## the director and the tests share ONE load path (never a bare load() scattered around). Returns
## null (never throws) so a not-yet-copied file degrades to silence instead of crashing the scene -
## the wiring must not error before the first-gesture web audio unlock.
static func load_stream(path: String) -> AudioStream:
	var res: Resource = load(path)
	if res is AudioStream:
		return res as AudioStream
	return null


## The stream path bound to `event`, or "" for an unknown event. Small typed accessor so callers do
## not index EVENT_STREAM directly (keeps the Dictionary an implementation detail).
static func stream_path_for(event: StringName) -> String:
	if EVENT_STREAM.has(event):
		return String(EVENT_STREAM[event])
	return ""


## The mix level (volume_db) for `event`, or 0.0 if unmapped. Same encapsulation reason as above.
static func volume_db_for(event: StringName) -> float:
	if EVENT_VOLUME_DB.has(event):
		return float(EVENT_VOLUME_DB[event])
	return 0.0
