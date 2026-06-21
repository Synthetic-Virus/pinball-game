# Reference Layout - faithful table recreation

Source of truth for the table layout we are recreating. The developer supplied a top-down render of a
real table (Heineken theme) on 2026-06-21 and asked for a faithful, region-by-region recreation. The
element positions below were MEASURED from that top-down (not eyeballed), then mapped into the table's
own coordinate system. Build to these numbers; refine via the deploy/react loop (see
the rapid-layout-loop memory).

## Coordinate mapping (reference pixels -> table units)

The reference image is 818 x 1351 px. Anchors found by detecting the perimeter:
- Top wall at py = 49  -> table z = -25 (HALF_LENGTH up-table edge).
- Launch-lane rails at px 667-693 -> table x ~ 14..16 (LANE_INNER_X..HALF_WIDTH).
- Furniture symmetry axis at px = 404 -> table x = 0.
- Flippers at py ~ 1075 -> table z = 20 (FLIPPER_PIVOT_Z), used to anchor the z scale.

Resulting affine (x to the right, z down-table toward the drain):

    x_table = (px - 404) / 18.0
    z_table = (py - 49) / 22.8 - 25.0

X and Z use DIFFERENT scales because the reference is taller (per-unit) than it is wide; that is the
real table's aspect, kept here rather than forced into a square.

## Measured element positions (table units)

Coordinates are (x, z). z is negative up-table (toward the arch), positive down-table (toward the
drain). Left/right pairs are symmetrized about x = 0.

### Upper field
- 5 standup targets in a row: x = -7.2, -3.6, 0.0, +3.5, +7.1 ; z = -16.4
- 3 pop bumpers (triangle): (-4.2, -9.4), (+4.0, -9.4), (0.0, -4.4)  [two high, one low-center]
- Top orbit: a large guide rail sweeping the whole top (replaces the small dome arch).
- Return guide rails with rubber posts down each upper side.

### Left target bank (region 3)
- A vertical bank of ~3 targets on the left side with rubber posts (px ~150, py 490-790 region).

### Lower third (region 1)
Each slingshot is a 3-POST rubber triangle (posts = red rubber cylinders, rubber bands between them):
- Left sling posts:  top (-9.3, 11.0), bottom-outer (-9.3, 15.0), bottom-inner (-6.1, 16.5)
- Right sling posts: top (+9.3, 11.0), bottom-outer (+9.3, 15.0), bottom-inner (+6.1, 16.5)
- Kicking face = the inner edge (top post -> bottom-inner post), faces down-and-toward-center.
- Flippers: tips at x ~ +/-3.6, z 20 (pivots inboard, existing FLIPPER_PIVOT_SPREAD/Z).
- Inlane/outlane per side: an OUTER rail near x ~ +/-13.3 (outlane outer wall) and an inner divider
  rail ~ x +/-11.6 with a rubber post on top, splitting the return inlane (inner, feeds the flipper)
  from the outlane (outer, drains). z range ~ 3..7 for the posts, rails curve down toward the flipper.

## Region plan (developer chose: full faithful, region by region)
1. Lower third: 3-post rubber slingshots + curved inlane/outlane guides.  <- IN PROGRESS
2. Upper field: top orbit rail + 5 standup targets + tightened/raised 3-bumper triangle + return guides.
3. Left target bank + rubber posts.

Each region: build to the numbers above, run the full GUT suite on Godot 4.7 locally, push to main,
deploy, screenshot, and let the developer react before the next region.

## Markup measurements (2026-06-21, developer's hand-drawn plan)

Andrew marked up the bottom-up render (legend: black=borders, orange=inlane walls, purple=targets,
grey=ball, yellow=bumpers, 2 black blobs=flippers, blue dots=pins with black fill between=guides).
Measured via a 4-corner homography from that perspective view to table coords (not eyeballed):

- Bumpers (3, triangle apex-down): (-4.8, -8.3), (2.1, -8.3), (-1.4, -4.0)
- Targets: upper pair (-8.4, -12.4) & (5.7, -12.4); RIGHT vertical bank of 4 at x~8.5, z -2.3..+2.1;
  LEFT single (-11.4, +2.1)
- Inlane walls (orange): (-9.9, +13.3) and (+7.2, +13.4)
- Guides (blue pins + black fill): top-left return (-8.5, -16), top-right return (+6.4, -13.6);
  mid side rails (~ +/-11, z+1); slingshot triangles (-8.0, +11.4) & (+5.4, +11.3); wall-hugging
  pins near x +/-14..15 (z +5..+7).
- Build back onto the flat play area one verified piece at a time (no overlap). See [[rapid-layout-loop]].
