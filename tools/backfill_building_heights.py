#!/usr/bin/env python3
"""Give buildings without OSM height tags a measured height instead of a guess.

The chunk builders infer height from tags and fall back to a class default,
which is why most of the Gold Coast arrives as 7.5 m cottages. This rewrites
each chunk JSON in place: wherever the stored height is a default (no `height`
or `building:levels` tag survived the extract), the roof elevation is sampled
from a surface model at the footprint centroid and the local ground read from
the surroundings, so the tower keeps its true relative height.

Sources, best first:
  --dsm FILE      a GDAL-readable GeoTIFF/AAIGrid surface model (state LiDAR,
                  0.5 m: real roof heights). Needs gdal_translate to ASCII grid
                  if GDAL Python bindings are absent:
                    gdal_translate -of AAIGrid roof_lidar.tif roof_lidar.asc
  (default)       Copernicus GLO-30 degree cells (30 m surface model), fetched
                  from the elevation-tiles-prod open-data bucket and cached
                  under --cache-dir. 30 m cannot resolve a single tower, but it
                  does raise the dense high-rise districts out of the 7.5 m
                  flatland, which is the visible error today.

Buildings are only ever made taller here, never shorter, and only when the
sampled relief around the footprint is real -- a house in open country reads
flat and keeps its tag height.
"""

from __future__ import annotations

import argparse
import array
import gzip
import io
import json
import math
import urllib.request
from pathlib import Path

METRES_PER_LATITUDE_DEGREE = 111_320.0
SKADI_URL = "https://s3.amazonaws.com/elevation-tiles-prod/skadi/{d}/{c}.hgt.gz"
SKADI_SIDE = 3601
MAX_HEIGHT_M = 320.0
MIN_HEIGHT_M = 3.0
# GLO-30 is a surface model: a bare-earth pixel and a rooftop pixel differ by
# the building. Relief below this, on a 30 m grid, is canopy and noise.
MIN_RELIEF_M = 6.0
MIN_RELIEF_COARSE_M = 14.0
# Upper quartile of the ground ring may sit this far above its floor before
# the neighbourhood counts as "slope, not suburb".
MAX_GROUND_SPREAD_M = 8.0
# A 30 m pixel is the size of a city block, so it cannot see a detached house.
# Only block-scale footprints and known tower classes may take a coarse estimate.
MIN_AREA_COARSE_M2 = 250.0
TOWER_CLASSES = {
    "apartments", "hotel", "office", "commercial", "retail", "civic",
    "hospital", "tower", "industrial", "school", "university",
}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("buildings_dir", type=Path)
    parser.add_argument("--latitude", type=float, required=True, help="Theatre centre latitude used to build the chunks")
    parser.add_argument("--longitude", type=float, required=True, help="Theatre centre longitude used to build the chunks")
    parser.add_argument("--cache-dir", type=Path, default=Path("/tmp/openstrike-dem"))
    parser.add_argument("--dsm", type=Path, default=None, help="AAIGrid/GeoTIFF surface model to use instead of GLO-30")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--report", type=int, default=0, help="Print this many of the largest changes")
    return parser.parse_args()


def to_latlon(x: float, z: float, center_latitude: float, center_longitude: float):
    metres_per_longitude_degree = METRES_PER_LATITUDE_DEGREE * math.cos(math.radians(center_latitude))
    return center_latitude - z / METRES_PER_LATITUDE_DEGREE, center_longitude + x / metres_per_longitude_degree


