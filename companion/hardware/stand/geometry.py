#!/usr/bin/env python3
"""Camera geometry for the Kifu phone stand.

Models an iPhone 17 Pro rear camera placed beside a 19x19 goban, looking down at
the board at an angle, and finds the lens heights at which the whole grid (plus a
stone's worth of margin) fits inside the frame.

Frame of reference (millimetres):
  - board top surface is z = 0, the board's near side face is x = 0
  - the board extends towards -x, the stand sits on the table at +x
  - the lens is at (d, 0, h): d outside the board edge (negative = overhanging)
  - the optical axis points towards -x, tilted `alpha` degrees below horizontal

Run:  python3 geometry.py            # table + chosen design
      python3 geometry.py --scad     # also writes params.scad for stand.scad
"""
import math
import sys

# --- iPhone 17 Pro ----------------------------------------------------------
# Body 150.0 x 71.9 x 8.75 mm, 204-206 g (Apple spec page / theapplewiki).
PHONE_L, PHONE_W, PHONE_T = 150.0, 71.9, 8.75
# Rear cameras: Fusion Main 24 mm equiv f/1.78, Fusion Ultra Wide 13 mm equiv f/2.2,
# both 48 MP on a 4:3 sensor. AVFoundation returns geometric-distortion-corrected
# frames for the ultra wide; the usable rectilinear horizontal field of view is
# a little under the raw 36/13 figure (108.5 deg). Values below are conservative.
LENSES = {
    "ultra-wide": {"hfov": 106.0, "px_w": 4032},  # 13 mm equiv, "120 deg" diagonal
    "main":       {"hfov": 72.0,  "px_w": 4032},  # 24 mm equiv
}
# Ultra wide lens centre on the back, portrait, seen from the back, measured from
# the top edge and from the left edge. Approximate (bottom-left lens of the
# triangle on the camera plateau); the cradle window is generous around it.
LENS_FROM_TOP = 30.0
LENS_FROM_SIDE = 17.0
PLATEAU_FROM_TOP = 42.0   # camera plateau spans the full width, this tall
PLATEAU_PROTRUSION = 4.5

# --- Goban -------------------------------------------------------------------
BOARD_LONG, BOARD_SHORT = 455.0, 424.0       # Japanese table goban
PITCH_LONG, PITCH_SHORT = 23.7, 22.0         # line spacing
LINES = 19
STONE_D = 22.0
BOARD_THICKNESS = 60.0                       # Thibaut's board, table to top surface
MARGIN = STONE_D / 2 + 14                    # grid edge -> must-see edge
FRAME_MARGIN = 0.92                          # keep the region 8 % inside the frame edge

# The phone sits on the long side of the board (the harder case for width).
GRID_ACROSS = (LINES - 1) * PITCH_LONG       # along the edge the phone faces
GRID_DEPTH = (LINES - 1) * PITCH_SHORT       # away from the phone
EDGE_TO_GRID_ACROSS = (BOARD_LONG - GRID_ACROSS) / 2
EDGE_TO_GRID_DEPTH = (BOARD_SHORT - GRID_DEPTH) / 2
# Must-see region on the board plane.
REGION_HALF_W = GRID_ACROSS / 2 + MARGIN
REGION_NEAR = -(EDGE_TO_GRID_DEPTH - MARGIN)   # x of the near must-see edge (<= 0)
REGION_FAR = -(EDGE_TO_GRID_DEPTH + GRID_DEPTH + MARGIN)

# Chosen design: ultra wide, landscape, lens straight above the column.
DESIGN_D = 25.0       # lens this far outside the board edge
DESIGN_H = 300.0      # lens height above the board surface
DESIGN_ALPHA = 60.0   # optical axis below horizontal -> phone 30 deg from horizontal


def half_tans(lens, landscape):
    th = math.tan(math.radians(LENSES[lens]["hfov"] / 2))
    tv = th * 3 / 4
    return (th, tv) if landscape else (tv, th)


def project(px, py, d, h, alpha):
    """Image coordinates (x/f, y/f) of board point (px, py, 0) and its depth."""
    a = math.radians(alpha)
    vx, vy, vz = px - d, py, -h
    depth = -vx * math.cos(a) - vz * math.sin(a)
    up = -vx * math.sin(a) + vz * math.cos(a)
    return vy / depth, up / depth, depth


def fits(lens, landscape, d, h, alpha):
    th, tv = half_tans(lens, landscape)
    corners = [(REGION_NEAR, -REGION_HALF_W), (REGION_NEAR, REGION_HALF_W),
               (REGION_FAR, -REGION_HALF_W), (REGION_FAR, REGION_HALF_W)]
    worst = 0.0
    for px, py in corners:
        xi, yi, depth = project(px, py, d, h, alpha)
        if depth <= 0:
            return False, 9.0
        worst = max(worst, abs(xi) / th, abs(yi) / tv)
    return worst <= FRAME_MARGIN, worst


