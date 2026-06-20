#!/usr/bin/env python3
"""
table_viz.py - render a SYNTHETIC image of the pinball table straight from the source-of-truth
positions, with no Godot and no GPU.

WHY THIS EXISTS: the laptop is a thin client (no Godot) and CI is headless, so nobody in the
pipeline can SEE the running game - which is how a camera-less build shipped an empty table. But
every element's position is fully determined by scripts/config/table_config.gd and the build code.
So we can reconstruct the layout from those numbers and draw it. This is a verification tool (and a
basis for automated geometry checks), not the game renderer.

Outputs two views to /tmp:
  table_topdown.png - top-down layout (walls, lane divider, arch, flippers at rest, drain, targets,
                      ball/plunger). Verifies the DESIGN layout (flipper gap, arch, target spread).
  table_side.png    - side view (Z vs Y) showing the 7deg tilt + the Camera3D position, aim, and
                      field-of-view cone. Verifies the camera actually FRAMES the table.

Constants are parsed from table_config.gd so this never drifts from the real scale.
"""

import re
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CFG = (ROOT / "scripts/config/table_config.gd").read_text()
TABLE = (ROOT / "scripts/table.gd").read_text()


def num(name: str) -> float:
    """Parse a `const NAME ... = <number>` literal from table_config.gd."""
    m = re.search(rf"const {name}\b[^=]*=\s*(-?\d+\.?\d*)", CFG)
    if not m:
        raise KeyError(name)
    return float(m.group(1))


# Base constants (literals) and the derived ones (mirror the .gd formulas).
HALF_W = num("HALF_WIDTH")
HALF_L = num("HALF_LENGTH")
WALL_T = num("WALL_THICKNESS")
LANE_INNER_X = num("LANE_INNER_X")
ARCH_CENTER_Z = -HALF_L + 6.0
ARCH_RX = HALF_W
ARCH_RZ = num("ARCH_RADIUS_Z")
FLIP_LEN = num("FLIPPER_LENGTH")
FLIP_W = num("FLIPPER_WIDTH")
FLIP_SPREAD = num("FLIPPER_PIVOT_SPREAD")
FLIP_PIVOT_Z = HALF_L - 5.0
REST = num("FLIPPER_REST_ANGLE")  # radians, magnitude used per-side
DRAIN_DEPTH = num("DRAIN_DEPTH")
# DRAIN_Z is defined in TableConfig as FLIPPER_BAT_MAX_Z + DRAIN_BAT_CLEARANCE + DRAIN_DEPTH/2 so the
# drain volume's up-table edge clears the flipper bat catch zone (QA BUG-023). Mirror that formula
# here (the constants are bare literals the parser can read) rather than the old stale HALF_L - 1.0.
DRAIN_Z = num("FLIPPER_BAT_MAX_Z") + num("DRAIN_BAT_CLEARANCE") + DRAIN_DEPTH / 2.0
BALL_R = num("BALL_RADIUS")
TILT = math.radians(num("TILT_DEG"))
FLIP_UP = num("FLIPPER_UP_ANGLE")  # radians, magnitude per side


def vec3_const(name: str):
    """Parse a `const NAME: Vector3 = Vector3(a, b, c)` literal, eval'ing simple expressions."""
    m = re.search(rf"const {name}:\s*Vector3\s*=\s*Vector3\(\s*([^)]+)\)", CFG)
    if not m:
        raise KeyError(name)
    ns = {
        "BALL_RADIUS": BALL_R, "HALF_LENGTH": HALF_L, "HALF_WIDTH": HALF_W,
        "FLIPPER_PIVOT_Z": FLIP_PIVOT_Z, "WALL_HEIGHT": num("WALL_HEIGHT"),
    }
    return [eval(p, {"__builtins__": {}}, ns) for p in m.group(1).split(",")]


