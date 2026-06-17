# QA Backlog (independent)
Owner: gamedev-qa-lead. QA is an INDEPENDENT team. It is never blocked waiting for a coding handoff.
It pulls work from this backlog and runs in parallel with development. Tests EXECUTE headless on the
homelab runner via CI (the laptop has no Godot); CI results are the source of truth. Three streams:

## Stream 1 - Test debt (automated GUT tests to write, often BEFORE the code exists)
- [ ] Physics: the ball never tunnels through a wall across many high-speed collisions.
- [ ] Scoring: hitting a target adds exactly the expected points.
- [ ] Drain: losing the ball decrements ball count; the game ends at zero balls.

## Stream 2 - Bug repros (found defects, reproduced and logged)
(none yet - one entry per defect: steps, expected, actual, severity)

## Stream 3 - Regression sweeps (re-verify after changes)
(none yet)

## How QA stays unblocked (the independence rule in practice)
When there is no new code to test, QA does NOT idle. It (a) writes tests against agreed function
signatures and contracts before the code exists, (b) hardens existing coverage and adds edge cases,
and (c) audits DESIGN.md and the code for testability gaps. There is always test-debt to pull.
