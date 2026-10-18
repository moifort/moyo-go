// Kifu phone stand: holds an iPhone 17 Pro beside a goban, ultra-wide lens
// looking down at the board. Geometry comes from geometry.py (params.scad).
//
// World frame: the board's side face is x = 0, the board extends towards -x,
// the stand stands on the table (z = 0) at +x. y runs along the board edge.
//
// Parts (render with -D 'part="..."'):
//   base       tongue under the board + column, printed upright
//   extension  column segment, printed socket end down (only when needed)
//   head       tilted saddle with the tenon, printed lying on its side
//   frame      phone cradle, printed back face down
//   assembly   everything in place, with the phone and the board edge

include <params.scad>

part = "assembly";

// --- Printer ------------------------------------------------------------------
max_print_h = 255;          // Bambu Lab X2D: 256 x 256 x 261

// --- Column and joint ---------------------------------------------------------
col_x = 20;                 // column section along x
col_y = 40;                 // column section along y
socket_x = 12;
socket_y = 32;
socket_depth = 30;
joint_play = 0.25;          // per side, tenon vs socket

// --- Base ---------------------------------------------------------------------
tongue_depth = 80;          // under the board
tongue_w = 120;
tongue_t = 2.4;
base_out = 130;             // outside the board
base_w = 140;
base_t = 8;
gusset_h = 60;

// --- Frame (phone cradle) -----------------------------------------------------
frame_w = 160;              // along the board edge
frame_len = 100;            // along the slope
frame_t = 6;
wall_t = 4.5;               // end walls
rail_h = 10;                // walls and lip rail, above the frame's front face
rail_t = 6;                 // lip rail, along the slope
pad_len = 20;               // lip pads at both ends (button-free zones of the phone)
lip_recess = 2;             // lip set back between the pads
window_w = 46;              // camera plateau window, from each end wall
window_len = 78;            // from the lip up the slope
usb_w = 14;
boss_s = [11, 35];          // head boss along the slope
boss_u = 44;                // head boss across
boss_h = 3;
pocket_play = 0.3;

// --- Derived ------------------------------------------------------------------
phi = phone_slope;                                  // phone plane from horizontal
lens_above_lip = lens_from_side * sin(phi);
lens_z = lens_h_above_board + board_thickness;      // lens above the table
lip_z = lens_z - lens_above_lip;                    // phone's lower edge, frame front
lip_x = lens_d + lens_from_side * cos(phi);
col_cx = lens_d;                                    // column axis under the lens
head_out_x = lip_x;                                 // head spans [head_out_x - head_len, head_out_x]
head_len = 42;
head_clear = 10;                                    // head height at its outer, lowest end
back_z_at_lip = lip_z - frame_t * cos(phi);         // frame back plane, at the lip edge
column_top = back_z_at_lip - head_clear;
base_h = min(column_top, max_print_h);
ext_h = column_top - base_h;

echo(str("lens ", lens_z, " mm above the table, column top ", column_top,
         ", base ", base_h, ", extension ", ext_h));

// Frame local coordinates (s along the slope from the lip, u across, n towards
// the phone) to world.
module at_frame() {
    translate([lip_x, 0, lip_z]) rotate([0, phi, 0]) mirror([1, 0, 0]) children();
}

module socket_cut(z_top) {
    translate([col_cx - socket_x / 2, -socket_y / 2, z_top - socket_depth])
        cube([socket_x, socket_y, socket_depth + 1]);
}

module tenon(z_top) {
    translate([col_cx - socket_x / 2 + joint_play, -socket_y / 2 + joint_play, z_top - socket_depth + 1])
        cube([socket_x - 2 * joint_play, socket_y - 2 * joint_play, socket_depth - 1]);
}

module base() {
    difference() {
        union() {
            // tongue under the board
            translate([-tongue_depth, -tongue_w / 2, 0]) cube([tongue_depth, tongue_w, tongue_t]);
            // outer base plate
            translate([0, -base_w / 2, 0]) cube([base_out, base_w, base_t]);
            // column
            translate([col_cx - col_x / 2, -col_y / 2, 0]) cube([col_x, col_y, base_h]);
            // gusset outwards
            hull() {
                translate([col_cx + col_x / 2 - 1, -col_y / 2, base_t]) cube([1, col_y, gusset_h]);
                translate([col_cx + col_x / 2, -col_y / 2, base_t]) cube([gusset_h, col_y, 1]);
            }
            // gussets sideways
            for (sy = [-1, 1]) hull() {
                translate([col_cx - col_x / 2, sy * col_y / 2 - (sy < 0 ? 1 : 0), base_t]) cube([col_x, 1, gusset_h]);
                translate([col_cx - col_x / 2, sy < 0 ? -col_y / 2 - 35 : col_y / 2, base_t]) cube([col_x, 35, 1]);
            }
        }
        socket_cut(base_h);
    }
}