def vec3_array_const(name: str):
    """Parse a `const NAME: Array[Vector3] = [ Vector3(...), ... ]` block into a list of (x, z).

    Split on `= [` (the array's opening bracket) so the `]` in the `Array[Vector3]` type annotation
    does not prematurely end the block; then take up to the closing `]`.
    """
    after = CFG.split(f"const {name}:", 1)[1]
    block = after.split("= [", 1)[1].split("]", 1)[0]
    out = []
    for m in re.finditer(r"Vector3\(([-\d.]+),\s*([-\d.]+),\s*([-\d.]+)\)", block):
        out.append((float(m.group(1)), float(m.group(3))))  # (x, z)
    return out


# SLICE "real pinball furniture" geometry, parsed from TableConfig (single source of truth).
POP_BUMPERS = vec3_array_const("POP_BUMPER_POSITIONS")
POP_BUMPER_R = num("POP_BUMPER_RADIUS")
STANDUP_BANK = vec3_array_const("STANDUP_BANK_POSITIONS")
SLING_L_POS = vec3_const("SLINGSHOT_LEFT_POS")
SLING_R_POS = vec3_const("SLINGSHOT_RIGHT_POS")
SLING_L_KICK = vec3_const("SLINGSHOT_LEFT_KICK_DIR")
SLING_R_KICK = vec3_const("SLINGSHOT_RIGHT_KICK_DIR")
# LANE_GUIDE_DIVIDER_X is defined as `HALF_WIDTH - 3.0` (an expression, not a bare literal), so we
# mirror that formula here rather than parse a number. Same for the top/bottom Z below.
LANE_GUIDE_X = HALF_W - 3.0
# LANE_GUIDE_TOP_Z raised from FLIP_PIVOT_Z - 2.0 to FLIP_PIVOT_Z - 1.0 so the guide divider clears
# the slingshot KickerBody outer corner (QA BUG-024). Mirror the new config formula.
LANE_GUIDE_TOP_Z = FLIP_PIVOT_Z - 1.0
LANE_GUIDE_BOTTOM_Z = HALF_L - 2.0
KICK_MIN = num("KICK_MIN_OUTGOING_SPEED")
KICK_MAX = num("KICK_MAX_OUTGOING_SPEED")

bs = re.search(r"BALL_START:\s*Vector3\s*=\s*Vector3\(([^)]+)\)", CFG)
# Components may be expressions (e.g. "HALF_LENGTH - 2.0"); eval them against the parsed constants.
_ns = {"BALL_RADIUS": BALL_R, "HALF_LENGTH": HALF_L, "HALF_WIDTH": HALF_W}
BALL_START = [eval(p, {"__builtins__": {}}, _ns) for p in bs.group(1).split(",")]

# The legacy scattered TARGET_POSITIONS const was removed from table.gd (the 3 targets are now the
# STANDUP_BANK_POSITIONS bank, parsed above). Keep an empty list so the legacy overlay loop below is
# a no-op; the bank is drawn from STANDUP_BANK. (Parsing TARGET_POSITIONS here used to crash the tool
# because the const no longer exists - SLICE "Table reshape" fix.)
targets: list = []

# Camera tunables from table.gd _build_presentation.
def vec3(name: str, text: str):
    m = re.search(rf"{name}:\s*Vector3\s*=\s*Vector3\(([^)]+)\)", text)
    if not m:
        return None  # value is computed at runtime (camera is auto-framed), not a literal
    return [float(x) for x in m.group(1).split(",")]

# The camera position is auto-framed at runtime now, so CAMERA_POS/CAMERA_LOOK are usually absent.
# Pass them via CLI to preview a specific candidate (see below). FOV is still a literal const.
CAM_POS = vec3("CAMERA_POS", TABLE)
CAM_LOOK = vec3("CAMERA_LOOK_AT", TABLE)
_fov_m = re.search(r"CAMERA_FOV:\s*float\s*=\s*([\d.]+)", TABLE)
CAM_FOV = float(_fov_m.group(1)) if _fov_m else 60.0

# Optional CLI override to sweep camera values offline without editing table.gd:
#   python3 tools/table_viz.py  cx cy cz  lx ly lz  fov
import sys
if len(sys.argv) >= 8:
    CAM_POS = [float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])]
    CAM_LOOK = [float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])]
    CAM_FOV = float(sys.argv[7])

