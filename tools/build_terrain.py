#!/usr/bin/env python3
"""Crop an SRTM HGT tile into an offline OpenStrike heightmap region."""

from __future__ import annotations

import argparse
import gzip
import json
import math
import struct
from pathlib import Path

import numpy as np
from PIL import Image


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="SRTM .hgt or .hgt.gz tile")
    parser.add_argument("metadata", type=Path, help="Region JSON to update")
    parser.add_argument("--latitude", type=float, required=True)
    parser.add_argument("--longitude", type=float, required=True)
    parser.add_argument("--size-metres", type=float, default=4000.0)
    parser.add_argument("--resolution", type=int, default=129)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--albedo-output", type=Path)
    parser.add_argument("--normal-output", type=Path)
    parser.add_argument("--texture-resolution", type=int, default=2048)
    return parser.parse_args()


def read_tile(path: Path) -> tuple[list[int], int]:
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rb") as source:
        data = source.read()
    sample_count = len(data) // 2
    side = math.isqrt(sample_count)
    if side * side != sample_count:
        raise ValueError(f"Unexpected HGT byte size: {len(data)}")
    return list(struct.unpack(f">{sample_count}h", data)), side


def tile_origin(path: Path) -> tuple[int, int]:
    name = path.name.split(".")[0].upper()
    latitude = int(name[1:3]) * (-1 if name[0] == "S" else 1)
    longitude = int(name[4:7]) * (-1 if name[3] == "W" else 1)
    return latitude, longitude


def bilinear(samples: list[int], side: int, row: float, column: float) -> float:
    row = max(0.0, min(side - 1.0, row))
    column = max(0.0, min(side - 1.0, column))
    r0, c0 = int(row), int(column)
    r1, c1 = min(r0 + 1, side - 1), min(c0 + 1, side - 1)
    dr, dc = row - r0, column - c0
    a = samples[r0 * side + c0]
    b = samples[r0 * side + c1]
    c = samples[r1 * side + c0]
    d = samples[r1 * side + c1]
    if min(a, b, c, d) <= -32768:
        return 0.0
    return (a * (1 - dc) + b * dc) * (1 - dr) + (c * (1 - dc) + d * dc) * dr


def resized_float(field: np.ndarray, size: int) -> np.ndarray:
    image = Image.fromarray(field.astype(np.float32), mode="F")
    return np.asarray(image.resize((size, size), Image.Resampling.BICUBIC), dtype=np.float32)


def value_noise(size: int, grid: int, seed: int) -> np.ndarray:
    random = np.random.default_rng(seed)
    source = (random.random((grid, grid)) * 255.0).astype(np.uint8)
    image = Image.fromarray(source, mode="L").resize((size, size), Image.Resampling.BICUBIC)
    return np.asarray(image, dtype=np.float32) / 255.0


def build_surface_textures(
    elevations: np.ndarray,
    world_size_m: float,
    albedo_path: Path,
    normal_path: Path,
    texture_size: int,
) -> None:
    height = resized_float(elevations, texture_size)
    low, high = float(height.min()), float(height.max())
    height_norm = np.clip((height - low) / max(high - low, 1.0), 0.0, 1.0)
    metres_per_pixel = world_size_m / max(texture_size - 1, 1)
    dz, dx = np.gradient(height, metres_per_pixel)
    slope = np.clip(np.hypot(dx, dz), 0.0, 1.0)
    macro = value_noise(texture_size, 18, 7401)
    medium = value_noise(texture_size, 72, 7402)
    fine = value_noise(texture_size, 280, 7403)
    noise = macro * 0.48 + medium * 0.34 + fine * 0.18

    dry = np.array([151.0, 126.0, 66.0], dtype=np.float32)
    soil = np.array([116.0, 91.0, 52.0], dtype=np.float32)
    vegetation = np.array([73.0, 91.0, 43.0], dtype=np.float32)
    rock = np.array([111.0, 105.0, 91.0], dtype=np.float32)
    base_mix = np.clip(height_norm * 0.55 + noise * 0.45, 0.0, 1.0)[..., None]
    colour = dry * (1.0 - base_mix) + soil * base_mix
    vegetation_weight = np.clip((0.78 - height_norm) * 1.8 - slope * 1.2 + (noise - 0.48), 0.0, 1.0)[..., None]
    colour = colour * (1.0 - vegetation_weight) + vegetation * vegetation_weight
    rock_weight = np.clip(slope * 2.7 + height_norm * 0.7 - 0.72 + (medium - 0.5) * 0.25, 0.0, 1.0)[..., None]
    colour = colour * (1.0 - rock_weight) + rock * rock_weight
    colour *= (0.88 + fine[..., None] * 0.24)
    albedo_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(colour, 0, 255).astype(np.uint8), mode="RGB").save(albedo_path, optimize=True)

    detail_height = height + (medium - 0.5) * 5.0 + (fine - 0.5) * 1.4
    normal_dz, normal_dx = np.gradient(detail_height, metres_per_pixel)
    nx = -normal_dx * 1.35
    ny = np.ones_like(nx)
    nz = -normal_dz * 1.35
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack((nx / length, ny / length, nz / length), axis=-1)
    encoded_normal = np.clip((normal * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    normal_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(encoded_normal, mode="RGB").save(normal_path, optimize=True)


def main() -> None:
    args = arguments()
    samples, side = read_tile(args.source)
    south, west = tile_origin(args.source)
    north = south + 1.0
    half_lat = (args.size_metres * 0.5) / 111_320.0
    half_lon = half_lat / math.cos(math.radians(args.latitude))
    elevations: list[float] = []
    for y in range(args.resolution):
        v = y / (args.resolution - 1)
        latitude = args.latitude + half_lat - v * half_lat * 2.0
        row = (north - latitude) * (side - 1)
        for x in range(args.resolution):
            u = x / (args.resolution - 1)
            longitude = args.longitude - half_lon + u * half_lon * 2.0
            column = (longitude - west) * (side - 1)
            elevations.append(bilinear(samples, side, row, column))
    minimum, maximum = min(elevations), max(elevations)
    span = max(maximum - minimum, 1.0)
    encoded = bytes(round((value - minimum) / span * 255.0) for value in elevations)
    elevation_array = np.asarray(elevations, dtype=np.float32).reshape(args.resolution, args.resolution)
    image = Image.frombytes("L", (args.resolution, args.resolution), encoded)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output)
    albedo_output = args.albedo_output or args.output.with_name("albedo.png")
    normal_output = args.normal_output or args.output.with_name("normal.png")
    build_surface_textures(
        elevation_array,
        args.size_metres,
        albedo_output,
        normal_output,
        args.texture_resolution,
    )
    metadata = json.loads(args.metadata.read_text())
    metadata.update(
        elevation_min_m=round(minimum, 2),
        elevation_max_m=round(maximum, 2),
        generated=True,
        heightmap_resolution=args.resolution,
        surface_texture_resolution=args.texture_resolution,
    )
    args.metadata.write_text(json.dumps(metadata, indent=2) + "\n")
    print(
        f"Wrote {args.output} ({args.resolution}x{args.resolution}, {minimum:.1f}m..{maximum:.1f}m) "
        f"and {args.texture_resolution}px surface textures"
    )


if __name__ == "__main__":
    main()
