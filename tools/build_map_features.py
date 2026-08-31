#!/usr/bin/env python3
"""Convert a bounded OSM Overpass extract into offline OpenStrike map features."""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

import numpy as np


METRES_PER_LATITUDE_DEGREE = 111_320.0


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Overpass JSON containing building and coastline ways")
    parser.add_argument("--latitude", type=float, required=True)
    parser.add_argument("--longitude", type=float, required=True)
    parser.add_argument("--world-size", type=float, default=4000.0)
    parser.add_argument("--buildings-output", type=Path, required=True)
    parser.add_argument("--coastline-output", type=Path, required=True)
    return parser.parse_args()


def local_point(latitude: float, longitude: float, center_latitude: float, center_longitude: float) -> tuple[float, float]:
    metres_per_longitude_degree = METRES_PER_LATITUDE_DEGREE * math.cos(math.radians(center_latitude))
    x = (longitude - center_longitude) * metres_per_longitude_degree
    z = (center_latitude - latitude) * METRES_PER_LATITUDE_DEGREE
    return x, z


def numeric_tag(value: object) -> float | None:
    if value is None:
        return None
    match = re.search(r"-?\d+(?:\.\d+)?", str(value))
    return float(match.group(0)) if match else None


def building_height(tags: dict[str, object], footprint_area: float) -> float:
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


def oriented_footprint(points: list[tuple[float, float]]) -> tuple[float, float, float, float, float, float]:
    values = np.asarray(points, dtype=np.float64)
    centroid = values.mean(axis=0)
    centered = values - centroid
    covariance = np.cov(centered.T)
    eigenvalues, eigenvectors = np.linalg.eigh(covariance)
    major = eigenvectors[:, int(np.argmax(eigenvalues))]
    minor = np.array([-major[1], major[0]])
    major_projection = centered @ major
    minor_projection = centered @ minor
    width = float(major_projection.max() - major_projection.min())
    depth = float(minor_projection.max() - minor_projection.min())
    box_center = centroid
    box_center = box_center + major * float((major_projection.max() + major_projection.min()) * 0.5)
    box_center = box_center + minor * float((minor_projection.max() + minor_projection.min()) * 0.5)
    # Godot yaw rotates the local X axis toward -Z for positive angles.
    yaw = math.atan2(-float(major[1]), float(major[0]))
    area = width * depth
    return float(box_center[0]), float(box_center[1]), width, depth, yaw, area


def interpolate_at_z(a: tuple[float, float], b: tuple[float, float], target_z: float) -> tuple[float, float]:
    if abs(b[1] - a[1]) < 1e-9:
        return a[0], target_z
    t = (target_z - a[1]) / (b[1] - a[1])
    return a[0] + (b[0] - a[0]) * t, target_z


def clip_coastline(points: list[tuple[float, float]], half_size: float) -> list[tuple[float, float]]:
    clipped: list[tuple[float, float]] = []
    for a, b in zip(points, points[1:]):
        a_inside = -half_size <= a[1] <= half_size
        b_inside = -half_size <= b[1] <= half_size
        if a_inside and not clipped:
            clipped.append(a)
        if a_inside and b_inside:
            clipped.append(b)
        elif a_inside != b_inside:
            boundary = half_size if (b[1] > half_size or a[1] > half_size) else -half_size
            crossing = interpolate_at_z(a, b, boundary)
            clipped.append(crossing)
            if b_inside:
                clipped.append(b)
    # The source way may run south-to-north. Sort into north-to-south screen order,
    # and thin points that are much closer than the terrain resolution needs.
    clipped.sort(key=lambda point: point[1])
    thinned: list[tuple[float, float]] = []
    for point in clipped:
        if not thinned or math.dist(point, thinned[-1]) >= 6.0:
            thinned.append(point)
    if clipped and (not thinned or thinned[-1] != clipped[-1]):
        thinned.append(clipped[-1])
    return thinned


def x_at_z(points: list[tuple[float, float]], target_z: float) -> float:
    for a, b in zip(points, points[1:]):
        if min(a[1], b[1]) <= target_z <= max(a[1], b[1]):
            return interpolate_at_z(a, b, target_z)[0]
    return min(points, key=lambda point: abs(point[1] - target_z))[0]


def main() -> None:
    args = arguments()
    extract = json.loads(args.source.read_text())
    half_size = args.world_size * 0.5
    margin = 35.0
    buildings: list[dict[str, object]] = []
    coast_candidates: list[list[tuple[float, float]]] = []

    for element in extract.get("elements", []):
        if element.get("type") != "way" or not element.get("geometry"):
            continue
        tags = element.get("tags", {})
        points = [
            local_point(float(node["lat"]), float(node["lon"]), args.latitude, args.longitude)
            for node in element["geometry"]
        ]
        if tags.get("natural") == "coastline":
            coast_candidates.append(points)
            continue
        if "building" not in tags or len(points) < 3:
            continue
        footprint = points[:-1] if points[0] == points[-1] else points
        center_x, center_z, width, depth, yaw, area = oriented_footprint(footprint)
        if not (-half_size + margin <= center_x <= half_size - margin and -half_size + margin <= center_z <= half_size - margin):
            continue
        if width < 2.0 or depth < 2.0 or area < 16.0:
            continue
        height = building_height(tags, area)
        buildings.append({
            "x": round(center_x, 2),
            "z": round(center_z, 2),
            "width": round(width, 2),
            "depth": round(depth, 2),
            "height": round(height, 2),
            "yaw": round(yaw, 5),
            "osm_id": int(element["id"]),
            "footprint": [[round(x, 2), round(z, 2)] for x, z in footprint],
        })

    if not coast_candidates:
        raise ValueError("No coastline way found in extract")
    coastline = clip_coastline(max(coast_candidates, key=len), half_size)
    coast_x = x_at_z(coastline, 0.0)
    # Start above the open beach, inland of the mapped water edge but east of the towers.
    spawn_x = coast_x - 30.0
    spawn_z = 0.0

    common = {
        "source": "OpenStreetMap",
        "attribution": "© OpenStreetMap contributors",
        "license": "Open Database License (ODbL)",
        "center_latitude": args.latitude,
        "center_longitude": args.longitude,
    }
    building_payload = common | {"buildings": buildings}
    coastline_payload = common | {
        "ocean_side": "east",
        "world_east_x": half_size,
        "points": [[round(x, 2), round(z, 2)] for x, z in coastline],
        "spawn": {"x": round(spawn_x, 2), "z": round(spawn_z, 2)},
    }
    args.buildings_output.parent.mkdir(parents=True, exist_ok=True)
    args.coastline_output.parent.mkdir(parents=True, exist_ok=True)
    args.buildings_output.write_text(json.dumps(building_payload, separators=(",", ":")) + "\n")
    args.coastline_output.write_text(json.dumps(coastline_payload, separators=(",", ":")) + "\n")
    print(
        f"Wrote {len(buildings)} positioned buildings and {len(coastline)} coastline points; "
        f"beach spawn x={spawn_x:.1f}, z={spawn_z:.1f}"
    )


if __name__ == "__main__":
    main()