# ---- top-down view -----------------------------------------------------------------------------
SCALE = 18  # pixels per world unit
MX, MZ = HALF_W + 3, HALF_L + 3
W = int(2 * MX * SCALE)
H = int(2 * MZ * SCALE)


def tx(x):  # world X -> pixel x (centered)
    return int((x + MX) * SCALE)


def tz(z):  # world Z -> pixel y (+Z = down-table = lower on screen = bottom)
    return int((z + MZ) * SCALE)


img = Image.new("RGB", (W, H), (20, 22, 28))
d = ImageDraw.Draw(img, "RGBA")

# playfield surface fill
d.rectangle([tx(-HALF_W), tz(-HALF_L), tx(HALF_W), tz(HALF_L)], fill=(40, 44, 52))
# perimeter walls: left, right, top (bottom OPEN for the drain)
wall = (150, 155, 165)
d.line([tx(-HALF_W), tz(-HALF_L), tx(-HALF_W), tz(HALF_L)], fill=wall, width=4)
d.line([tx(HALF_W), tz(-HALF_L), tx(HALF_W), tz(HALF_L)], fill=wall, width=4)
d.line([tx(-HALF_W), tz(-HALF_L), tx(HALF_W), tz(-HALF_L)], fill=wall, width=4)
# lane divider at x = LANE_INNER_X (right launch lane)
d.line([tx(LANE_INNER_X), tz(ARCH_CENTER_Z), tx(LANE_INNER_X), tz(HALF_L)], fill=(120, 125, 135), width=3)
# arch dome across the top
pts = []
for i in range(33):
    a = math.pi * i / 32
    pts.append((tx(ARCH_RX * math.cos(a)), tz(ARCH_CENTER_Z - ARCH_RZ * math.sin(a))))
d.line(pts, fill=(180, 140, 90), width=3)
# drain zone (translucent red) near the bottom
d.rectangle([tx(-HALF_W), tz(DRAIN_Z - DRAIN_DEPTH / 2), tx(HALF_W), tz(DRAIN_Z + DRAIN_DEPTH / 2)],
            fill=(200, 60, 60, 70))
# flippers as bats from each pivot (inverted V); tip reaches toward center + up-table
for sign in (-1, 1):
    px, pz = sign * FLIP_SPREAD, FLIP_PIVOT_Z
    tipx = px - sign * FLIP_LEN * math.cos(abs(REST))
    tipz = pz - FLIP_LEN * math.sin(abs(REST))
    d.line([tx(px), tz(pz), tx(tipx), tz(tipz)], fill=(90, 200, 120), width=int(FLIP_W * SCALE / 2))
    d.ellipse([tx(px) - 4, tz(pz) - 4, tx(px) + 4, tz(pz) + 4], fill=(230, 230, 120))
# targets (legacy scattered list, if present)
for txx, tzz in targets:
    d.ellipse([tx(txx) - 7, tz(tzz) - 7, tx(txx) + 7, tz(tzz) + 7], outline=(120, 180, 255), width=3)

# ---- SLICE "real pinball furniture" overlay (CAD shot validation) -------------------------------
# Standup target bank (re-homed physical targets): filled blue squares.
for sxx, szz in STANDUP_BANK:
    d.rectangle([tx(sxx) - 7, tz(szz) - 7, tx(sxx) + 7, tz(szz) + 7],
                outline=(120, 180, 255), fill=(60, 90, 140), width=2)
# Pop bumpers: orange circles of POP_BUMPER_R, with a small radial-kick fan to show "outward".
for bxx, bzz in POP_BUMPERS:
    r = POP_BUMPER_R * SCALE
    d.ellipse([tx(bxx) - r, tz(bzz) - r, tx(bxx) + r, tz(bzz) + r],
              outline=(255, 170, 70), width=3)
    for ang in range(0, 360, 45):
        ex = bxx + (POP_BUMPER_R + 1.2) * math.cos(math.radians(ang))
        ez = bzz + (POP_BUMPER_R + 1.2) * math.sin(math.radians(ang))
        d.line([tx(bxx), tz(bzz), tx(ex), tz(ez)], fill=(255, 170, 70, 120), width=1)
