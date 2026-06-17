# Pinball (working title)

A pinball game targeting a commercial Steam release. Godot 4 (GDScript), built by a team of
specialized agents modeled on the OfficeSphere pipeline.

## Build and deploy model
The laptop is a thin client: the agents edit code, you `git push`. A self-hosted runner on the
homelab does every build and test. Pushing to `main` publishes the newest web demo to a homelab
URL. Tagging `v*` publishes native builds. The laptop never holds Godot or build tooling.

## Start here
- `.claude/CLAUDE.md` - instructions every agent reads.
- `docs/TEAM.md`      - the 13-agent roster.
- `docs/DESIGN.md`    - the design doc (seed).
- `docs/GATES.md`     - the kill/keep gates that decide whether the project continues.
- `docs/BACKLOG.md`   - shared dev backlog.
- `docs/qa/QA_BACKLOG.md` - independent QA backlog.
- `docs/INFRA.md`     - the homelab runner + pipeline runbook.

## Activate the agents
Restart Claude Code, then run a session with this folder as the working directory. The project-
scoped `gamedev-*` agents become dispatchable only after a restart (the registry caches at startup).