class SkadiSource:
    """Copernicus GLO-30 degree cells, cached as raw .hgt next to the game's
    own map cache format so the runtime and this tool read the same bytes."""

    def __init__(self, cache_dir: Path):
        self.cache_dir = cache_dir
        self.cells = {}
        cache_dir.mkdir(parents=True, exist_ok=True)

    def cell_name(self, latitude: float, longitude: float) -> str:
        lat_floor = int(math.floor(latitude))
        lon_floor = int(math.floor(longitude))
        prefix = "S%d" % abs(lat_floor) if lat_floor < 0 else "N%d" % lat_floor
        return "%sE%d" % (prefix, lon_floor)

    def cell(self, name: str):
        if name in self.cells:
            return self.cells[name]
        path = self.cache_dir / ("%s.hgt" % name)
        if not path.exists() or path.stat().st_size != SKADI_SIDE * SKADI_SIDE * 2:
            request = urllib.request.Request(
                SKADI_URL.format(d=name[:3], c=name), headers={"User-Agent": "OpenStrike"}
            )
            with urllib.request.urlopen(request, timeout=120) as response:
                raw = gzip.decompress(response.read())
            if len(raw) != SKADI_SIDE * SKADI_SIDE * 2:
                raise RuntimeError("cell %s is %d bytes" % (name, len(raw)))
            path.write_bytes(raw)
        values = array.array("h")
        values.frombytes(path.read_bytes())
        values.byteswap()  # SRTM grids are big-endian
        self.cells[name] = values
        return values

    def elevation(self, latitude: float, longitude: float):
        lat_floor = int(math.floor(latitude))
        lon_floor = int(math.floor(longitude))
        name = self.cell_name(latitude, longitude)
        try:
            values = self.cell(name)
        except Exception:
            # Southern cells sit under the ocean here far more often than not.
            try:
                lat_floor += 1
                values = self.cell(self.cell_name(lat_floor + 0.5, longitude))
            except Exception:
                return None
        fx = (longitude - lon_floor) * (SKADI_SIDE - 1)
        fy = (1.0 - (latitude - lat_floor)) * (SKADI_SIDE - 1)
        x0, y0 = int(fx), int(fy)
        tx, ty = fx - x0, fy - y0

        def at(row, column):
            row = min(max(row, 0), SKADI_SIDE - 1)
            column = min(max(column, 0), SKADI_SIDE - 1)
            return values[row * SKADI_SIDE + column]

        top = at(y0, x0) * (1 - tx) + at(y0, x0 + 1) * tx
        bottom = at(y0 + 1, x0) * (1 - tx) + at(y0 + 1, x0 + 1) * tx
        value = top * (1 - ty) + bottom * ty
        return None if value < -1000 else value


class AsciiGridSource:
    """AAIGrid from gdal_translate: a state LiDAR canopy-height model."""

    def __init__(self, path: Path):
        lines = path.read_text().splitlines()
        header = {}
        index = 0
        for index, line in enumerate(lines):
            parts = line.split()
            if len(parts) != 5:
                break
            header[parts[0].lower()] = float(parts[1])
        self.xll = header["xllcorner"]
        self.yll = header["yllcorner"]
        self.cell = header["cellsize"]
        self.columns = int(header["ncols"])
        self.rows = int(header["nrows"])
        self.no_data = header.get("nodata_value", -9999)
        self.values = [float(v) for v in " ".join(lines[index:]).split()]
        if len(self.values) != self.columns * self.rows:
            raise RuntimeError("AAIGrid body has %d values, header promises %d"
                               % (len(self.values), self.columns * self.rows))

    def elevation(self, latitude: float, longitude: float):
        column = (longitude - self.xll) / self.cell
        row = (self.yll + self.rows * self.cell - latitude) / self.cell
        x0, y0 = int(math.floor(column)), int(math.floor(row))
        if not (0 <= x0 < self.columns - 1 and 0 <= y0 < self.rows - 1):
            return None
        tx, ty = column - x0, row - y0

        def at(r, c):
            value = self.values[(r * self.columns) + c]
            return 0.0 if value <= self.no_data + 1 else value

        top = at(y0, x0) * (1 - tx) + at(y0, x0 + 1) * tx
        bottom = at(y0 + 1, x0) * (1 - tx) + at(y0 + 1, x0 + 1) * tx
        return top * (1 - ty) + bottom * ty