# Slingshots: magenta dots with a KICK VECTOR arrow (the load-bearing "into play" direction).
for (px, _py, pz), (kx, _ky, kz) in [(SLING_L_POS, SLING_L_KICK), (SLING_R_POS, SLING_R_KICK)]:
    d.ellipse([tx(px) - 5, tz(pz) - 5, tx(px) + 5, tz(pz) + 5], fill=(230, 90, 210))
    ex, ez = px + kx * 5.0, pz + kz * 5.0  # 5-unit arrow along the kick direction
    d.line([tx(px), tz(pz), tx(ex), tz(ez)], fill=(230, 90, 210), width=3)
# Lane-guide dividers (inlane/outlane split) per side.
for sgn in (-1, 1):
    gx = LANE_GUIDE_X * sgn
    d.line([tx(gx), tz(LANE_GUIDE_TOP_Z), tx(gx), tz(LANE_GUIDE_BOTTOM_Z)],
           fill=(120, 200, 140), width=3)
# Flipper-tip sweep ARC (rest -> up) so the human can see what the standup bank is checked against.
for sign in (-1, 1):
    px, pz = sign * FLIP_SPREAD, FLIP_PIVOT_Z
    arc_pts = []
    steps = 16
    for k in range(steps + 1):
        a = abs(REST) + (abs(FLIP_UP) - abs(REST)) * k / steps if False else None
        # Sweep the bat angle from rest to up; tip position traces the arc.
        ang = (-abs(REST)) + ((abs(FLIP_UP) - (-abs(REST))) * k / steps)
        tipx = px - sign * FLIP_LEN * math.cos(ang)
        tipz = pz - FLIP_LEN * math.sin(ang)
        arc_pts.append((tx(tipx), tz(tipz)))
    d.line(arc_pts, fill=(90, 200, 120, 160), width=1)

# ball start + plunger
d.ellipse([tx(BALL_START[0]) - BALL_R * SCALE, tz(BALL_START[2]) - BALL_R * SCALE,
           tx(BALL_START[0]) + BALL_R * SCALE, tz(BALL_START[2]) + BALL_R * SCALE], fill=(235, 235, 245))
d.text((tx(BALL_START[0]) + 8, tz(BALL_START[2])), "ball/plunger", fill=(200, 200, 210))
d.text((6, 6), "TOP-DOWN  (arch=top, drain/flippers=bottom)  gap=%.2f" %
       (2 * (FLIP_SPREAD - FLIP_LEN * math.cos(abs(REST)))), fill=(220, 220, 230))
img.save("/tmp/table_topdown.png")


