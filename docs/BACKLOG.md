# Development Backlog
Shared task queue. The lead-programmer turns design items into small technical tasks here; coders
pull from here. Keep items small and finishable. Each task names an owner agent and an acceptance check.

## Now (milestone: gray-box prototype -> Gate 0)
- [ ] DEVOPS: provision the self-hosted Godot runner on a homelab Docker host; generate Godot export
      presets (Web, Windows); install the GUT test addon (addons/gut). Owner: gamedev-devops-engineer.
      Acceptance: a push to main runs the pipeline green and publishes the web demo URL.
- [ ] DESIGN: fill DESIGN.md one-sentence pitch + core loop. Owner: gamedev-game-designer.
- [ ] PHYSICS: gray-box table - ball + two flippers + outer walls. Owner: gamedev-physics-programmer.
      Acceptance: full-power flip into a wall repeated 100x with ZERO tunneling; continuous_cd on;
      physics tick >= 120 (verified by a GUT test that runs on the runner).
- [ ] GAMEPLAY: launch the ball, detect drain, track ball count, show a basic score.
      Owner: gamedev-gameplay-programmer. Acceptance: 3 balls, score increments on target hit,
      game ends at zero balls.
- [ ] UX: minimal HUD (score + balls remaining) and a launch control. Owner: gamedev-ux-designer.
- [ ] PRODUCER: schedule the Gate 0 fun check once the above land. Owner: gamedev-producer.

## Next (filled in only after Gate 0 passes)
-

## Icebox (deliberately deferred - NOT now)
- multiball, ramps, bumpers, special modes, meta-progression, multiple tables, art pass, audio pass,
  Steam integration, menus beyond the minimum.
