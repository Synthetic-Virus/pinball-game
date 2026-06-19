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
DRAIN_Z = HALF_L - 1.0
DRAIN_DEPTH = num("DRAIN_DEPTH")
BALL_R = num("BALL_RADIUS")
TILT = math.radians(num("TILT_DEG"))

bs = re.search(r"BALL_START:\s*Vector3\s*=\s*Vector3\(([^)]+)\)", CFG)
# Components may be expressions (e.g. "HALF_LENGTH - 2.0"); eval them against the parsed constants.
_ns = {"BALL_RADIUS": BALL_R, "HALF_LENGTH": HALF_L, "HALF_WIDTH": HALF_W}
BALL_START = [eval(p, {"__builtins__": {}}, _ns) for p in bs.group(1).split(",")]

# Target positions from table.gd.
targets = []
for m in re.finditer(r"Vector3\(([-\d.]+),\s*([-\d.]+),\s*([-\d.]+)\)", TABLE.split("TARGET_POSITIONS")[1].split("]")[0]):
    targets.append((float(m.group(1)), float(m.group(3))))  # (x, z)

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
# targets
for txx, tzz in targets:
    d.ellipse([tx(txx) - 7, tz(tzz) - 7, tx(txx) + 7, tz(tzz) + 7], outline=(120, 180, 255), width=3)
# ball start + plunger
d.ellipse([tx(BALL_START[0]) - BALL_R * SCALE, tz(BALL_START[2]) - BALL_R * SCALE,
           tx(BALL_START[0]) + BALL_R * SCALE, tz(BALL_START[2]) + BALL_R * SCALE], fill=(235, 235, 245))
d.text((tx(BALL_START[0]) + 8, tz(BALL_START[2])), "ball/plunger", fill=(200, 200, 210))
d.text((6, 6), "TOP-DOWN  (arch=top, drain/flippers=bottom)  gap=%.2f" %
       (2 * (FLIP_SPREAD - FLIP_LEN * math.cos(abs(REST)))), fill=(220, 220, 230))
img.save("/tmp/table_topdown.png")

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