# ---- DETERMINISTIC SHOT VALIDATION (CAD discipline; mirrors tests/test_shot_geometry.gd) --------
# Fails the tool (non-zero exit) if any kick aims at the drain or a standup target is out of flipper
# reach. This is the offline twin of the GUT geometry test: the same checks, runnable on the laptop
# (thin client, no Godot) so the layout can be validated before pushing. The GUT test is the CI
# source of truth; this is the fast local pre-check.
def validate_layout():
    problems = []
    # 1. Slingshot kicks must point UP-table (-z) and toward center per side.
    if SLING_L_KICK[2] >= 0.0:
        problems.append("left slingshot kick aims at the drain (z=%.2f >= 0)" % SLING_L_KICK[2])
    if SLING_R_KICK[2] >= 0.0:
        problems.append("right slingshot kick aims at the drain (z=%.2f >= 0)" % SLING_R_KICK[2])
    if SLING_L_KICK[0] <= 0.0:
        problems.append("left slingshot does not kick toward center (x=%.2f <= 0)" % SLING_L_KICK[0])
    if SLING_R_KICK[0] >= 0.0:
        problems.append("right slingshot does not kick toward center (x=%.2f >= 0)" % SLING_R_KICK[0])
    # 2. Standup bank must sit in the MAKEABLE WINDOW: up-table of the flipper-tip reach (a deliberate
    #    aimed flip, not a touch) and down-table of the arch base (still in the open field the ball can
    #    climb to). Mirrors tests/test_shot_geometry.gd._makeable_near_z / _makeable_far_z.
    near_z = FLIP_PIVOT_Z - FLIP_LEN  # least up-table: closer is a touch, not a flip
    far_z = ARCH_CENTER_Z             # most up-table: past this the ball is in the arch
    for sxx, szz in STANDUP_BANK:
        if szz >= near_z:
            problems.append("standup target z=%.2f too close to flippers (near %.2f)" % (szz, near_z))
        if szz <= far_z:
            problems.append("standup target z=%.2f past the arch base (far %.2f)" % (szz, far_z))
    # 3. Pop bumpers must be up-table of the flippers and inside the side walls.
    for bxx, bzz in POP_BUMPERS:
        if bzz >= FLIP_PIVOT_Z:
            problems.append("pop bumper z=%.2f is not up-table of the flippers" % bzz)
        if abs(bxx) >= HALF_W - POP_BUMPER_R:
            problems.append("pop bumper x=%.2f fouls a side wall" % bxx)
    # 4. Kick-impulse bounds sane and inside the no-tunneling stress band (2x LAUNCH_SPEED_MAX).
    launch_max_m = re.search(r"const LAUNCH_SPEED_MAX:\s*float\s*=\s*([\d.]+)", CFG)
    launch_max = float(launch_max_m.group(1)) if launch_max_m else 90.0
    if not (KICK_MIN < KICK_MAX < 2.0 * launch_max):
        problems.append("kick bounds out of band: min=%.1f cap=%.1f stress=%.1f"
                        % (KICK_MIN, KICK_MAX, 2.0 * launch_max))
    # 5. LAUNCH FURNITURE FITS THE BALL (SLICE "Playtest fixes 2", fix 4). After the lane/plunger
    #    resize the lane must be a SNUG ~ball-width chute and the ball + plunger face must line up
    #    inside it with no part poking through a wall. Deterministic, not eyeballed:
    #      a) the lane width = HALF_WIDTH - LANE_INNER_X must be a snug chute (between ~1 and ~3 ball
    #         diameters): wide enough for the ball, narrow enough to read as a chute not a box.
    #      b) the resting ball (BALL_START.x) must sit at the lane CENTER, fully inside the lane in X.
    #      c) the plunger face (PLUNGER_FACE_WIDTH) must be WIDER than the ball (strikes squarely) and
    #         fit inside the lane with clearance (no part of the face inside the divider or the wall).
    lane_w = HALF_W - LANE_INNER_X
    ball_dia = 2.0 * BALL_R
    lane_center = (LANE_INNER_X + HALF_W) / 2.0
    face_w_m = re.search(r"const PLUNGER_FACE_WIDTH:\s*float\s*=\s*LANE_WIDTH\s*-\s*([\d.]+)", CFG)
    face_w = (lane_w - float(face_w_m.group(1))) if face_w_m else None
    if not (ball_dia <= lane_w <= 3.0 * ball_dia):
        problems.append("lane width %.2f not a snug ~ball-width chute (ball dia %.2f; want 1..3 dia)"
                        % (lane_w, ball_dia))
    # The ball at BALL_START.x must sit inside the lane in X with at least a ball radius of clearance.
    if not (LANE_INNER_X + BALL_R <= BALL_START[0] <= HALF_W - BALL_R):
        problems.append("ball start x=%.2f not inside the lane [%.2f, %.2f] with clearance"
                        % (BALL_START[0], LANE_INNER_X + BALL_R, HALF_W - BALL_R))
    if abs(BALL_START[0] - lane_center) > 0.01:
        problems.append("ball start x=%.2f not centered in the lane (center %.2f) - off the plunger"
                        % (BALL_START[0], lane_center))
    if face_w is not None:
        if face_w <= ball_dia:
            problems.append("plunger face %.2f not wider than the ball (dia %.2f) - off-center misses"
                            % (face_w, ball_dia))
        if face_w >= lane_w:
            problems.append("plunger face %.2f does not fit inside the lane (width %.2f)"
                            % (face_w, lane_w))
    return problems


_problems = validate_layout()
if _problems:
    print("SHOT VALIDATION FAILED:")
    for p in _problems:
        print("  - " + p)
    sys.exit(1)
