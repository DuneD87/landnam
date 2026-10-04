#!/usr/bin/env python3
"""Bake linear terrain maps: R=roughness, G=AO, B=height (requires Pillow)."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
IMPORT_SETTINGS = '''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{resource}"

[params]

compress/mode=2
compress/high_quality=true
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/size_limit=0
detect_3d/compress_to=0
'''


def local(resource: str) -> Path:
    if not resource.startswith("res://"):
        raise ValueError(f"Expected res:// path: {resource}")
    return ROOT / resource[6:]


def jobs(configs: list[Path]) -> dict[str, tuple[str, str, str | None]]:
    result = {}
    reefs = []
    for config_path in configs:
        config = json.loads(config_path.read_text())
        biome = config["biome_settings"]
        arrays = [biome[key] for key in ("packed_material_textures", "roughness_textures", "ao_textures", "height_textures")]
        if any(len(array) != len(biome["textures"]) for array in arrays):
            raise ValueError(f"Mismatched material arrays: {config_path}")
        entries = list(zip(*arrays))
        entries.append((biome["slope_packed_material_texture"], biome["slope_roughness_texture"],
                        biome["slope_ao_texture"], biome["slope_height_texture"]))
        for output, roughness, ao, height in entries:
            sources = (roughness, ao, height)
            if output in result and result[output] != sources:
                raise ValueError(f"Conflicting sources for {output}")
            result[output] = sources
        reef = config.get("reef_settings", {})
        if "packed_material_texture" in reef:
            reefs.append(reef)
    for reef in reefs:
        output = reef["packed_material_texture"]
        sources = (reef["roughness_texture"], reef["ao_texture"])
        if output in result:
            if result[output][:2] != sources:
                raise ValueError(f"Conflicting reef sources for {output}")
        else:
            result[output] = (*sources, None)
    return result


def packed_image(sources: tuple[str, str, str | None]) -> Image.Image:
    channels = []
    for source in sources:
        if source is None:
            channels.append(Image.new("L", channels[0].size, 128))
        else:
            with Image.open(local(source)) as image:
                channels.append(image.convert("RGB").getchannel("R"))
    if len({channel.size for channel in channels}) != 1:
        raise ValueError(f"Source sizes differ: {sources}")
    return Image.merge("RGB", channels)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configs", nargs="*", type=Path, default=[ROOT / "data/planet/planet_earth.json", ROOT / "data/planet/planet_moon.json"])
    parser.add_argument("--check", action="store_true", help="Verify every channel against its source without writing files")
    args = parser.parse_args()
    materials = jobs(args.configs)
    for resource, sources in materials.items():
        output = local(resource)
        expected = packed_image(sources)
        if args.check:
            with Image.open(output) as actual:
                if actual.mode != "RGB" or actual.size != expected.size or ImageChops.difference(actual, expected).getbbox():
                    raise ValueError(f"Outdated packed map: {output}")
            settings = output.with_suffix(output.suffix + ".import").read_text()
            for setting in ("compress/mode=2", "compress/high_quality=true", "mipmaps/generate=true", "compress/normal_map=0"):
                if setting not in settings:
                    raise ValueError(f"Wrong import settings for {output}: {setting}")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            expected.save(output)
            import_file = output.with_suffix(output.suffix + ".import")
            # Preserve Godot's generated UID and import metadata on later bakes.
            if not import_file.exists():
                import_file.write_text(IMPORT_SETTINGS.format(resource=resource))
        print(f"{'Checked' if args.check else 'Packed'} {resource} ({expected.width}×{expected.height})")
    print(f"{len(materials)} unique materials")


if __name__ == "__main__":
    main()