def best_alpha(lens, landscape, d, h):
    """Axis tilt that centres the region vertically, and whether it all fits."""
    near = math.degrees(math.atan2(h, d - REGION_NEAR))
    far = math.degrees(math.atan2(h, d - REGION_FAR))
    alpha = (near + far) / 2
    ok, worst = fits(lens, landscape, d, h, alpha)
    return alpha, ok, worst


def far_elevation(d, h):
    return math.degrees(math.atan2(h, d - REGION_FAR))


def px_per_cell_far(lens, landscape, d, h, alpha):
    """Pixels between two neighbouring far-row intersections, across and along."""
    th, _ = half_tans(lens, landscape)
    long_px = LENSES[lens]["px_w"]
    f_px = (long_px / 2) / th if landscape else (long_px * 3 / 4 / 2) / th
    xfar = REGION_FAR + MARGIN
    x0, y0, _ = project(xfar, 0, d, h, alpha)
    x1, _, _ = project(xfar, PITCH_LONG, d, h, alpha)
    _, y2, _ = project(xfar + PITCH_SHORT, 0, d, h, alpha)
    return abs(x1 - x0) * f_px, abs(y2 - y0) * f_px


def scan(lens, landscape, heights, ds):
    """For each lens height, the smallest d that fits, and the far-edge elevation."""
    rows = []
    for h in heights:
        for d in ds:
            alpha, ok, _ = best_alpha(lens, landscape, d, h)
            if ok:
                across, along = px_per_cell_far(lens, landscape, d, h, alpha)
                rows.append((h, d, alpha, far_elevation(d, h), across, along))
                break
    return rows


def main():
    heights = range(150, 451, 25)
    ds = range(-60, 301, 5)
    print(f"must-see region: {2 * REGION_HALF_W:.0f} mm across, "
          f"{REGION_NEAR - REGION_FAR:.0f} mm deep, starting {-REGION_NEAR:.0f} mm inside the edge")
    for lens in ("ultra-wide", "main"):
        for landscape in (True, False):
            name = f"{lens} {'landscape' if landscape else 'portrait'}"
            print(f"\n{name}: smallest lens offset d that frames the board, per lens height h")
            print("   h(mm)   d(mm)  tilt  far-edge  px/cell far (across, along)")
            for h, d, alpha, elev, across, along in scan(lens, landscape, heights, ds):
                print(f"  {h:5.0f}  {d:6.0f}  {alpha:4.0f}  {elev:6.1f}   {across:5.0f} {along:5.0f}")

    lens, landscape = "ultra-wide", True
    d, h, alpha = DESIGN_D, DESIGN_H, DESIGN_ALPHA
    ok, worst = fits(lens, landscape, d, h, alpha)
    across, along = px_per_cell_far(lens, landscape, d, h, alpha)
    print(f"\nDESIGN  {lens} landscape: d={d} h={h} tilt={alpha}"
          f"  fits={ok} worst={worst:.2f} far-edge={far_elevation(d, h):.1f} deg"
          f"  near-edge={math.degrees(math.atan2(h, d - REGION_NEAR)):.1f} deg"
          f"  px/cell far={across:.0f}x{along:.0f}")
    phone_slope = 90 - alpha
    lens_above_lip = LENS_FROM_SIDE * math.sin(math.radians(phone_slope))
    lip_z = h + BOARD_THICKNESS - lens_above_lip
    print(f"phone slope from horizontal {phone_slope} deg, lip {lip_z:.0f} mm above the table "
          f"for a {BOARD_THICKNESS:.0f} mm thick board; lens {h + BOARD_THICKNESS:.0f} mm above the table")
    if "--scad" in sys.argv:
        with open("params.scad", "w") as f:
            f.write("// Generated by geometry.py, do not edit.\n")
            f.write(f"phone_l = {PHONE_L};\nphone_w = {PHONE_W};\nphone_t = {PHONE_T};\n")
            f.write(f"plateau_from_top = {PLATEAU_FROM_TOP};\nplateau_protrusion = {PLATEAU_PROTRUSION};\n")
            f.write(f"lens_from_side = {LENS_FROM_SIDE};\nlens_from_top = {LENS_FROM_TOP};\n")
            f.write(f"phone_slope = {phone_slope};\n")
            f.write(f"lens_d = {d};\nlens_h_above_board = {h};\n")
            f.write(f"board_thickness = {BOARD_THICKNESS};\n")
        print("wrote params.scad")


if __name__ == "__main__":
    main()