print("shot validation OK: %d bumpers, %d standup targets, 2 slings, kicks into play"
      % (len(POP_BUMPERS), len(STANDUP_BANK)))

# The camera views below need explicit camera values. The in-game camera is auto-framed at runtime
# (no hardcoded position), so unless values were passed on the CLI we stop after the top-down layout.
if CAM_POS is None or CAM_LOOK is None:
    print("wrote /tmp/table_topdown.png")
    print("camera is auto-framed at runtime; pass 'cx cy cz lx ly lz fov' to preview a candidate.")
    sys.exit(0)

# ---- side view with camera frustum -------------------------------------------------------------
SW, SH = 1100, 760
S = 11  # px per unit
ox, oy = 220, 420  # world origin -> pixel


def sx(z):
    return int(ox + z * S)


def sy(y):
    return int(oy - y * S)


simg = Image.new("RGB", (SW, SH), (20, 22, 28))
sd = ImageDraw.Draw(simg)
# tilted playfield surface line (world): local Z in [-HALF_L, HALF_L], tilt about X
az, ay = -HALF_L, 0.0
aw = (-math.cos(TILT) * HALF_L * -1, 0)  # placeholder
def world_of(localz):
    return (math.cos(TILT) * localz, -math.sin(TILT) * localz)  # (world z, world y)
p_arch = world_of(-HALF_L)
p_drain = world_of(HALF_L)
sd.line([sx(p_arch[0]), sy(p_arch[1]), sx(p_drain[0]), sy(p_drain[1])], fill=(150, 155, 165), width=4)
sd.text((sx(p_arch[0]) - 10, sy(p_arch[1]) - 18), "arch", fill=(180, 140, 90))
sd.text((sx(p_drain[0]) - 10, sy(p_drain[1]) + 6), "drain", fill=(200, 80, 80))
# camera position + aim
cz, cy = CAM_POS[2], CAM_POS[1]
lz, ly = CAM_LOOK[2], CAM_LOOK[1]
sd.ellipse([sx(cz) - 6, sy(cy) - 6, sx(cz) + 6, sy(cy) + 6], fill=(255, 220, 80))
sd.text((sx(cz) + 8, sy(cy) - 6), "camera", fill=(255, 220, 80))
sd.line([sx(cz), sy(cy), sx(lz), sy(ly)], fill=(120, 120, 140), width=1)
# frustum edges: aim direction +/- fov/2 (in the Z-Y plane)
aim = math.atan2(ly - cy, lz - cz)
half = math.radians(CAM_FOV / 2)
for edge in (aim - half, aim + half):
    ez, ey = cz + 80 * math.cos(edge), cy + 80 * math.sin(edge)
    sd.line([sx(cz), sy(cy), sx(ez), sy(ey)], fill=(90, 160, 230), width=2)
sd.text((6, 6), "SIDE VIEW (Z horiz, Y up)  cam=%s look=%s fov=%g  -- table should sit inside the blue cone"
        % (CAM_POS, CAM_LOOK, CAM_FOV), fill=(220, 220, 230))
simg.save("/tmp/table_side.png")

# ---- camera-projection view: predict what the in-game camera actually renders ------------------
# Pure-math projection through the Camera3D into the real 720x1280 viewport (KEEP_HEIGHT => fov is
# VERTICAL). This is the deterministic "virtual image" used to verify/tune framing with no GPU.
import numpy as np

VW, VH = 720, 1280
ASPECT = VW / VH
TILT_RAD = TILT


def to_world(local):
    # Playfield node is rotated +TILT about X; gravity stays world-down.
    x, y, z = local
    return np.array([x, y * math.cos(TILT_RAD) - z * math.sin(TILT_RAD),
                     y * math.sin(TILT_RAD) + z * math.cos(TILT_RAD)])


cam = np.array(CAM_POS, dtype=float)
look = np.array(CAM_LOOK, dtype=float)
fwd = look - cam
fwd = fwd / np.linalg.norm(fwd)
right = np.cross(fwd, np.array([0.0, 1.0, 0.0]))
right = right / np.linalg.norm(right)
up = np.cross(right, fwd)
tan_half = math.tan(math.radians(CAM_FOV) / 2.0)


