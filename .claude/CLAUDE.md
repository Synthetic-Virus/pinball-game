# Pinball Game - Project Instructions (every agent reads this first)

## What this is
A pinball video game targeting a commercial Steam release. Working title only; rename freely.
The developer (Andrew) has a sysadmin/engineering background and NO prior coding experience, and
is assisted by a team of specialized agents (docs/TEAM.md). Code and docs must be readable and
well commented so a motivated non-expert can follow and resume them.

## Engine and stack (locked)
- Engine: Godot 4, GDScript primary. C# only if a specific need clearly justifies it.
- Target: native desktop builds for Steam. Windows first, then Linux and macOS.
- Steam: GodotSteam addon, wired in later (stubbed until a Steamworks App ID exists).

## Pinball technical north star (the one thing not to get wrong)
Pinball is PHYSICS-FIRST. The ball is small and fast, so it tunnels through thin flippers and walls
unless continuous collision detection is on. Non-negotiable defaults:
- Enable `continuous_cd` on the ball RigidBody.
- Keep the physics tick rate high (120 or more).
- Validate with a stress test: a full-power flip into a wall, repeated, with zero tunneling.
The physics-programmer owns this; it is the single most important correctness concern in the project.

## Build and deploy model (lean laptop, homelab build farm)
- The laptop is a THIN CLIENT: agents edit code in WSL, you `git push`. NO Godot, no export
  templates, no build tooling, no steamcmd on the laptop.
- A self-hosted GitHub Actions runner on the homelab (label: `godot`) does ALL builds and tests.
- Push to `main`: the runner lints, runs GUT tests, builds the WEB export, and deploys it to a
  homelab demo URL. That URL is the newest playable prototype.
- Tag `v*`: the runner builds native Windows/Linux and publishes a GitHub Release. Steam is stubbed.
- CONSEQUENCE for agents: CI is the source of truth for "do the tests pass." Write code and tests,
  push, and read the runner results. Do NOT assume a local `godot` exists. A pure-Python linter
  (gdtoolkit) may be available locally for fast static checks; test EXECUTION is CI-side.
- Infra runbook: docs/INFRA.md. Owner: gamedev-devops-engineer.

## House style (hard rules, no exceptions)
- NO emojis anywhere: code, comments, docs, commit messages, UI copy.
- NO em dash characters. Use hyphens, parentheses, commas, colons, or separate sentences.
- Document the WHY. Type GDScript variables and function signatures where practical. snake_case,
  one clear responsibility per script, no clever one-liners a beginner cannot read.

## Document map (sources of truth)
- docs/DESIGN.md        design source of truth   (owner: gamedev-game-designer)
- docs/GATES.md         kill/keep decision gates (owner: gamedev-producer)
- docs/BACKLOG.md       shared development backlog
- docs/qa/QA_BACKLOG.md independent QA backlog    (owner: gamedev-qa-lead)
- docs/INFRA.md         runner + pipeline runbook (owner: gamedev-devops-engineer)
- docs/TEAM.md          the agent roster

## Two principles baked into this team
1. QA is INDEPENDENT of coding. QA has its own backlog and is never blocked waiting for a coding
   handoff. When there is no new code to test, QA writes tests against agreed contracts, hardens
   coverage, and audits docs for testability gaps. QA runs in parallel with development.
2. The PRODUCER holds a scope and finish gate. The enemy of this project is abandonment, not bugs.

## Scope discipline: CUT features, but do not cut correctness
- The PRODUCER's bias is to CUT scope: one polished table beats five rough ones; defer non-essential
  features; finish small; ship. Deciding to scrap at an early gate is a cheap win, not a failure.
- The ENGINEERS' bias, WITHIN an agreed-scoped task, is the opposite: do not defer hardening, edge
  cases, or correctness that belongs to the task you accepted. Cut the feature OR build it solid;
  never ship a half-built feature with a trail of "fix later" notes.
