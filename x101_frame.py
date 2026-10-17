#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Parametric lightweight replacement frame for the MJX X101 quadcopter.

Design goals
------------
* Minimal plastic. Stiffness comes from tall vertical webs (T-beam logic),
  not from thick plates. Nothing is solid that does not have to be.
* Printable flat on the bed with ZERO support material. Every surface is
  either on the bed, vertical, or the top of a feature.
* Tuned for PETG: wall thicknesses are integer multiples of a 0.4 mm nozzle
  so the slicer prints them fully solid with perimeters only (0% infill).
* Reuses the stock motor modules, propellers and landing legs.

Print orientation: as modelled. Z=0 is the bed. No supports.

Run:  python x101_frame.py
Out:  x101_frame_base.stl, x101_frame_cover.stl
"""

import math
import struct
import os

# =====================================================================
#  P A R A M E T E R S
#  Lines marked [VERIFY] MUST be measured on your own drone before
#  printing. The defaults are plausible placeholders, NOT measured data.
# =====================================================================

# ---- overall geometry -------------------------------------------------
MOTOR_DIAG      = 320.0   # [VERIFY] prop-shaft to opposite prop-shaft, mm

# ---- motor module sleeve ---------------------------------------------
SLEEVE_BORE     = 16.0    # [VERIFY] outer dia of the stock motor pod barrel
SLEEVE_FIT      = 0.25    # clearance added to the bore
SLEEVE_WALL     = 2.0     # 5 x 0.4 mm
SLEEVE_H        = 22.0    # [VERIFY] pod body height / insertion depth

# ---- central deck -----------------------------------------------------
DECK_X          = 72.0    # [VERIFY] deck width  (clear board + battery)
DECK_Y          = 92.0    # [VERIFY] deck length
DECK_T          = 1.6     # 4 x 0.4 mm  -- deck plate thickness
BAND_W          = 9.0     # perimeter band width (the deck is a frame)

# ---- spars (the two full-length diagonal beams) -----------------------
WEB_T           = 1.6     # 4 x 0.4 mm
FLANGE_T        = 1.6
WEB_H_DECK      = 3.0     # web height while crossing the deck: stays low so
                          # it cannot foul the board or the battery
WEB_H_ARM       = 12.0    # web height on the arm -- load-bearing value
WEB_H_MID       = 9.0
WEB_H_SLEEVE    = 16.0    # braces the tall sleeve tube
FL_W_DECK       = 13.0    # flange width at centre
FL_W_MID        = 7.0
FL_W_SLEEVE     = 11.0

# ---- flight controller board -----------------------------------------
BOARD_DX        = 26.0    # [VERIFY] board hole spacing across X
BOARD_DY        = 34.0    # [VERIFY] board hole spacing along Y
BOARD_SCREW     = 2.0     # M2 self-tapper
POST_H          = 8.0
POST_OD         = 5.2

# ---- battery ----------------------------------------------------------
BATT_X          = 32.0    # [VERIFY] battery width
BATT_PAD_H      = 4.0     # lifts the battery clear of the 3 mm centre rib
BATT_LUG_H      = 5.0
STRAP_W         = 13.0    # velcro strap width -> slot width

# ---- landing legs -----------------------------------------------------
LEG_BOSS        = True    # [VERIFY] screw bosses for the stock legs
LEG_BOSS_OD     = 6.4
LEG_BOSS_SCREW  = 2.0
LEG_BOSS_H      = 10.0

# ---- cover ------------------------------------------------------------
COVER_T         = 1.0
COVER_SKIRT_T   = 1.2     # 3 x 0.4
COVER_SKIRT_H   = 9.0
COVER_CLEAR     = 0.3

# ---- material ---------------------------------------------------------
PETG_DENSITY    = 1.27    # g/cm3
SEG             = 48      # circle resolution
NSEG            = 14      # taper segments per spar half

# =====================================================================
#  G E O M E T R Y   K E R N E L
# =====================================================================

def V(x, y, z):
    """Quantised vertex, so shared corners compare equal."""
    return (round(float(x), 6), round(float(y), 6), round(float(z), 6))


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def hex8(b, t):
    """Hexahedron from 4 bottom verts (CCW seen from +Z) and 4 top verts."""
    f = [(b[0], b[2], b[1]), (b[0], b[3], b[2]),          # bottom, -Z
         (t[0], t[1], t[2]), (t[0], t[2], t[3])]          # top, +Z
    for i in range(4):
        j = (i + 1) % 4
        f.append((b[i], b[j], t[j]))
        f.append((b[i], t[j], t[i]))
    return f


def box(x0, y0, z0, x1, y1, z1):
    b = [V(x0, y0, z0), V(x1, y0, z0), V(x1, y1, z0), V(x0, y1, z0)]
    t = [V(x0, y0, z1), V(x1, y0, z1), V(x1, y1, z1), V(x0, y1, z1)]
    return hex8(b, t)


def tube(cx, cy, z0, z1, r_out, r_in, seg=SEG):
    """Closed annular cylinder. r_in must be > 0."""
    assert r_in > 0.0 and r_out > r_in, "bad tube radii"
    O0, O1, I0, I1 = [], [], [], []
    for i in range(seg):
        a = 2.0 * math.pi * i / seg
        co, si = math.cos(a), math.sin(a)
        O0.append(V(cx + r_out * co, cy + r_out * si, z0))
        O1.append(V(cx + r_out * co, cy + r_out * si, z1))
        I0.append(V(cx + r_in * co, cy + r_in * si, z0))
        I1.append(V(cx + r_in * co, cy + r_in * si, z1))
    f = []
    for i in range(seg):
        j = (i + 1) % seg
        f.append((O0[i], O0[j], O1[j]))          # outer wall
        f.append((O0[i], O1[j], O1[i]))
        f.append((I0[j], I0[i], I1[i]))          # inner wall
        f.append((I0[j], I1[i], I1[j]))
        f.append((O1[i], O1[j], I1[j]))          # top annulus
        f.append((O1[i], I1[j], I1[i]))
        f.append((O0[i], I0[j], O0[j]))          # bottom annulus
        f.append((O0[i], I0[i], I0[j]))
    return f


def interp(pts, s):
    """Piecewise-linear lookup over [(s, value), ...] sorted by s."""
    if s <= pts[0][0]:
        return pts[0][1]
    for (s0, v0), (s1, v1) in zip(pts, pts[1:]):
        if s <= s1:
            return v0 + (v1 - v0) * (s - s0) / (s1 - s0)
    return pts[-1][1]


# =====================================================================
#  S O L I D   R E G I S T R Y   +   V A L I D A T I O N
# =====================================================================

class Model:
    def __init__(self, name):
        self.name = name
        self.solids = []      # (label, faces)

    def add(self, label, faces):
        self.solids.append((label, faces))

    def faces(self):
        out = []
        for _, f in self.solids:
            out.extend(f)
        return out

    @staticmethod
    def _volume(faces):
        v = 0.0
        for a, b, c in faces:
            v += _dot(a, _cross(b, c))
        return v / 6.0

    @staticmethod
    def _nonmanifold(faces):
        """Count unbalanced directed edges.

        A group is a union of individually closed solids that may share
        coincident faces, so an undirected edge can legitimately appear
        4 or 6 times. What must hold for a watertight, consistently
        oriented surface is that every directed edge a->b is matched by
        an edge b->a. Any imbalance is a real hole or a flipped face.
        """
        d = {}
        for tri in faces:
            for i in range(3):
                a, b = tri[i], tri[(i + 1) % 3]
                d[(a, b)] = d.get((a, b), 0) + 1
        bad = 0
        for (a, b), n in d.items():
            if n != d.get((b, a), 0):
                bad += 1
        return bad

    def report(self):
        print("\n  %-22s %12s %8s %6s" % (self.name, "volume", "mass", "open"))
        print("  " + "-" * 52)
        total = 0.0
        bad = 0
        for label, f in self.solids:
            vol = self._volume(f)
            nm = self._nonmanifold(f)
            bad += nm
            total += vol
            print("  %-22s %8.2f cm3 %6.1f g %6d" %
                  (label, vol / 1000.0, vol / 1000.0 * PETG_DENSITY, nm))
        print("  " + "-" * 52)
        print("  %-22s %8.2f cm3 %6.1f g %6d" %
              ("TOTAL", total / 1000.0,
               total / 1000.0 * PETG_DENSITY, bad))
        if bad:
            print("  !! %d non-manifold edges -- geometry bug" % bad)
        return total, bad

    def write_stl(self, path):
        faces = self.faces()
        with open(path, "wb") as fh:
            fh.write(b"\0" * 80)
            fh.write(struct.pack("<I", len(faces)))
            for a, b, c in faces:
                n = _cross(_sub(b, a), _sub(c, a))
                L = math.sqrt(_dot(n, n))
                n = (n[0] / L, n[1] / L, n[2] / L) if L > 1e-12 else (0., 0., 1.)
                fh.write(struct.pack("<12fH", n[0], n[1], n[2],
                                     a[0], a[1], a[2],
                                     b[0], b[1], b[2],
                                     c[0], c[1], c[2], 0))
        return len(faces)


# =====================================================================
#  D E R I V E D   G E O M E T R Y
# =====================================================================

R         = MOTOR_DIAG / 2.0
SLEEVE_IR = (SLEEVE_BORE + SLEEVE_FIT) / 2.0
SLEEVE_OR = SLEEVE_IR + SLEEVE_WALL

# where a 45 deg spar leaves the deck rectangle
_r_exit = min((DECK_X / 2.0) / math.cos(math.pi / 4),
              (DECK_Y / 2.0) / math.sin(math.pi / 4))
S_DECK  = _r_exit / R

# the web ends flush with the sleeve bore and never enters it
S_END   = (R - SLEEVE_IR) / R

H_PTS = [(0.0,            WEB_H_DECK),
         (S_DECK * 0.88,  WEB_H_DECK),
         (min(S_DECK + 0.09, S_END * 0.95), WEB_H_ARM),
         (0.74,           WEB_H_MID),
         (S_END,          WEB_H_SLEEVE)]

W_PTS = [(0.0,            FL_W_DECK),
         (S_DECK * 0.88,  FL_W_DECK),
         (0.74,           FL_W_MID),
         (S_END,          FL_W_SLEEVE)]

BAND_MID   = BAND_W / 2.0
FRONT_Y    = DECK_Y / 2.0 - BAND_MID          # front band centreline
RIB_Y      = FRONT_Y - BOARD_DY               # rib follows the board holes
BOARD_Y    = (FRONT_Y + RIB_Y) / 2.0
REAR_Y     = -DECK_Y / 2.0 + BAND_MID


# =====================================================================
#  T H E   F R A M E
# =====================================================================

def spar(model, ang_deg, tag):
    """One full-length diagonal beam: bottom flange + vertical web."""
    a = math.radians(ang_deg)
    ux, uy = math.cos(a), math.sin(a)
    vx, vy = -uy, ux

    def at(r, half, z):
        return V(ux * r + vx * half, uy * r + vy * half, z)

    flange, web = [], []
    for sign in (1.0, -1.0):
        for k in range(NSEG):
            s0 = S_END * k / NSEG
            s1 = S_END * (k + 1) / NSEG
            r0, r1 = sign * s0 * R, sign * s1 * R
            w0, w1 = interp(W_PTS, s0) / 2.0, interp(W_PTS, s1) / 2.0
            h0, h1 = interp(H_PTS, s0), interp(H_PTS, s1)
            o = sign  # keeps the plan-view winding CCW for both halves

            b = [at(r0, -w0 * o, 0.0), at(r1, -w1 * o, 0.0),
                 at(r1,  w1 * o, 0.0), at(r0,  w0 * o, 0.0)]
            t = [at(r0, -w0 * o, FLANGE_T), at(r1, -w1 * o, FLANGE_T),
                 at(r1,  w1 * o, FLANGE_T), at(r0,  w0 * o, FLANGE_T)]
            flange += hex8(b, t)

            q = WEB_T / 2.0
            b = [at(r0, -q * o, 0.0), at(r1, -q * o, 0.0),
                 at(r1,  q * o, 0.0), at(r0,  q * o, 0.0)]
            t = [at(r0, -q * o, h0), at(r1, -q * o, h1),
                 at(r1,  q * o, h1), at(r0,  q * o, h0)]
            web += hex8(b, t)

    model.add("spar %s flange" % tag, flange)
    model.add("spar %s web" % tag, web)


def build_base():
    m = Model("x101_frame_base")

    # ---- two diagonal spars, motor to motor -------------------------
    spar(m, 45.0, "A")
    spar(m, 135.0, "B")

    # ---- motor sleeves and leg bosses --------------------------------
    sleeves, bosses = [], []
    for ang in (45.0, 135.0, 225.0, 315.0):
        a = math.radians(ang)
        cx, cy = R * math.cos(a), R * math.sin(a)
        sleeves += tube(cx, cy, 0.0, SLEEVE_H, SLEEVE_OR, SLEEVE_IR)
        if LEG_BOSS:
            # outboard of the sleeve, on the same diagonal
            d = SLEEVE_OR + LEG_BOSS_OD / 2.0 - 1.2
            bx, by = cx + d * math.cos(a), cy + d * math.sin(a)
            bosses += tube(bx, by, 0.0, LEG_BOSS_H,
                           LEG_BOSS_OD / 2.0, BOARD_SCREW / 2.0 - 0.15, 32)
            # short web tying the boss back into the sleeve wall
            ex, ey = math.cos(a), math.sin(a)
            px, py = -ey * WEB_T / 2.0, ex * WEB_T / 2.0
            bq = [V(cx + ex * (SLEEVE_IR) + px, cy + ey * (SLEEVE_IR) + py, 0.0),
                  V(bx + px, by + py, 0.0),
                  V(bx - px, by - py, 0.0),
                  V(cx + ex * (SLEEVE_IR) - px, cy + ey * (SLEEVE_IR) - py, 0.0)]
            tq = [(v[0], v[1], LEG_BOSS_H) for v in bq]
            bosses += hex8(bq, tq)
    m.add("motor sleeves", sleeves)
    if LEG_BOSS:
        m.add("leg bosses", bosses)

    # ---- deck: perimeter band with strap slots -----------------------
    hx, hy = DECK_X / 2.0, DECK_Y / 2.0
    deck = []
    deck += box(-hx, hy - BAND_W, 0.0, hx, hy, DECK_T)        # front band
    deck += box(-hx, -hy, 0.0, hx, -hy + BAND_W, DECK_T)      # rear band

    # side bands split into segments, leaving two strap slots
    slot_c = [RIB_Y - (RIB_Y - REAR_Y) * 0.32,
              RIB_Y - (RIB_Y - REAR_Y) * 0.78]
    edges = [-hy + BAND_W]
    for c in sorted(slot_c):
        edges += [c - STRAP_W / 2.0, c + STRAP_W / 2.0]
    edges.append(hy - BAND_W)
    edges.sort()
    for k in range(0, len(edges) - 1, 2):
        y0, y1 = edges[k], edges[k + 1]
        if y1 - y0 <= 0.2:
            continue
        deck += box(-hx, y0, 0.0, -hx + BAND_W, y1, DECK_T)
        deck += box(hx - BAND_W, y0, 0.0, hx, y1, DECK_T)

    # centre rib, carries the rear pair of board screws
    deck += box(-hx, RIB_Y - BAND_MID, 0.0, hx, RIB_Y + BAND_MID, DECK_T)
    m.add("deck frame", deck)

    # ---- board posts -------------------------------------------------
    posts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            px = sx * BOARD_DX / 2.0
            py = BOARD_Y + sy * BOARD_DY / 2.0
            posts += tube(px, py, 0.0, DECK_T + POST_H,
                          POST_OD / 2.0, BOARD_SCREW / 2.0 - 0.15, 32)
    m.add("board posts", posts)

    # ---- battery pads and retention lugs -----------------------------
    batt = []
    for sx in (-1, 1):
        x_in = sx * BATT_X / 2.0
        x_out = x_in + sx * 1.6
        x0, x1 = min(x_in, x_out), max(x_in, x_out)
        for y in (RIB_Y, REAR_Y):
            y0, y1 = y - BAND_MID, y + BAND_MID
            batt += box(x0 - 2.0, y0, DECK_T,
                        x1 + 2.0, y1, DECK_T + BATT_PAD_H)
            batt += box(x0, y0, DECK_T + BATT_PAD_H,
                        x1, y1, DECK_T + BATT_PAD_H + BATT_LUG_H)
    m.add("battery mounts", batt)
    return m


def build_cover():
    """Minimal canopy over the board only. Print top-plate down, no supports."""
    m = Model("x101_frame_cover")
    hx = DECK_X / 2.0 - COVER_CLEAR
    y0 = RIB_Y - BAND_MID + COVER_CLEAR
    y1 = DECK_Y / 2.0 - COVER_CLEAR
    m.add("cover top", box(-hx, y0, 0.0, hx, y1, COVER_T))

    t = COVER_SKIRT_T
    z0, z1 = COVER_T, COVER_T + COVER_SKIRT_H
    skirt = box(-hx, y1 - t, z0, hx, y1, z1)                  # front skirt
    span = y1 - y0
    for ya, yb in ((y0, y0 + span * 0.30), (y1 - span * 0.30, y1)):
        skirt += box(-hx, ya, z0, -hx + t, yb, z1)
        skirt += box(hx - t, ya, z0, hx, yb, z1)
    m.add("cover skirt", skirt)
    return m


# =====================================================================
#  M A I N
# =====================================================================

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    print("MJX X101 lightweight frame -- parametric generator")
    print("  motor diagonal   %.1f mm" % MOTOR_DIAG)
    print("  sleeve bore      %.2f mm (pod %.1f + fit %.2f)"
          % (SLEEVE_BORE + SLEEVE_FIT, SLEEVE_BORE, SLEEVE_FIT))
    print("  deck             %.0f x %.0f mm" % (DECK_X, DECK_Y))
    print("  web ends at      s=%.3f R   deck exit s=%.3f" % (S_END, S_DECK))

    grand, errs = 0.0, 0
    for m in (build_base(), build_cover()):
        vol, bad = m.report()
        grand += vol
        errs += bad
        p = os.path.join(here, m.name + ".stl")
        n = m.write_stl(p)
        print("  -> %s  (%d triangles)" % (os.path.basename(p), n))

    print("\n  both parts: %.2f cm3  ~ %.0f g in PETG"
          % (grand / 1000.0, grand / 1000.0 * PETG_DENSITY))
    print("  volume sums overlapping solids, so it over-estimates slightly")
    print("  manifold check: %s" % ("OK" if errs == 0 else "%d BAD EDGES" % errs))
