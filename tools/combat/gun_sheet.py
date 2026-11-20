#!/usr/bin/env python3
"""Before/after picture sheets of the guns, one per family, for reviewing a change to
their models (tools/robot/weapons.py) without opening the game.

    python3 tools/combat/gun_sheet.py OUT_DIR BEFORE.glb [AFTER.glb]

BEFORE.glb: a robot's model file from before the change (for example
`git show main:game/player/robot/needle.glb > /tmp/before.glb`). AFTER.glb: the one to
show beside it (default: the game's own needle.glb as it is now). Each row is one gun:
as it was, as it is, and as it is from a three-quarter view. Writes OUT_DIR/<family>.png.
"""
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FAMILIES = [
    ("Sidearms", [("pistol", "Pistol"), ("revolver", "Revolver"), ("golden_gun", "Golden Gun"), ("machine_pistol", "Machine Pistol"),
                  ("akimbo", "Dual Pistols")]),
    ("Shotguns", [("shotgun", "Shotgun"), ("break_action", "Break-Action Shotgun"), ("air_cannon", "Air Cannon")]),
    ("Automatics", [("rifle", "Assault Rifle"), ("burst_rifle", "Burst Rifle"), ("battle_rifle", "Battle Rifle"),
                    ("lmg", "Light Machine Gun"), ("minigun", "Minigun")]),
    ("Precision", [("lever_action", "Lever-Action Rifle"), ("anti_materiel", "Anti-Materiel Rifle"),
                   ("railgun", "Railgun"), ("crossbow", "Crossbow")]),
    ("Heavies", [("rocket_launcher", "Rocket Launcher"), ("grenade_launcher", "Grenade Launcher")]),
]
CELL = (640, 280)
HEAD = 64
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    out = os.path.abspath(sys.argv[1])
    before = os.path.abspath(sys.argv[2])
    after = os.path.abspath(sys.argv[3]) if len(sys.argv) > 3 else "res://game/player/robot/needle.glb"
    shots = os.path.join(out, "_shots")
    guns = [g for _, family in FAMILIES for g, _ in family]
    subprocess.run([os.path.join(ROOT, "tools", "combat", "gun_preview.sh"), shots, "--guns=" + ",".join(guns),
                    "--glb=" + after, "--before=" + before], check=True, stdout=subprocess.DEVNULL)
    big = ImageFont.truetype(FONT, 30)
    small = ImageFont.truetype(FONT, 22)
    for family, rows in FAMILIES:
        sheet = Image.new("RGB", (CELL[0] * 3, HEAD + CELL[1] * len(rows)), (38, 41, 48))
        d = ImageDraw.Draw(sheet)
        d.text((16, 16), family, font=big, fill=(255, 255, 255))
        for c, title in enumerate(("Before", "After", "After, from the front")):
            d.text((CELL[0] * c + CELL[0] // 2, 20), title, font=small, fill=(200, 205, 215), anchor="ma")
        for r, (gun, name) in enumerate(rows):
            y = HEAD + r * CELL[1]
            for c, f in enumerate(("%s_before_side.png", "%s_side.png", "%s_quarter.png")):
                sheet.paste(Image.open(os.path.join(shots, f % gun)).resize(CELL, Image.LANCZOS), (c * CELL[0], y))
            d.text((12, y + 8), name, font=small, fill=(255, 255, 255), stroke_width=2, stroke_fill=(40, 44, 52))
            d.line([(0, y), (sheet.width, y)], fill=(38, 41, 48), width=2)
        path = os.path.join(out, family.lower() + ".png")
        sheet.save(path)
        print(path)


if __name__ == "__main__":
    main()