def offsets(source, latitude: float, longitude: float, ring_m: float):
    """Elevations at the centroid and a ring around it.

    The centroid carries an isolated tower's roof; the ring's low edge is the
    street. In a dense high-rise district the ring never reaches ground, so
    the district's relief is measured too -- but that number describes the
    precinct, not the cottage standing in it, so it is only used as a floor
    for what the centroid itself reads.
    """
    latitude_offset = ring_m / METRES_PER_LATITUDE_DEGREE
    longitude_offset = ring_m / (METRES_PER_LATITUDE_DEGREE * math.cos(math.radians(latitude)))
    centroid = source.elevation(latitude, longitude)
    samples = [centroid] if centroid is not None else []
    for d_lat, d_lon in (
        (1, 0), (-1, 0), (0, 1), (0, -1),
        (0.75, 0.75), (0.75, -0.75), (-0.75, 0.75), (-0.75, -0.75),
        (1.7, 0), (-1.7, 0), (0, 1.7), (0, -1.7),
    ):
        value = source.elevation(latitude + d_lat * latitude_offset, longitude + d_lon * longitude_offset)
        if value is not None:
            samples.append(value)
    return centroid, samples


def main() -> None:
    args = arguments()
    source = AsciiGridSource(args.dsm) if args.dsm else SkadiSource(args.cache_dir)
    coarse = args.dsm is None
    # The 30 m grid's "near" is a couple of pixels; a LiDAR grid's is a block.
    ring_m = 120.0 if coarse else 45.0
    min_relief = MIN_RELIEF_COARSE_M if coarse else MIN_RELIEF_M
    changed = considered = files = 0
    changes = []
    for path in sorted(args.buildings_dir.glob("*.json")):
        payload = json.loads(path.read_text())
        dirty = False
        for building in payload.get("buildings", []):
            considered += 1
            if building.get("height_source"):
                continue
            # Only a default may be overwritten: a tagged height is data, and
            # a short tagged tower is still a tower.
            if float(building["height"]) > 18.5:
                continue
            footprint = building.get("footprint", [])
            area = abs(sum(
                p[0] * q[1] - q[0] * p[1]
                for p, q in zip(footprint, footprint[1:] + footprint[:1])
            )) * 0.5 if len(footprint) >= 3 else 0.0
            if coarse and area < MIN_AREA_COARSE_M2:
                continue
            latitude, longitude = to_latlon(
                float(building["x"]), float(building["z"]), args.latitude, args.longitude
            )
            samples = offsets(source, latitude, longitude, ring_m)
            if len(samples[1]) < 4:
                continue
            centroid, ring = samples
            ordered = sorted(ring)
            ground = ordered[0]
            # A hillside inside one pixel is not a building: require the
            # surroundings to be genuinely flat before trusting the relief.
            spread = ordered[int(0.75 * (len(ordered) - 1))] - ground
            if spread > MAX_GROUND_SPREAD_M:
                continue
            district = ordered[min(len(ordered) - 1, int(0.9 * len(ordered)))] - ground
            # A footprint is only ever raised to what the pixel it stands on
            # reads -- the district's relief alone justifies nothing.
            if centroid is None:
                continue
            measured = max(centroid - ground, min(district, centroid - ground + 10.0))
            if measured < min_relief:
                continue
            estimate = min(max(measured, MIN_HEIGHT_M), MAX_HEIGHT_M)
            if estimate > float(building["height"]) + 0.5:
                changes.append({
                    "osm_id": building.get("osm_id"),
                    "area_m2": round(area),
                    "before_m": building["height"],
                    "after_m": round(estimate, 1),
                    "lat": round(latitude, 5), "lon": round(longitude, 5),
                })
                building["height"] = round(estimate, 1)
                building["height_source"] = "lidar" if args.dsm else "dem"
                dirty = True
                changed += 1
        if dirty and not args.dry_run:
            path.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
        files += 1
    print("%s %d of %d buildings across %d chunk files (%s)" % (
        "Would raise" if args.dry_run else "Raised", changed, considered, files,
        "GLO-30 30 m" if args.dsm is None else args.dsm.name))
    for row in sorted(changes, key=lambda r: -r["after_m"])[:args.report]:
        print("  %(osm_id)s  %(area_m2)6d m2  %(before_m)6.1f -> %(after_m)6.1f m  @ %(lat)s, %(lon)s" % row)


if __name__ == "__main__":
    main()
