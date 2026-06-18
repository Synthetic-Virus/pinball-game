// Game-dev ship-slice workflow for the pinball project.
// Runs ONE slice through the full gamedev-* team, mirroring the OfficeSphere ship-slice pattern
// adapted to game roles: Design -> Plan/scaffold -> parallel Build+Tests -> QA -> Polish ->
// peer-review board -> producer scope/finish gate.
//
// IMPORTANT: run this from a session ROOTED AT /home/virus/pinball-game so the project-scoped
// gamedev-* agents are registered. From a /home/virus-rooted session the agents do not load and
// the workflow's agent() calls will fail with "agent not found".
//
// Invoke:  Workflow({ name: "ship-slice", args: "<the slice brief, e.g. the Core 3D rebuild slice in docs/BACKLOG.md>" })

export const meta = {
  name: 'ship-slice',
  description: 'Run a pinball game-dev slice through the full gamedev team: design -> plan/scaffold -> parallel build+tests -> QA -> polish -> review board -> producer scope gate.',
  phases: [
    { title: 'Design' },
    { title: 'Plan' },
    { title: 'Build' },
    { title: 'QA' },
    { title: 'Polish' },
    { title: 'Review board' },
    { title: 'Producer gate' },
  ],
}

// args = the slice brief. On this Claude Code build workflow args can arrive JSON-encoded; parse defensively.
let _a = args
if (typeof _a === 'string') { try { _a = JSON.parse(_a) } catch (e) { /* plain string brief */ } }
const SLICE = (typeof _a === 'string') ? _a : ((_a && (_a.brief || _a.slice || _a.description)) || 'See the latest SLICE in docs/BACKLOG.md')

const DOCS = 'Read .claude/CLAUDE.md (house rules), docs/DESIGN.md, docs/REFERENCES.md, docs/pinhead-tech-notes.md, docs/GATES.md, and the SLICE in docs/BACKLOG.md.'

log('ship-slice on: ' + SLICE)

// 1) DESIGN -------------------------------------------------------------------
phase('Design')
const design = await agent(
  `${DOCS}\n\nYou are the game designer. Confirm and tighten the DESIGN INTENT for this slice BEFORE engineering. ` +
  `Slice: ${SLICE}\n\nReturn a concise brief: the player-facing goal, the must-feel qualities, and the design constraints the engineers must honor. Do NOT write code.`,
  { agentType: 'gamedev-game-designer', model: 'opus', phase: 'Design', label: 'design-intent' }
)

// 2) PLAN + SCAFFOLD ----------------------------------------------------------
phase('Plan')
const plan = await agent(
  `${DOCS}\n\nYou are the lead programmer. Architect this slice and SCAFFOLD skeleton files so the physics and gameplay coders can fill DIFFERENT files in parallel without conflict.\n` +
  `Slice: ${SLICE}\nDesigner brief:\n${design}\n\n` +
  `Decide scene structure, world scale, Jolt physics layers, the input action map, and the FILE-OWNERSHIP split. ` +
  `Create skeleton files with typed signatures + TODOs: assign FLIPPER/BALL/physics files to the physics-programmer, PLUNGER/SCORING/flow files to the gameplay-programmer, and the test matrix to the test-builder. ` +
  `Return the architecture decisions + an explicit file-ownership map + the test matrix.`,
  { agentType: 'gamedev-lead-programmer', model: 'opus', phase: 'Plan', label: 'architecture+scaffold' }
)

// 3) BUILD (parallel, each agent fills only its own files) --------------------
phase('Build')
const build = (await parallel([
  () => agent(
    `${DOCS}\n\nYou are the physics programmer. Fill in YOUR assigned files only (per the lead file-ownership map). ` +
    `Implement FORCE-DRIVEN flippers (hinge + driven force + return spring, NOT kinematic) and the ball with continuous_cd on Jolt, per docs/pinhead-tech-notes.md. Do not touch other agents' files.\n` +
    `Plan:\n${plan}\n\nReport exactly which files you changed.`,
    { agentType: 'gamedev-physics-programmer', model: 'opus', phase: 'Build', label: 'physics' }
  ),
  () => agent(
    `${DOCS}\n\nYou are the gameplay programmer. Fill in YOUR assigned files only: plunger power meter, drain + ball count, scoring. Do not touch the physics files.\n` +
    `Plan:\n${plan}\n\nReport exactly which files you changed.`,
    { agentType: 'gamedev-gameplay-programmer', model: 'sonnet', phase: 'Build', label: 'gameplay' }
  ),
  () => agent(
    `${DOCS}\n\nYou are the test builder. Write GUT tests under tests/ per the lead test matrix, including a stress test asserting the ball never tunnels at full flip speed. Install the GUT addon (addons/gut) if missing so the CI test job stops skipping.\n` +
    `Plan:\n${plan}\n\nReport the tests you wrote.`,
    { agentType: 'gamedev-test-builder', model: 'sonnet', phase: 'Build', label: 'tests' }
  ),
])).filter(Boolean)

