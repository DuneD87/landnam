"""Builds every style of tools/character/hair_tool_styles.json (docs/hair_tool.md).

    python3 tools/character/blender/hair_tool_build.py [--only a,b] [--render] [--no-assets] [--textures]

1. Blender 4.5 + MPFB: the base head (hair_tool_base.py), once.
2. Blender 5.2, per style: preset -> cards on that head (hair_tool_convert.py).
3. Blender 4.5 + MPFB: cards -> MakeHuman assets ht_<name> (hair_tool_mhclo.py).

Everything goes to build/character/hair_tool/lib/; the assets to MPFB's user
data, where export_mpfb_human.py finds them. No step opens a window.
--textures only refreshes the assets' textures (the cards do not change, so
their anchors stand): step 3 takes ~25 minutes.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / "tools/character/blender"
BLENDER_45 = Path(os.environ.get("BLENDER_45", "/home/drive/tools/blender-4.5.14-linux-x64/blender"))
BLENDER_52 = Path(os.environ.get("BLENDER_52", "/home/drive/tools/blender-5.2.3-linux-x64/blender"))
LIBRARY = Path(os.environ.get("HAIR_TOOL_LIBRARY", "/home/drive/tools/hair_tool_library/HairLibrary_52"))
OUT = ROOT / "build/character/hair_tool/lib"


def styles():
    data = json.loads((ROOT / "tools/character/hair_tool_styles.json").read_text())
    for kind, group in (("hair", "styles"), ("beard", "beards")):
        for style in data[group].values():
            style.setdefault("budget", data["budget"][kind])
            style.setdefault("spread", data["spread"][kind])
    return {**data["styles"], **data["beards"]}


def run(command, log):
    with open(log, "w") as f:
        result = subprocess.run([str(c) for c in command], stdout=f, stderr=subprocess.STDOUT, timeout=1800)
    text = Path(log).read_text()
    if result.returncode != 0 or "Traceback" in text:
        sys.exit("Failed, see %s" % log)
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--no-assets", action="store_true")
    parser.add_argument("--textures", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "logs").mkdir(exist_ok=True)
    base = OUT / "mh_base.blend"
    if not base.exists():
        run([BLENDER_45, "-b", "--python", TOOLS / "hair_tool_base.py", "--", base], OUT / "logs/base.log")
    todo = styles()
    if args.only:
        todo = {k: v for k, v in todo.items() if k in args.only.split(",")}
    for name, style in todo.items():
        command = [BLENDER_52, "-b", "--factory-startup", LIBRARY / (style["preset"] + ".blend"),
                   "--python", TOOLS / "hair_tool_convert.py", "--", base, OUT, name,
                   "--keep", style.get("keep", 1.0), "--budget", style["budget"],
                   "--unsubdivide", style.get("unsubdivide", 1), "--spread", style["spread"]]
        if style.get("extra"):
            command += ["--extra"] + [e + ".blend" for e in style["extra"]]
        if style.get("noise"):
            command += ["--noise", style["noise"]]
        if style.get("region"):
            command += ["--region", style["region"]]
        if style.get("objects"):
            command += ["--objects", ",".join(style["objects"])]
        if args.render:
            command.append("--render")
        text = run(command, OUT / "logs" / (name + ".log"))
        report = json.loads(text.split("HAIR_TOOL_REPORT ", 1)[1].splitlines()[0])
        print("%-20s %6d tris  keep %.2f  atlas %s  dropped %d" % (
            name, report["triangles"], report["keep"], ",".join(report["atlas"]), report["dropped_faces"]), flush=True)
    if args.textures:
        data = Path.home() / ".config/blender/4.5/extensions/.user/blender_org/mpfb/data"
        for name in todo:
            folder = data / ("clothes" if name.startswith("beard_") else "hair") / ("ht_" + name)
            shutil.copyfile(OUT / (name + "_atlas.png"), folder / ("ht_%s_diffuse.png" % name))
        print("Textures refreshed for", len(todo), "styles")
    elif not args.no_assets:
        run([BLENDER_45, "-b", "--python", TOOLS / "hair_tool_mhclo.py", "--", OUT] + list(todo),
            OUT / "logs/assets.log")
        print("Assets written for", len(todo), "styles")


main()
