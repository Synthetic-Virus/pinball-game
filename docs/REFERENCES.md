# Design References - the games we are recreating
Owner: gamedev-game-designer (seeded 2026-06-17 from Andrew's inspiration set). These are the
childhood favorites this project reimagines: modern UI/UX, modern features, and SMOOTH HIGH FPS.
The originals ran poorly, and that frame-rate pain is the single experience flaw we most want to fix.

Reference archives (Win3x / DOS abandonware, kept for study, NOT shipped):
C:\Users\aalex\Downloads\  (3-D Ultra Pinball x4, Hyper 3-D Pinball, Pinball 2000)

## The heart: Sierra / Dynamix "3-D Ultra Pinball" series (mid-late 1990s)
The defining inspiration. What made them special and worth recreating:
- MULTI-BOARD TABLES: the signature mechanic. A table spans several connected boards/screens, and
  ramps shoot the ball between boards. This is what set them apart from single-table simulations and
  is the number-one thing to preserve.
- THEMED WORLDS with characters, story, and MISSIONS - not just a high-score chase. Each title a
  distinct world:
  - 3-D Ultra Pinball (1995): sci-fi / space "Ultra" theme (folder 3DUP).
  - 3-D Ultra Pinball: Creep Night (1996): horror / Halloween, monsters, haunted house (3DUPCN).
  - 3-D Ultra Pinball: The Lost Continent (1997): lost-world adventure, dinosaurs, Atlantis (3DUPLC).
  - 3-D Ultra Pinball: Thrillride (2000): amusement park - you BUILD rides and coasters as you play.
- OBJECTIVE-DRIVEN: complete goals, trigger set-piece events, play mini-games, build/unlock things.
  Closer to "a video game with pinball physics" than to a pure simulation.
- LOOK: pre-rendered, colorful, cartoonish, family-friendly, vibrant.

## Also referenced
- Hyper 3-D Pinball (1995, DOS): multiple themed, texture-mapped 3D-rendered tables; more arcade.
- Pinball 2000 (DOS, ~592K): small release - IDENTIFY it exactly before leaning on it. Note: the
  famous "Pinball 2000" was Williams' late-90s ARCADE platform (Revenge from Mars, Star Wars Ep.1)
  that projected video onto a real playfield; this small DOS file is likely a different title.

## What to KEEP (the soul)
1. Multi-board tables connected by ramps - the signature.
2. A strong THEME with characters and a sense of place.
3. Mission/objective structure and mini-games, so progress feels like a journey, not just a number.
4. Approachable, vibrant, family-friendly charm.

## What to MODERNIZE (the reason for the remake)
1. SMOOTH HIGH FRAME RATE - the headline fix. The originals ran badly. This ties directly to the
   project's physics-first mandate (120hz+ tick, continuous_cd, zero tunneling). See .claude/CLAUDE.md.
2. Modern UI/UX: clean readable HUD, clear objective tracking, fluid menus, widescreen, scaling.
3. Modern features to weigh: Steam achievements + leaderboards, controller support, accessibility
   (remappable input, colorblind-safe, readable text), daily/online challenges, a progression layer.
4. Modern 3D presentation while keeping the playfield readable and legible.

## Intellectual property (this is a COMMERCIAL Steam release - read carefully)
Recreate the EXPERIENCE and MECHANICS (multi-board, themed, mission pinball), NOT the copyrighted
names, themes, characters, art, or audio of these games. Original world, original IP throughout.
gamedev-product-strategist + gamedev-producer own this boundary.

## Prior-art consulted for the "real pinball furniture" slice (2026-06-19)
Consulted by the design + physics agents BEFORE building, so we adopt patterns rather than reinvent.
Recorded here per the slice mandate. Mechanics/patterns are not copyrightable; we write original code.
- Devlog video (Godot pinball): https://www.youtube.com/watch?v=oAkSuSY1MaU
- r/godot "anyone worked on a pinball game in Godot":
  https://www.reddit.com/r/godot/comments/1aw79u9/has_anyone_worked_on_a_pinball_game_in_godot/
- r/godot "Professor Pinball's Castle (OPEN SOURCE)":
  https://www.reddit.com/r/godot/comments/df09i5/professor_pinballs_castle_an_opensource_pinball/
  Source: dbisdorf/professor-pinball (MIT, Godot 3, 2D, complete game).
- r/godot "pinball game work in progress":
  https://www.reddit.com/r/godot/comments/pshuaw/hi_ive_been_working_on_a_pinball_game_this_is_the/
- Mission Pinball "using CAD to test/plan shots" (missionpinball.org): the discipline of validating
  shot geometry deterministically (is the shot geometrically makeable from the flipper tip?) rather
  than eyeballing. Drives the table_viz.py shot-validation extension in this slice.

### Key finding from mining the open-source repos (design-relevant)
Both open-source pinball references (GandalfDG/pinhead Kicker.gd + pop_bumper.gd, and
dbisdorf/professor-pinball Bumper.gd + Kicker.gd) do NOT apply a coded impulse for the bumper/sling
kick. Their contact handlers are SIGNAL-ONLY (emit triggered/score, play a sound); the visible
rebound comes from the body's PhysicsMaterial restitution (a bouncy bumper) plus the ball's incoming
speed. That is the simplest pattern, but it is a PASSIVE bounce: a ball that crawls into a bumper
crawls back out, which is not the "bell thingy that contracts to shoot the ball away" the developer
described. DESIGN DECISION for our slice (see DESIGN.md): use an ACTIVE kick (a fixed outward impulse
on contact) so even a slow ball is fired away with authority, layered on top of CCD-safe solid
geometry. This is a deliberate divergence from the prior art toward the developer's stated feel.

## Open questions for gamedev-game-designer
- An original theme/world that evokes the same wonder (IP-safe), not a clone of any title above.
- v1 scope: ONE multi-board table done excellently (producer's cut-scope gate) before any others.
- How "multi-board" is realized in Godot: separate scenes/cameras, seamless ball hand-off, framing.
