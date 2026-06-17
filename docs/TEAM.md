# Pinball Game - Agent Team Roster
Modeled on the OfficeSphere ship-slice agent team, adapted for Godot 4 game development.
13 agents across 5 teams. There is no orchestration workflow yet (by design); the agents exist
first and we wire the pipeline up later.

## Honest scope note (read this)
Text agents can DESIGN, CODE, REVIEW, TEST, and PRODUCE. They CANNOT draw sprites, model 3D, or
compose music. The art and audio agents are BRIEF-WRITERS: they produce specs, style guides, and
asset lists for a human or an external art/audio tool, and they review how assets are integrated.
They do not create the assets themselves. Everything else on this team is real working capability.

## Teams
### Design
- gamedev-game-designer (opus)   owns docs/DESIGN.md: mechanics, table layout, scoring, the fun.
- gamedev-ux-designer (sonnet)   controls, nudge/tilt feel, HUD, onboarding, menus, accessibility.

### Engineering
- gamedev-lead-programmer (opus) architecture; turns design into tasks in BACKLOG.md; scaffolds;
                                 runs the final code-polish pass before review.
- gamedev-gameplay-programmer (sonnet) implements systems: modes, scoring, targets, game flow.
- gamedev-physics-programmer (opus)    the pinball core: ball, flippers, collisions, CCD, tuning.
- gamedev-devops-engineer (opus)       GitHub, Git LFS, the self-hosted runner, CI/CD, web-demo
                                       deploy, native release, and the (stubbed) Steam pipeline.

### QA (independent - own backlog, never blocked on coding)
- gamedev-qa-lead (opus)         owns docs/qa/QA_BACKLOG.md: strategy, triage, what to test.
- gamedev-test-builder (sonnet)  writes automated GUT tests (run headless on the runner via CI).
- gamedev-qa-bug-hunter (sonnet) adversarial analysis; finds and logs defects.

### Art / Audio (brief-writers, not creators)
- gamedev-art-brief (sonnet)     visual style guide, asset lists, sprite/model specs; integration review.
- gamedev-audio-brief (sonnet)   SFX and music specs, juice/feedback design; audio integration review.

### Production (the gate)
- gamedev-producer (opus)        owns docs/GATES.md: scope discipline, the kill/keep gates, the ship gate.
- gamedev-product-strategist (opus) is it fun, the market/wishlist read, competitive positioning.

## Build/deploy model the agents work under
Laptop is a thin client (agents edit, you push). All builds/tests run on the homelab self-hosted
runner (label: godot). CI is the source of truth for test results. See docs/INFRA.md and .claude/CLAUDE.md.

## Models and tools
Each agent file sets its own model and tools (seniors and gates run opus; executors and briefs run
sonnet to control cost). Both are tunable - edit the agent files freely.

## Activating these agents (important)
These are PROJECT-SCOPED agents. Claude Code caches its agent registry at session start, so:
1. Restart Claude Code after these files are created.
2. Run your session with this project as the working directory (/home/virus/pinball-game).
Only then do the gamedev-* agents become dispatchable.
