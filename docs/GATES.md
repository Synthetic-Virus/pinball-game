# Kill / Keep Gates
Owner: gamedev-producer. Pre-committed checkpoints that decide whether the project continues.
Scrapping at an early gate is a WIN (a cheap lesson), not a failure. Record each gate, dated, here.

## Gate 0 - Fun Gate (after the gray-box prototype)
Is ONE ball fun with no art, no audio, no progression - just flippers, a ball, and targets?
Keep if you replay it without being told to. Scrap or pivot if "it will be fun once X is added."
Status: NOT REACHED.

## Gate 1 - Stranger Gate (early playtest, via the homelab demo URL)
Does someone who is not you enjoy it without you narrating how it is meant to be fun?
Keep if they play past politeness and ask a real question. Scrap if you must explain the fun.
Status: NOT REACHED.

## Gate 2 - Slice Gate (one table fully polished)
With one table polished (art, audio, feel), is it genuinely compelling, AND does the time math to
finish the whole game not end in retirement?
Status: NOT REACHED.

## Gate 3 - Market Gate (Steam page up EARLY, during production)
Do strangers wishlist it? Keep if wishlists accumulate from trailers and posts. Rethink if you show
it repeatedly and nobody bites. Better to learn this at month 3 than month 30.
Status: NOT REACHED.

## Gate 4 - Finish Gate
Can this be finished with real available time, or does "done" recede every month?
Keep if scope is cuttable to a finishable core. Scrap or cut hard if done keeps moving.
Status: NOT REACHED.

## Gate log (producer rulings)
- 2026-06-18 SEND_BACK - SLICE "Core 3D table rebuild on Jolt": scope held (no creep; cut list intact)
  and architecture approved by the board, but the two physics-first gates this slice exists to prove are
  NOT asserted by CI: (1) test_ball_tunneling stress loop runs a hand-built body, not the real Ball.tscn;
  (2) test_flipper_momentum still pending() despite the force_energized() hook existing. Required to clear:
  repoint the tunneling stress test at real Ball.tscn, replace the momentum pending() stubs with real
  force_energized() assertions (full swing >= ~1.5x tap; ~50 ms snap), and produce the runner log showing
  GUT green (not skipped/pending). UX/QA polish items (nudge, HUD font, overlap, colorblind, extra lock
  tests, stale comments) are DEFERRED to BACKLOG Next / QA_BACKLOG and must NOT block resubmission. Gate 0
  NOT scheduled until the two CI gates are green on the runner.

- 2026-06-19 SEND_BACK - SLICE "Make the core interactions physics-based": scope held (no creep; cut
  list intact - 3 targets, flat 100, plunger contract preserved) and the architecture/feel/test-DESIGN
  is approved by the board. BLOCKED on DELIVERY/PROVENANCE, the same gate the prior slice tripped on:
  (1) the polish-pass fixes are UNCOMMITTED (git working tree only) - committed HEAD 97d4327 is the
  known-broken pre-polish state (table.gd:237 still plunger.position = BALL_START -> off-table face;
  table_geometry.gd build() omits _build_lane_pocket -> ball exits the lane); (2) ZERO CI runs on
  slice/core-interactions-physics and NO PR; (3) test_table_integration.gd is untracked. "Green on the
  runner (the artifact, not a doc claim)" is not just unproven, it is provably FALSE against committed
  HEAD. Required to clear: commit + push the polish pass, open the PR, and produce the runner log showing
  GUT GREEN (the integration + plunger-launch + target + no-tunneling suites actually executed, not
  pending/skipped). Then re-derive green from the runner artifact, not the BACKLOG notes. House-style
  line-length nits (plunger.gd:306-307, table_geometry.gd long comments) and the stale 120 Hz comment in
  test_plunger.gd should be wrapped/corrected in the same push but do not by themselves block. UX items
  (re-issue the HOLD LAUNCH prompt on every arm; name the actual restart key; colorblind-safe meter;
  HUD font size) are real and IN SCOPE for this slice's gray-box-clarity intent - fold them in before the
  PR rather than deferring, since Gate 0 is the next stop and a player who cannot tell how to launch ball 2
  fails the fun check on a control problem, not a fun problem. Glancing-shot target stress and off-axis
  tunneling -> QA_BACKLOG (do NOT block resubmission). Gate 0 NOT scheduled until the suite is green on
  the runner.

- 2026-06-19 SEND_BACK - SLICE "Table reshape + playtest fixes": SCOPE HELD (five fixes only, no new
  element types/art/length change - the board's design-intent and architecture lenses both APPROVE; the
  cut list is intact). BLOCKED ON THE DELIVERY GATE - the same gate the two prior slices tripped on.
  The runner artifact is RED, not a doc claim: CI run 27858434688 on pushed sha 73f8fc7 (PR #10) =
  FAILURE, 143 tests / 137 passing / 6 FAILING. A PASS requires ci_conclusion == success; this is a
  hard fail. The headline fix is DEAD in CI. Required to clear (re-derive GREEN from a fresh runner run,
  not the BACKLOG):
    1. test_plunger_launch.gd (5 reds) - the #1 fix, the launch, imparts ~0 velocity. Root cause is
       seating geometry, not the impulse design: the settled ball drifts under tilt to z~24.08 (against
       the lane pocket), DOWN-table of PLUNGER_REST_POS.z=24.0, so ball.is_touching(_face) is never true
       and no impulse fires. Re-derive PLUNGER_REST_POS.z / BALL_START.z so the settled ball CONTACTS the
       face (and add a test asserting is_touching(face)==true after settle), or strike on the first fresh
       forward-stroke contact. PHYSICS.
    2. test_table_integration.gd (1 red) - the BUG-023 drain fix made the CONFIG arithmetic assert pass
       but a real ball at the cradle (z~23.06) STILL fires Drain.ball_drained. Make the BEHAVIORAL oracle
       green, not just the math. LEAD/PHYSICS (verify the live drain Area3D in the instanced Table.tscn).
    3. test_target_no_tunneling.gd (1 red) - stale local POST_RADIUS=1.5 vs the resized 2.0; the resized-
       post no-tunnel gate is not actually measuring the resized post. Read POST_RADIUS live from the
       deflector shape so it cannot drift. TEST-BUILDER.
  PLUS one coverage gap flagged by the board (fold in before resubmission, it is THIS slice's own headline
  gate): no stress test fires a >=2x LAUNCH_SPEED_MAX ball at the NEW convex-hull flipper bat - the only
  ball-vs-flipper test fires at 50 u/s. DESIGN must-feel #6 requires zero tunneling through the capsule
  flipper at >=2x, proven against the real instanced body (resting AND mid-swing). Add it.
  PLUS the UX controls items the producer's prior SEND_BACK already ruled IN SCOPE for the gray-box-clarity
  intent and are still unmet: re-issue the HOLD LAUNCH prompt on every ball arm (not just ball 1), and name
  the actual restart key (SPACE), since Gate 0 is the next stop and a player who cannot launch ball 2 fails
  the fun check on a control problem. Colorblind-safe power meter is cheap (width already encodes power) -
  fold it. HUD font size -> include. DEFER (do NOT block): table_viz.py line-length, the mid-word comment
  reflow in table_config.gd, the test ordering nit in test_ball_tunneling.gd, nudge tuning. Gate 0 stays
  NOT scheduled until GUT is GREEN on the runner on the pushed sha with the capsule-flipper stress test
  executing (not pending/skipped).

## Sunk-cost rule (the producer enforces this)
Hours already spent are gone whether we continue or not. The only question at each gate is whether
the NEXT chunk of hours is the best use of them. Past investment is never an argument to continue.
