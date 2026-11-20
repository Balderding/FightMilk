"""Draws our own exercise icons: one SVG per <pattern>_<equipment> used in exercises.json.

A figure in the movement's pose (light grey, thick round strokes) plus the equipment glyph in
its colour: barbell/smith teal, dumbbell/kettlebell gold, machine green, cable light blue.
64x64 viewBox, transparent background, readable at 44 px. Licence: CC BY-SA 4.0 (balderding).
Run: python tools/gen_icons.py
"""
import json, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIB = json.loads((ROOT / "app/assets/exercises.json").read_text())
OUT = ROOT / "app/assets/icons"
OUT.mkdir(parents=True, exist_ok=True)

FIG = "#dfe7ec"
COL = {"barbell": "#2ec4b6", "smith": "#2ec4b6", "dumbbell": "#f2c14e", "kettlebell": "#f2c14e",
       "machine": "#7bd389", "cable": "#8ecae6", "bodyweight": "#93a4b1", "band": "#c3a6ff"}

# Pose = head centre, list of polylines (body), hands (where equipment goes), optional prop lines
# (bench/floor/pad, drawn dim), and a hint for how the equipment sits ("bar","pair","up","none").
P = {
 "press":   dict(head=(13, 37), body=[[(18, 38), (40, 38), (48, 38), (50, 52)], [(19, 38), (19, 28), (19, 18)]], hands=[(19, 17)], prop=[[(10, 43), (44, 43)], [(14, 43), (14, 54)], [(40, 43), (40, 54)]], kind="bar_side"),
 "incline": dict(head=(17, 26), body=[[(21, 30), (38, 42), (48, 42), (50, 55)], [(22, 31), (24, 21), (24, 12)]], hands=[(24, 11)], prop=[[(16, 33), (38, 47)], [(36, 47), (36, 56)]], kind="bar_side"),
 "fly":     dict(head=(32, 46), body=[[(32, 41), (32, 22)], [(32, 36), (20, 30), (12, 22)], [(32, 36), (44, 30), (52, 22)]], hands=[(12, 22), (52, 22)], prop=[[(26, 54), (38, 54)]], kind="pair"),
 "dip":     dict(head=(32, 10), body=[[(32, 15), (32, 36), (32, 46), (26, 54)], [(32, 19), (22, 22), (22, 34)], [(32, 19), (42, 22), (42, 34)]], hands=[(22, 35), (42, 35)], prop=[[(14, 36), (24, 36)], [(40, 36), (50, 36)], [(16, 36), (16, 60)], [(48, 36), (48, 60)]], kind="handles"),
 "overhead":dict(head=(32, 18), body=[[(32, 23), (32, 42), (27, 58)], [(32, 42), (37, 58)], [(32, 26), (22, 20), (22, 9)], [(32, 26), (42, 20), (42, 9)]], hands=[(22, 8), (42, 8)], prop=[], kind="bar_front"),
 "lateral": dict(head=(32, 13), body=[[(32, 18), (32, 38), (27, 58)], [(32, 38), (37, 58)], [(32, 22), (20, 23), (9, 24)], [(32, 22), (44, 23), (55, 24)]], hands=[(9, 24), (55, 24)], prop=[], kind="pair"),
 "rear":    dict(head=(15, 26), body=[[(20, 28), (38, 32), (40, 45), (38, 58)], [(24, 29), (14, 38)], [(26, 30), (36, 22)]], hands=[(14, 39), (36, 21)], prop=[], kind="pair"),
 "row":     dict(head=(14, 25), body=[[(19, 27), (38, 32), (41, 45), (38, 58)], [(24, 29), (30, 35), (24, 42)]], hands=[(24, 43)], prop=[], kind="bar_side"),
 "pulldown":dict(head=(32, 22), body=[[(32, 27), (32, 42), (44, 42), (44, 57)], [(32, 30), (22, 20), (22, 9)], [(32, 30), (42, 20), (42, 9)]], hands=[(22, 8), (42, 8)], prop=[[(24, 46), (46, 46)]], kind="bar_front"),
 "pullover":dict(head=(24, 36), body=[[(29, 38), (46, 38), (52, 50)], [(28, 38), (18, 32), (8, 30)]], hands=[(8, 30)], prop=[[(18, 43), (50, 43)], [(46, 43), (46, 54)]], kind="one"),
 "squat":   dict(head=(30, 15), body=[[(30, 20), (23, 37), (39, 40), (33, 58)], [(28, 24), (36, 24)]], hands=[(31, 22)], prop=[], kind="bar_side"),
 "legpress":dict(head=(13, 40), body=[[(17, 42), (30, 46), (38, 30), (48, 26)], [(20, 43), (26, 50)]], hands=[(48, 26)], prop=[[(10, 50), (34, 50)], [(46, 18), (54, 34)]], kind="plate"),
 "lunge":   dict(head=(31, 11), body=[[(31, 16), (31, 34), (42, 42), (42, 58)], [(31, 34), (22, 46), (14, 56)], [(31, 20), (28, 30), (28, 38)]], hands=[(28, 39)], prop=[], kind="one"),
 "hinge":   dict(head=(42, 19), body=[[(37, 23), (25, 33), (29, 46), (27, 58)], [(34, 26), (35, 36), (35, 45)]], hands=[(35, 46)], prop=[], kind="bar_side"),
 "thrust":  dict(head=(10, 34), body=[[(15, 36), (32, 30), (44, 34), (48, 50)], [(32, 30), (32, 27)]], hands=[(32, 28)], prop=[[(6, 40), (18, 40)], [(8, 40), (8, 56)], [(40, 52), (56, 52)]], kind="bar_side"),
 "kickback":dict(head=(16, 22), body=[[(21, 25), (34, 32), (36, 46), (36, 58)], [(34, 32), (48, 28), (58, 22)], [(24, 27), (22, 40)]], hands=[(58, 22)], prop=[], kind="ankle"),
 "abduction":dict(head=(32, 14), body=[[(32, 19), (32, 36)], [(32, 36), (20, 44), (14, 56)], [(32, 36), (44, 44), (50, 56)]], hands=[(14, 50), (50, 50)], prop=[[(22, 38), (42, 38)]], kind="pads"),
 "legext":  dict(head=(22, 14), body=[[(22, 19), (22, 38), (36, 38), (50, 30)]], hands=[(50, 30)], prop=[[(16, 42), (38, 42)], [(18, 18), (18, 42)], [(30, 42), (30, 58)]], kind="pad"),
 "legcurl": dict(head=(8, 36), body=[[(13, 38), (36, 38), (46, 26)]], hands=[(46, 26)], prop=[[(6, 43), (40, 43)], [(12, 43), (12, 56)], [(36, 43), (36, 56)]], kind="pad"),
 "calf":    dict(head=(32, 10), body=[[(32, 15), (32, 36), (31, 52), (33, 56)], [(32, 36), (35, 52), (37, 56)], [(32, 19), (27, 28), (29, 34)]], hands=[(29, 35)], prop=[[(24, 58), (44, 58)]], kind="one"),
 "adduction":dict(head=(32, 14), body=[[(32, 19), (32, 36)], [(32, 36), (25, 46), (22, 56)], [(32, 36), (39, 46), (42, 56)]], hands=[(22, 50), (42, 50)], prop=[[(22, 38), (42, 38)]], kind="pads"),
 "curl":    dict(head=(30, 11), body=[[(30, 16), (30, 37), (26, 58)], [(30, 37), (34, 58)], [(30, 20), (30, 31), (40, 24)]], hands=[(41, 23)], prop=[], kind="one"),
 "pushdown":dict(head=(30, 11), body=[[(30, 16), (30, 37), (26, 58)], [(30, 37), (34, 58)], [(30, 20), (31, 30), (39, 38)]], hands=[(40, 39)], prop=[], kind="one"),
 "overhead_ext": dict(head=(30, 16), body=[[(30, 21), (30, 40), (26, 58)], [(30, 40), (34, 58)], [(30, 24), (32, 10), (22, 12)]], hands=[(21, 13)], prop=[], kind="one"),
 "shrug":   dict(head=(32, 11), body=[[(32, 16), (32, 37), (27, 58)], [(32, 37), (37, 58)], [(32, 18), (24, 22), (22, 38)], [(32, 18), (40, 22), (42, 38)]], hands=[(22, 39), (42, 39)], prop=[], kind="pair_down"),
 "carry":   dict(head=(30, 11), body=[[(30, 16), (30, 37), (22, 57)], [(30, 37), (38, 57)], [(30, 20), (22, 26), (21, 38)], [(30, 20), (38, 26), (39, 38)]], hands=[(21, 39), (39, 39)], prop=[], kind="pair_down"),
 "wristcurl":dict(head=(14, 22), body=[[(16, 27), (20, 42), (34, 42), (34, 58)], [(18, 30), (30, 36), (42, 36), (48, 32)]], hands=[(49, 31)], prop=[[(26, 40), (46, 40)]], kind="one"),
 "crunch":  dict(head=(18, 26), body=[[(22, 30), (32, 42), (44, 38), (50, 50)], [(22, 30), (26, 22)]], hands=[(27, 21)], prop=[[(12, 54), (56, 54)]], kind="one"),
 "legraise":dict(head=(32, 18), body=[[(32, 23), (32, 38), (48, 38), (50, 48)], [(32, 25), (26, 14), (26, 6)], [(32, 25), (38, 14), (38, 6)]], hands=[(26, 6), (38, 6)], prop=[[(16, 5), (48, 5)]], kind="none"),
 "pushup":  dict(head=(12, 30), body=[[(17, 33), (40, 39), (56, 47)], [(20, 34), (20, 44), (20, 52)]], hands=[(20, 52)], prop=[[(8, 54), (60, 54)]], kind="none"),
 "frontraise": dict(head=(26, 12), body=[[(26, 17), (26, 38), (22, 58)], [(26, 38), (30, 58)], [(26, 21), (40, 21), (52, 20)]], hands=[(53, 20)], prop=[], kind="one"),
 "rotation": dict(head=(32, 12), body=[[(32, 17), (32, 37), (26, 58)], [(32, 37), (38, 58)], [(32, 21), (42, 26), (50, 30)], [(32, 21), (40, 28), (50, 31)]], hands=[(51, 30)], prop=[], kind="one"),
 "olympic": dict(head=(32, 16), body=[[(32, 21), (31, 38), (24, 46), (27, 58)], [(31, 38), (38, 46), (37, 58)], [(32, 24), (24, 22), (24, 12)], [(32, 24), (40, 22), (40, 12)]], hands=[(24, 11), (40, 11)], prop=[], kind="bar_front"),
 "plank":   dict(head=(12, 32), body=[[(17, 34), (52, 40), (56, 50)], [(20, 35), (20, 48), (26, 48)]], hands=[(26, 48)], prop=[[(8, 52), (60, 52)]], kind="none"),
}

