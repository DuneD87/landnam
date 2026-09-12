"""Compile shaders and run the GPU regression scene without loading the game.

Usage: python tools/water/test_underwater_compositor.py --godot PATH_TO_GODOT
Creates an isolated temporary project; leaves its log and PNGs for inspection.
"""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile
import re

ROOT = Path(__file__).resolve().parents[2]


def main():
    os.sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--benchmark", action="store_true")
    args = parser.parse_args()
    subprocess.run([os.sys.executable, str(ROOT / "tools/water/build_underwater_shared.py"), "--check"], check=True)
    workspace = Path(tempfile.mkdtemp(prefix="underwater-gpu-"))
    for folder in ("shaders/liquid", "shaders/atmosphere", "shaders/lib", "shaders/materials"):
        shutil.copytree(ROOT / folder, workspace / folder)
    for name in ("scripts/atmosphere/planet_atmosphere.gd", "scripts/water/underwater_render_pass.gd",
                 "tests/water/test_underwater_compositor.gd", "tests/water/benchmark_underwater.gd", "data/resources/underwater_layout.json"):
        destination = workspace / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    (workspace / "project.godot").write_text('''config_version=5
[application]
config/name="Underwater GPU Regression"
[display]
window/size/viewport_width=320
window/size/viewport_height=180
window/vsync/vsync_mode=0
[rendering]
renderer/rendering_method="gl_compatibility"
''', encoding="utf-8")
    def expand(path):
        source = path.read_text(encoding="utf-8")
        return re.sub(r'#include "([^"]+)"', lambda m: expand(path.parent / m[1]), source)
    for name, folder in (("underwater_surface_cache", "liquid"), ("planet_atmosphere", "atmosphere"), ("god_rays", "atmosphere")):
        source = expand(workspace / f"shaders/{folder}/{name}.glsl").replace("#[compute]", "")
        temp = workspace / f"{name}.comp"
        temp.write_text(source, encoding="utf-8")
        subprocess.run(["glslangValidator", "-V", str(temp), "-o", str(workspace / f"{name}.spv")], check=True)
    print(f"GPU test project: {workspace}", flush=True)
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with (workspace / "import.log").open("w", encoding="utf-8") as log:
        subprocess.run([args.godot, "--headless", "--path", str(workspace), "--editor", "--quit"],
                       stdout=log, stderr=subprocess.STDOUT, timeout=120, creationflags=flags, check=True)
    with (workspace / "gpu.log").open("w", encoding="utf-8") as log:
        result = subprocess.run([args.godot, "--path", str(workspace), "--rendering-method", "forward_plus",
            "--rendering-driver", "vulkan", "--position", "-32000,-32000",
            "--script", "res://tests/water/benchmark_underwater.gd" if args.benchmark else "res://tests/water/test_underwater_compositor.gd"],
            stdout=log, stderr=subprocess.STDOUT, timeout=180, creationflags=flags)
    output = (workspace / "gpu.log").read_text(encoding="utf-8")
    print(output)
    marker = "UNDERWATER_BENCHMARK_DONE" if args.benchmark else "UNDERWATER_RESULT failures=0"
    assert result.returncode == 0 and marker in output
    assert "SCRIPT ERROR" not in output and "ERROR:" not in output


if __name__ == "__main__":
    main()
