#!/usr/bin/env python3
"""Give every guessed building height a plausible one instead of a flat default.

The chunk builders infer height from OSM tags and fall back to a class default
when the tag is missing, which is why whole suburbs arrive as one number:
78.7% of Sydney Harbour sits at exactly 7.5 m, so a garage and a shop block
extrude the same and the city reads flat from the air.

Nothing here needs a re-fetch. The stored heights already say how much can be
trusted, because the builder wrote them:

  a multiple of 3.15  -- from a real `building:levels` tag
  any other value      -- from a real `height` tag
  7.5, 11.0, 18.0      -- the fallback guesses, and the only ones rewritten

So the tagged buildings are the reference data. Each guess is re-stated from
its own footprint (a 20 m^2 slab is a shed, 2500 m^2 over a city block is not)
and then pulled toward the tagged heights actually nearby, which is what makes
a terrace row agree with the terrace row beside it and lets an untagged
footprint in the CBD read as a tower. A guess with a tagged near-twin within
30 m takes that twin's height outright, which is the strongest signal here.

Jitter is a hash of the osm_id, never random: the same building gets the same
height on the next run, and no two sides of a street disagree because the
loader happened to visit them in a different order.

Marked by `height_model` in each chunk, so a re-run is a no-op until that
string is bumped. Originals are in git; pass --force to restate anyway.

  python3 tools/infer_building_heights.py --report
  python3 tools/infer_building_heights.py            # rewrite every theatre
  python3 tools/infer_building_heights.py --region au_nsw_sydney_harbour
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import math
import os
from collections import defaultdict
from pathlib import Path

MODEL_VERSION = "footprint+neighbourhood-v1"
GUESS_DEFAULTS = (7.5, 11.0, 18.0)
CELL_M = 96.0
NEIGHBOUR_CELLS = 2  # rings of cells => ~290 m radius
MIN_HEIGHT_M = 2.6
MAX_HEIGHT_M = 220.0

# (max footprint area m^2, base height m). Aussie housing stock, coarse on
# purpose: the neighbourhood term does the fine work. The tail turns back over
# because a 20,000 m^2 way is not a tower -- at that size OSM is describing a
# warehouse, a hangar or an airfield outline, which are big and low.
AREA_BANDS = [
    (28.0, 2.8),      # garage, shed, carport, pool plant
    (55.0, 3.4),      # small cottage, single storey
    (110.0, 5.4),     # house, single storey
    (190.0, 7.6),     # house, two storey
    (330.0, 9.0),     # large house, duplex
    (700.0, 10.5),    # terrace row, shop, small commercial
    (1500.0, 15.0),   # low-rise apartments, office
    (3500.0, 21.0),   # block of flats
    (8000.0, 24.0),   # civic block, hospital wing
    (float("inf"), 12.0),
]
# Beyond these, only a tower district may talk a footprint out of being a shed.
SLAB_AREA_M2 = 8000.0
MEGA_SLAB_AREA_M2 = 40000.0
SLAB_CEILING_M = 9.0
MEGA_SLAB_CEILING_M = 7.0
TOWER_DISTRICT_M = 30.0


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--regions-dir", type=Path, default=Path("data/regions"))
    parser.add_argument("--region", default=None, help="Only this theatre id")
    parser.add_argument("--report", action="store_true", help="Histograms only, write nothing")
    return parser.parse_args()


def jitter(osm_id: int, salt: int = 0) -> float:
    """Stable pseudo-random in [-1, 1] for one building."""
    digest = hashlib.sha256(f"{osm_id}:{salt}".encode()).digest()
    return (int.from_bytes(digest[:4], "big") / 0xFFFFFFFF) * 2.0 - 1.0


def footprint_area(points: list) -> float:
    total = 0.0
    for (x0, z0), (x1, z1) in zip(points, points[1:] + points[:1]):
        total += x0 * z1 - x1 * z0
    return abs(total) * 0.5


def area_prior(area: float) -> float:
    for ceiling, base in AREA_BANDS:
        if area <= ceiling:
            return base
    return AREA_BANDS[-1][1]


def is_guess(height: float) -> bool:
    return any(abs(height - value) < 0.01 for value in GUESS_DEFAULTS)


def is_tagged(height: float) -> bool:
    """True when the stored height came from an OSM tag rather than a default.

    A non-default value cannot have been written by the builder's fallback, so
    it is either a `building:levels` multiple of 3.15 or an explicit `height`.
    """
    return not is_guess(height)


def nearest_twin(area: float, neighbours: list) -> float:
    """A tagged building of similar footprint within 30 m is the best evidence
    there is: a terrace row is a terrace row all the way down it."""
    best = None
    wanted = area_prior(area)
    for (nx, nz, nh, narea, distance) in neighbours:
        if distance > 30.0 or not (area * 0.6 <= narea <= area * 1.6):
            continue
        score = distance + abs(nh - wanted) * 0.6
        if best is None or score < best[0]:
            best = (score, nh)
    return best[1] if best else -1.0


def district_profile(neighbours: list) -> tuple:
    """Median and 80th percentile of the tagged heights around a footprint."""
    near = sorted(h for (_, _, h, _, d) in neighbours if d <= 150.0)
    if len(near) < 4:
        near = sorted(h for (_, _, h, _, _) in neighbours)
    if not near:
        return 0.0, 0.0
    return near[len(near) // 2], near[min(len(near) - 1, int(len(near) * 0.8))]


def infer_height(building: dict, neighbours: list) -> float:
    area = footprint_area(building.get("footprint", []))
    base = area_prior(area)
    osm_id = int(building.get("osm_id", 0))
    twin = nearest_twin(area, neighbours)
    if twin > 0.0:
        value = twin * (1.0 + 0.04 * jitter(osm_id, 1))
        return round(min(max(value, MIN_HEIGHT_M), MAX_HEIGHT_M) * 2.0) / 2.0
    median, top = district_profile(neighbours)
    if area >= SLAB_AREA_M2 and top < TOWER_DISTRICT_M:
        # Big and low: warehouse, hangar, terminal, or an airfield outline
        # somebody mistagged as a building. Never a tower.
        ceiling = MEGA_SLAB_CEILING_M if area >= MEGA_SLAB_AREA_M2 else SLAB_CEILING_M
        value = min(base, ceiling) * (1.0 + 0.12 * jitter(osm_id, 0))
    else:
        if base >= 15.0:
            scale = max(0.8, min(3.4, (top or median) / max(base, 1.0)))
        elif base >= 10.0:
            scale = max(0.85, min(1.9, (median or base) / max(base, 1.0)))
        else:
            scale = max(0.9, min(1.35, (median or base) / max(base, 1.0)))
        value = base * scale
        if area >= 1200.0 and top >= TOWER_DISTRICT_M:
            # A whole city block standing among towers is a tower, and the
            # district's own profile is the only honest read of which one.
            value = max(value, min(top, 0.35 * value + 0.65 * top))
        spread = 0.16 if base < 12.0 else 0.24
        value *= 1.0 + spread * jitter(osm_id, 0)
    return round(min(max(value, MIN_HEIGHT_M), MAX_HEIGHT_M) * 2.0) / 2.0


def load_chunk(path: Path) -> dict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def dump_chunk(path: Path, payload: dict) -> None:
    temp = Path(str(path) + ".tmp")
    with open(temp, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"))
    os.replace(temp, path)


def collect_tagged(buildings: list, grid: dict) -> None:
    for building in buildings:
        height = float(building.get("height", 0.0))
        if building.get("height_source") or not is_tagged(height):
            continue
        key = (int(building.get("x", 0.0) // CELL_M), int(building.get("z", 0.0) // CELL_M))
        grid[key].append((
            float(building.get("x", 0.0)),
            float(building.get("z", 0.0)),
            height,
            footprint_area(building.get("footprint", [])),
        ))


def neighbours_for(x: float, z: float, grid: dict, cache: dict) -> list:
    cx, cz = int(x // CELL_M), int(z // CELL_M)
    key = (cx, cz)
    cached = cache.get(key)
    if cached is not None:
        return cached
    found = []
    for dx in range(-NEIGHBOUR_CELLS, NEIGHBOUR_CELLS + 1):
        for dz in range(-NEIGHBOUR_CELLS, NEIGHBOUR_CELLS + 1):
            for (nx, nz, nh, narea) in grid.get((cx + dx, cz + dz), ()):
                distance = math.hypot(nx - x, nz - z)
                if distance <= CELL_M * NEIGHBOUR_CELLS * 1.6:
                    found.append((nx, nz, nh, narea, distance))
    # A dense district has more reference points than one building needs.
    if len(found) > 220:
        found.sort(key=lambda entry: entry[4])
        found = found[:220]
    cache[key] = found
    return found


def histogram(heights: list) -> str:
    buckets = [(0, 3.5), (3.5, 6), (6, 9), (9, 13), (13, 20), (20, 35), (35, 60), (60, 1000)]
    parts = []
    for low, high in buckets:
        count = sum(1 for h in heights if low <= h < high)
        parts.append(f"{low:g}-{high:g}:{100.0 * count / max(len(heights), 1):.0f}%")
    return "  ".join(parts)


def process_region(directory: Path, args: argparse.Namespace) -> None:
    paths = sorted(glob.glob(str(directory / "buildings" / "*.json")))
    if not paths:
        return
    # Tagged heights have to be known before any guess is restated, so the
    # whole theatre is indexed first: a CBD block's neighbours live in the
    # chunk file to the east, not in its own.
    grid: dict = defaultdict(list)
    chunks = []
    for path in paths:
        payload = load_chunk(Path(path))
        chunks.append((path, payload))
        collect_tagged(payload.get("buildings", []), grid)
    cache: dict = {}
    rewritten = guessed = changed = 0
    before = []
    after = []
    for path, payload in chunks:
        if payload.get("height_model") == MODEL_VERSION:
            continue
        tally = 0
        for building in payload.get("buildings", []):
            height = float(building.get("height", 0.0))
            if building.get("height_source") or not is_guess(height) or len(building.get("footprint", [])) < 3:
                continue
            guessed += 1
            before.append(height)
            value = infer_height(building, neighbours_for(float(building.get("x", 0.0)),
                                                           float(building.get("z", 0.0)), grid, cache))
            after.append(value)
            if abs(value - height) > 0.01:
                building["height"] = value
                tally += 1
        payload["height_model"] = MODEL_VERSION
        changed += tally
        rewritten += 1
        if not args.report:
            dump_chunk(Path(path), payload)
    distinct_before = len(set(round(h, 1) for h in before))
    distinct_after = len(set(round(h, 1) for h in after))
    print(f"{directory.name}: {len(paths)} chunks, {guessed} guessed, {changed} restated")
    print(f"  distinct heights among guesses: {distinct_before} -> {distinct_after}")
    if after:
        print(f"  new spread: {histogram(after)}")
        print(f"  median guess: {sorted(before)[len(before)//2]:.1f} m -> {sorted(after)[len(after)//2]:.1f} m")


def main() -> None:
    args = arguments()
    targets = sorted(p for p in args.regions_dir.iterdir() if (p / "buildings").is_dir())
    if args.region:
        targets = [p for p in targets if p.name == args.region]
    for directory in targets:
        process_region(directory, args)


if __name__ == "__main__":
    main()
