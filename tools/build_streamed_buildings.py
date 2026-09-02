#!/usr/bin/env python3
"""Split an OSM building extract into per-chunk files for a streamed theatre.

The packaged theatres keep every building in one file, which is fine for 4 km
and 2,373 buildings. The original 36 km corridor building extract has 24,755;
it remains centred inside the expanded 50 km outer flight ring. Building them
all into one mesh at load would stall the game, so they are written per source
chunk and built only when that chunk is near enough to carry detail.

Unlike tools/build_map_features.py this emits only the fields the renderer
reads -- x, z, height, osm_id, footprint. That drops the numpy PCA (width,
depth and yaw are computed there but never used) and a chunk of file size.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from collections import defaultdict
from pathlib import Path

METRES_PER_LATITUDE_DEGREE = 111_320.0


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Overpass JSON with building ways (out tags geom)")
    parser.add_argument("--latitude", type=float, required=True, help="Region centre latitude")
    parser.add_argument("--longitude", type=float, required=True, help="Region centre longitude")
    parser.add_argument("--world-size", type=float, default=36000.0)
    parser.add_argument("--chunks", type=int, default=12, help="Chunks per side; must match streamed_terrain")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--min-area", type=float, default=16.0, help="Drop footprints smaller than this (m^2)")
    return parser.parse_args()


def local_point(latitude, longitude, center_latitude, center_longitude):
    metres_per_longitude_degree = METRES_PER_LATITUDE_DEGREE * math.cos(math.radians(center_latitude))
    return ((longitude - center_longitude) * metres_per_longitude_degree,
            (center_latitude - latitude) * METRES_PER_LATITUDE_DEGREE)


def numeric_tag(value):
    if value is None:
        return None
    match = re.search(r"-?\d+(?:\.\d+)?", str(value))
    return float(match.group(0)) if match else None


def building_height(tags, footprint_area):
    """Same inference as build_map_features.py, so packaged and streamed
    theatres give the same building the same height."""
    explicit = numeric_tag(tags.get("height"))
    if explicit is not None:
        return min(max(explicit, 3.0), 220.0)
    levels = numeric_tag(tags.get("building:levels"))
    if levels is not None:
        return min(max(levels * 3.15, 3.0), 220.0)
    kind = str(tags.get("building", "yes"))
    if kind in {"apartments", "hotel", "commercial", "office", "retail"}:
        return 18.0 if footprint_area > 350.0 else 11.0
    return 7.5


def polygon_area(points):
    """Shoelace. Replaces the numpy covariance work, which only existed to
    produce fields nothing reads."""
    total = 0.0
    for (x0, z0), (x1, z1) in zip(points, points[1:] + points[:1]):
        total += x0 * z1 - x1 * z0
    return abs(total) * 0.5


def main() -> None:
    args = arguments()
    extract = json.loads(args.source.read_text())
    half = args.world_size * 0.5
    chunk_size = args.world_size / float(args.chunks)
    per_chunk = defaultdict(list)
    skipped_outside = skipped_small = 0

    for element in extract.get("elements", []):
        if element.get("type") != "way" or not element.get("geometry"):
            continue
        tags = element.get("tags", {})
        if "building" not in tags:
            continue
        points = [local_point(float(n["lat"]), float(n["lon"]), args.latitude, args.longitude)
                  for n in element["geometry"]]
        if len(points) < 3:
            continue
        footprint = points[:-1] if points[0] == points[-1] else points
        if len(footprint) < 3:
            continue
        area = polygon_area(footprint)
        if area < args.min_area:
            skipped_small += 1
            continue
        center_x = sum(p[0] for p in footprint) / len(footprint)
        center_z = sum(p[1] for p in footprint) / len(footprint)
        if not (-half <= center_x <= half and -half <= center_z <= half):
            skipped_outside += 1
            continue
        cx = min(int((center_x + half) / chunk_size), args.chunks - 1)
        cz = min(int((center_z + half) / chunk_size), args.chunks - 1)
        per_chunk[(cx, cz)].append({
            "x": round(center_x, 2),
            "z": round(center_z, 2),
            "height": round(building_height(tags, area), 2),
            "osm_id": int(element["id"]),
            "footprint": [[round(x, 2), round(z, 2)] for x, z in footprint],
        })

    args.output_dir.mkdir(parents=True, exist_ok=True)
    common = {
        "source": "OpenStreetMap",
        "attribution": "© OpenStreetMap contributors",
        "license": "Open Database License (ODbL)",
    }
    written = total = 0
    for (cx, cz), buildings in sorted(per_chunk.items()):
        payload = common | {"chunk_x": cx, "chunk_z": cz, "buildings": buildings}
        path = args.output_dir / f"{cx}_{cz}.json"
        path.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
        written += 1
        total += len(buildings)

    occupied = sorted(per_chunk.items(), key=lambda kv: -len(kv[1]))
    print(f"Wrote {total} buildings across {written} of {args.chunks ** 2} chunks")
    print(f"  skipped: {skipped_small} below {args.min_area} m^2, {skipped_outside} outside the region")
    print("  busiest chunks: " + ", ".join(f"{cx}_{cz}={len(b)}" for (cx, cz), b in occupied[:5]))


if __name__ == "__main__":
    main()
