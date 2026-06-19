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

## Sunk-cost rule (the producer enforces this)
Hours already spent are gone whether we continue or not. The only question at each gate is whether
the NEXT chunk of hours is the best use of them. Past investment is never an argument to continue.