def poly(pts, color, w):
    d = " ".join(f"{x},{y}" for x, y in pts)
    return f'<polyline points="{d}" fill="none" stroke="{color}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'

def equip(eq, pose):
    c = COL[eq]; k = pose["kind"]; hs = pose["hands"]; out = []
    if eq == "bodyweight" or k == "none":
        return out
    if eq == "machine":
        out.append(f'<rect x="3" y="3" width="58" height="58" rx="6" fill="none" stroke="{c}" stroke-width="2.5" opacity=".55"/>')
        for x, y in hs:
            out.append(f'<rect x="{x-4}" y="{y-3}" width="8" height="6" rx="2" fill="{c}"/>')
        return out
    if eq == "cable":
        out.append(f'<circle cx="56" cy="8" r="4" fill="none" stroke="{c}" stroke-width="2.5"/>')
        for x, y in hs:
            out.append(poly([(56, 8), (x, y)], c, 2))
            out.append(f'<circle cx="{x}" cy="{y}" r="3" fill="{c}"/>')
        return out
    if eq == "band":
        for x, y in hs:
            out.append(f'<path d="M{x},{y} Q{x+6},{(y+60)//2} {x},60" fill="none" stroke="{c}" stroke-width="2.5"/>')
            out.append(f'<circle cx="{x}" cy="{y}" r="3" fill="{c}"/>')
        return out
    if eq == "smith":
        out.append(poly([(6, 2), (6, 62)], c, 2)); out.append(poly([(58, 2), (58, 62)], c, 2))
    for x, y in hs:
        if eq in ("barbell", "smith"):
            if k in ("bar_front",):
                out.append(poly([(6, y), (58, y)], c, 3))
                out.append(f'<rect x="4" y="{y-7}" width="5" height="14" rx="1.5" fill="{c}"/><rect x="55" y="{y-7}" width="5" height="14" rx="1.5" fill="{c}"/>')
            else:  # bar seen end-on: a plate disc
                out.append(f'<circle cx="{x}" cy="{y}" r="7" fill="none" stroke="{c}" stroke-width="3"/><circle cx="{x}" cy="{y}" r="2" fill="{c}"/>')
        elif eq == "kettlebell":
            out.append(f'<circle cx="{x}" cy="{y+5}" r="5" fill="{c}"/><path d="M{x-3},{y+1} Q{x},{y-4} {x+3},{y+1}" fill="none" stroke="{c}" stroke-width="2"/>')
        else:  # dumbbell
            out.append(poly([(x-5, y), (x+5, y)], c, 2.5))
            out.append(f'<rect x="{x-8}" y="{y-4}" width="4" height="8" rx="1" fill="{c}"/><rect x="{x+4}" y="{y-4}" width="4" height="8" rx="1" fill="{c}"/>')
        if k in ("bar_front",) and eq in ("barbell", "smith"):
            break
    return out

def svg(pattern, eq):
    pose = P[pattern]
    parts = []
    for pr in pose["prop"]:
        parts.append(poly(pr, "#5b6b77", 3))
    parts += equip(eq, pose) if eq == "machine" else []
    hx, hy = pose["head"]
    for b in pose["body"]:
        parts.append(poly(b, FIG, 4.5))
    parts.append(f'<circle cx="{hx}" cy="{hy}" r="4.5" fill="{FIG}"/>')
    if eq != "machine":
        parts += equip(eq, pose)
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' + "".join(parts) + "</svg>\n"

def main():
  made = set()
  for e in LIB["exercises"]:
    if e["icon"] in made:
        continue
    (OUT / f'{e["icon"]}.svg').write_text(svg(e["pattern"], e["equipment"]))
    made.add(e["icon"])
  print(len(made), "icons ->", OUT)


if __name__ == "__main__":
    main()