module extension() {
    union() {
        difference() {
            translate([col_cx - col_x / 2, -col_y / 2, base_h]) cube([col_x, col_y, ext_h]);
            socket_cut(base_h + ext_h);
        }
        tenon(base_h);
    }
}

// Half space below the frame's back plane (local n <= -frame_t), in world.
module below_frame_back() {
    at_frame() translate([-500, -500, -frame_t - 500]) cube([1000, 1000, 500]);
}

module head() {
    union() {
        intersection() {
            translate([head_out_x - head_len, -col_y / 2, column_top]) cube([head_len, col_y, 200]);
            below_frame_back();
        }
        // boss locating the frame
        at_frame() translate([boss_s[0], -boss_u / 2, -frame_t - 0.01])
            cube([boss_s[1] - boss_s[0], boss_u, boss_h + 0.01]);
        tenon(column_top);
    }
}

// Frame in local coordinates: s = x, u = y (centred), n = z.
module frame_local() {
    difference() {
        union() {
            // plate
            translate([0, -frame_w / 2, -frame_t]) cube([frame_len, frame_w, frame_t]);
            // lip rail
            translate([-rail_t, -frame_w / 2, -frame_t]) cube([rail_t, frame_w, frame_t + rail_h]);
            // end walls
            for (sy = [-1, 1])
                translate([-rail_t, sy > 0 ? frame_w / 2 - wall_t : -frame_w / 2, -frame_t])
                    cube([frame_len + rail_t, wall_t, frame_t + rail_h]);
        }
        // lip recess between the pads, so no button is pressed in landscape
        translate([-lip_recess, -frame_w / 2 + wall_t + pad_len, 0])
            cube([lip_recess + 1, frame_w - 2 * (wall_t + pad_len), rail_h + 1]);
        // USB-C notch in the lip (portrait) and in the end walls (landscape)
        translate([-rail_t - 1, -usb_w / 2, -1]) cube([rail_t + 2, usb_w, rail_h + 2]);
        for (sy = [-1, 1])
            translate([(phone_w - usb_w) / 2, sy > 0 ? frame_w / 2 - wall_t - 1 : -frame_w / 2 - 1, -1])
                cube([usb_w, wall_t + 2, rail_h + 2]);
        // camera plateau windows at both ends
        for (sy = [-1, 1])
            translate([0, sy > 0 ? frame_w / 2 - wall_t - window_w : -frame_w / 2 + wall_t, -frame_t - 1])
                cube([window_len, window_w, frame_t + 2]);
        // pocket for the head's boss
        translate([boss_s[0] - pocket_play, -boss_u / 2 - pocket_play, -frame_t - 1])
            cube([boss_s[1] - boss_s[0] + 2 * pocket_play, boss_u + 2 * pocket_play, boss_h + pocket_play + 1]);
    }
}

module frame() { at_frame() frame_local(); }

// Phone in landscape, lens-side long edge on the lip, camera end at -u.
module phone_local() {
    color("DimGray") translate([0, -phone_l / 2, 0]) cube([phone_w, phone_l, phone_t]);
    color("DarkSlateGray") translate([0, -phone_l / 2, -plateau_protrusion])
        cube([phone_w, plateau_from_top, plateau_protrusion]);
    color("Black") translate([lens_from_side, -phone_l / 2 + lens_from_top, -plateau_protrusion - 0.5])
        cylinder(d = 12, h = 1, $fn = 32);
}

module board_edge() {
    color("BurlyWood") translate([-200, -260, 0]) cube([200, 520, board_thickness]);
}

module assembly() {
    color("SteelBlue") base();
    if (ext_h > 0) color("CadetBlue") extension();
    color("DarkOrange") head();
    color("Gold") frame();
    at_frame() phone_local();
    board_edge();
}

if (part == "base") base();
else if (part == "extension") extension();
else if (part == "head") head();
else if (part == "frame") frame_local();
else assembly();