def project(world):
    rel = world - cam
    depth = float(np.dot(rel, fwd))
    if depth <= 0.01:
        return None  # behind camera
    xc = float(np.dot(rel, right))
    yc = float(np.dot(rel, up))
    ndc_x = (xc / depth) / (tan_half * ASPECT)
    ndc_y = (yc / depth) / tan_half
    sx_ = (ndc_x * 0.5 + 0.5) * VW
    sy_ = (1.0 - (ndc_y * 0.5 + 0.5)) * VH
    return (sx_, sy_)


fimg = Image.new("RGB", (VW, VH), (16, 17, 22))
fd = ImageDraw.Draw(fimg)


def draw_world_poly(locals_list, color, width=3, closed=True):
    pts = [project(to_world(p)) for p in locals_list]
    pts = [p for p in pts if p is not None]
    if len(pts) >= 2:
        fd.line(pts + ([pts[0]] if closed else []), fill=color, width=width)


# playfield surface rectangle
HW, HL = HALF_W, HALF_L
draw_world_poly([(-HW, 0, -HL), (HW, 0, -HL), (HW, 0, HL), (-HW, 0, HL)], (90, 95, 110), 2)
# perimeter wall tops (left/right/top), height WALL_HEIGHT
WHt = num("WALL_HEIGHT")
for seg in [[(-HW, WHt, -HL), (-HW, WHt, HL)], [(HW, WHt, -HL), (HW, WHt, HL)], [(-HW, WHt, -HL), (HW, WHt, -HL)]]:
    draw_world_poly(seg, (150, 155, 165), 2, closed=False)
# arch curve
arch = [(ARCH_RX * math.cos(math.pi * i / 16), 0, ARCH_CENTER_Z - ARCH_RZ * math.sin(math.pi * i / 16)) for i in range(17)]
draw_world_poly(arch, (180, 140, 90), 3, closed=False)
# flippers
for sign in (-1, 1):
    px, pz = sign * FLIP_SPREAD, FLIP_PIVOT_Z
    tipx = px - sign * FLIP_LEN * math.cos(abs(REST))
    tipz = pz - FLIP_LEN * math.sin(abs(REST))
    draw_world_poly([(px, 0, pz), (tipx, 0, tipz)], (90, 200, 120), 5, closed=False)
# ball
bp = project(to_world((BALL_START[0], BALL_START[1], BALL_START[2])))
if bp:
    fd.ellipse([bp[0] - 8, bp[1] - 8, bp[0] + 8, bp[1] + 8], fill=(235, 235, 245))
# centerlines + label
fd.line([0, VH // 2, VW, VH // 2], fill=(60, 60, 70), width=1)
fd.line([VW // 2, 0, VW // 2, VH], fill=(60, 60, 70), width=1)
# report vertical coverage of the table on screen
ys = [project(to_world(p)) for p in [(-HW, 0, -HL), (HW, 0, -HL), (-HW, 0, HL), (HW, 0, HL), (0, 0, 0)]]
ys = [p[1] for p in ys if p is not None]
cover = ""
if ys:
    cover = "table screen-y %d..%d of %d (center %d)" % (int(min(ys)), int(max(ys)), VH, int(sum(ys) / len(ys)))
fd.text((8, 8), "PROJECTED 720x1280  cam=%s look=%s fov=%g" % (CAM_POS, CAM_LOOK, CAM_FOV), fill=(220, 220, 230))
fd.text((8, 26), cover, fill=(200, 200, 120))
fimg.save("/tmp/table_projected.png")
print(cover)

print("wrote /tmp/table_topdown.png, /tmp/table_side.png, /tmp/table_projected.png")
print("flipper drain-gap = %.2f units (~%.1f ball-diameters)" %
      (2 * (FLIP_SPREAD - FLIP_LEN * math.cos(abs(REST))), (2 * (FLIP_SPREAD - FLIP_LEN * math.cos(abs(REST)))) / (2 * BALL_R)))
print("camera pos=%s look=%s fov=%g" % (CAM_POS, CAM_LOOK, CAM_FOV))