// 4) QA (independent review of the integrated slice) --------------------------
phase('QA')
const qa = (await parallel([
  () => agent(
    `${DOCS}\n\nYou are the QA lead. Review the integrated slice production code for quality, correctness, and testability. Return findings split into BLOCKING vs non-blocking. Read-only on production code.`,
    { agentType: 'gamedev-qa-lead', model: 'opus', phase: 'QA', label: 'qa-lead' }
  ),
  () => agent(
    `${DOCS}\n\nYou are the QA bug hunter. Adversarially hunt defects (tunneling, stuck ball, score exploits, soft-locks, flipper overlap, drain edge cases). Return reproducible defect reports ranked by severity.`,
    { agentType: 'gamedev-qa-bug-hunter', model: 'sonnet', phase: 'QA', label: 'bug-hunter' }
  ),
])).filter(Boolean)

// 5) POLISH (lead addresses QA findings + tighten) ----------------------------
phase('Polish')
const polish = await agent(
  `${DOCS}\n\nYou are the lead programmer doing the final polish pass. Address the QA findings below and FOLD IN hardening that belongs to this slice (do not defer it). Tighten the code.\n` +
  `QA findings:\n${JSON.stringify(qa)}\n\nReport what you changed and which findings you addressed vs deferred (with why).`,
  { agentType: 'gamedev-lead-programmer', model: 'opus', phase: 'Polish', label: 'polish' }
)

// 6) REVIEW BOARD (parallel, one verdict per lens) ----------------------------
phase('Review board')
const REVIEWERS = [
  { type: 'gamedev-lead-programmer', model: 'opus', lens: 'code architecture and quality, Godot 4 idioms, file structure' },
  { type: 'gamedev-physics-programmer', model: 'opus', lens: 'physics correctness and feel: Jolt usage, continuous_cd, no tunneling, flipper momentum and no overlap' },
  { type: 'gamedev-ux-designer', model: 'sonnet', lens: 'controls, readability, game feel, accessibility' },
  { type: 'gamedev-game-designer', model: 'opus', lens: 'adherence to the design intent and the table feel' },
  { type: 'gamedev-qa-lead', model: 'opus', lens: 'test coverage of new behavior, real node/physics tests (no faked engine internals)' },
]
const reviews = (await parallel(REVIEWERS.map((r) => () =>
  agent(
    `${DOCS}\n\nPeer-review this completed slice through ONE lens: ${r.lens}.\nSlice: ${SLICE}\n` +
    `Return a short YAML verdict block: verdict (APPROVE or REQUEST_CHANGES) then findings as bullets with file:line where possible. Read-only.`,
    { agentType: r.type, model: r.model, phase: 'Review board', label: 'review:' + r.type }
  )
))).filter(Boolean)

// 7) PRODUCER SCOPE/FINISH GATE -----------------------------------------------
phase('Producer gate')
const verdict = await agent(
  `${DOCS}\n\nYou are the producer and you hold the scope/finish gate. Review the slice, the board verdicts, and the kill/keep gates in docs/GATES.md.\n` +
  `Board verdicts:\n${JSON.stringify(reviews)}\n\n` +
  `Decide PASS (in-scope, finishable, board satisfied; append a one-line dated approval note to docs/GATES.md naming this slice) or SEND_BACK (list exactly what must change). Enforce the cut list; reject scope creep. Return PASS or SEND_BACK with reasoning.`,
  { agentType: 'gamedev-producer', model: 'opus', phase: 'Producer gate', label: 'producer' }
)

log('ship-slice complete; producer verdict captured.')
return { slice: SLICE, design, plan, build, qa, polish, reviews, verdict }
