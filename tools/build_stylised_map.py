#!/usr/bin/env python3
"""Render a high-detail offline military-tabletop ground map from OSM vectors."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


METRES_PER_LATITUDE_DEGREE = 111_320.0


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="OSM/Overpass JSON with roads and land features")
    parser.add_argument("--buildings-source", type=Path)
    parser.add_argument("--heightmap", type=Path, required=True)
    parser.add_argument("--latitude", type=float, required=True)
    parser.add_argument("--longitude", type=float, required=True)
    parser.add_argument("--world-size", type=float, default=4000.0)
    parser.add_argument("--resolution", type=int, default=4096)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


class MapRenderer:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.size = args.resolution
        self.half_world = args.world_size * 0.5
        self.metres_per_pixel = args.world_size / args.resolution
        self.metres_per_longitude_degree = METRES_PER_LATITUDE_DEGREE * math.cos(math.radians(args.latitude))
        self.image = Image.new("RGB", (self.size, self.size), (91, 96, 77))
        self.draw = ImageDraw.Draw(self.image)

    def pixel(self, latitude: float, longitude: float) -> tuple[float, float]:
        world_x = (longitude - self.args.longitude) * self.metres_per_longitude_degree
        world_z = (self.args.latitude - latitude) * METRES_PER_LATITUDE_DEGREE
        return (
            (world_x / self.args.world_size + 0.5) * self.size,
            (world_z / self.args.world_size + 0.5) * self.size,
        )

    def geometry(self, element: dict[str, object]) -> list[tuple[float, float]]:
        return [self.pixel(float(node["lat"]), float(node["lon"])) for node in element.get("geometry", [])]

    def width_pixels(self, metres: float) -> int:
        return max(1, round(metres / self.metres_per_pixel))

    def polygon(self, points: list[tuple[float, float]], colour: tuple[int, int, int]) -> None:
        if len(points) >= 3:
            self.draw.polygon(points, fill=colour)

    def line(self, points: list[tuple[float, float]], colour: tuple[int, int, int], metres: float) -> None:
        if len(points) >= 2:
            self.draw.line(points, fill=colour, width=self.width_pixels(metres), joint="curve")

    def render_land_features(self, elements: list[dict[str, object]]) -> None:
        landuse_colours = {
            "residential": (91, 91, 80),
            "commercial": (101, 94, 80),
            "retail": (106, 97, 82),
            "industrial": (91, 87, 76),
            "construction": (112, 96, 70),
            "grass": (78, 105, 65),
            "forest": (55, 83, 54),
            "meadow": (88, 112, 65),
            "recreation_ground": (74, 104, 66),
            "cemetery": (67, 91, 65),
        }
        leisure_colours = {
            "park": (67, 103, 63),
            "garden": (70, 108, 67),
            "nature_reserve": (54, 88, 57),
            "pitch": (79, 116, 72),
            "golf_course": (70, 105, 65),
            "playground": (99, 111, 74),
        }
        for element in elements:
            tags = element.get("tags", {})
            points = self.geometry(element)
            if len(points) < 3:
                continue
            landuse = tags.get("landuse")
            leisure = tags.get("leisure")
            natural = tags.get("natural")
            if landuse in landuse_colours:
                self.polygon(points, landuse_colours[landuse])
            if leisure in leisure_colours:
                self.polygon(points, leisure_colours[leisure])
            if tags.get("amenity") == "parking":
                self.polygon(points, (80, 82, 78))
            elif tags.get("amenity") == "school":
                self.polygon(points, (105, 101, 78))
            if natural in {"water", "bay"} or tags.get("water"):
                self.polygon(points, (35, 82, 97))
            elif natural in {"beach", "sand"}:
                self.polygon(points, (171, 151, 99))
            elif natural in {"wood", "scrub", "heath"}:
                self.polygon(points, (55, 85, 55))

    def render_coast(self, elements: list[dict[str, object]]) -> None:
        for element in elements:
            tags = element.get("tags", {})
            if tags.get("natural") != "coastline":
                continue
            points = self.geometry(element)
            # The Gold Coast ocean is east of the coastline. A broad sand band
            # beneath a narrow foam edge makes the beachfront readable in flight.
            self.line(points, (168, 148, 96), 72.0)
            self.line(points, (203, 191, 148), 20.0)
            self.line(points, (222, 218, 181), 4.0)

    def apply_surface_detail(self) -> None:
        height = Image.open(self.args.heightmap).convert("L").resize((self.size, self.size), Image.Resampling.BICUBIC)
        height_values = np.asarray(height, dtype=np.float32) / 255.0
        dz, dx = np.gradient(height_values)
        hillshade = np.clip(0.78 + (-dx * 22.0 - dz * 13.0), 0.70, 1.12)
        rng = np.random.default_rng(90210)
        noise_small = rng.normal(0.0, 1.8, (self.size, self.size)).astype(np.float32)
        macro_small = rng.normal(0.0, 1.0, (128, 128)).astype(np.float32)
        macro = np.asarray(
            Image.fromarray(macro_small, mode="F").resize((self.size, self.size), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        detail = np.clip(hillshade + macro * 0.018, 0.68, 1.14)
        pixels = np.asarray(self.image, dtype=np.float32)
        pixels = pixels * detail[..., None] + noise_small[..., None]
        self.image = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), mode="RGB")
        self.draw = ImageDraw.Draw(self.image)

    def render_waterways_and_rail(self, elements: list[dict[str, object]]) -> None:
        for element in elements:
            tags = element.get("tags", {})
            points = self.geometry(element)
            if len(points) < 2:
                continue
            waterway = tags.get("waterway")
            if waterway:
                width = 11.0 if waterway in {"river", "canal"} else 4.0
                self.line(points, (39, 92, 108), width)
            if tags.get("railway"):
                self.line(points, (44, 43, 39), 5.0)
                self.line(points, (146, 139, 116), 1.4)
            if tags.get("man_made") == "pier":
                self.line(points, (112, 107, 91), 7.0)

    def render_roads(self, elements: list[dict[str, object]]) -> None:
        road_widths = {
            "motorway": 24.0,
            "trunk": 21.0,
            "primary": 16.0,
            "secondary": 13.0,
            "tertiary": 11.0,
            "unclassified": 8.0,
            "residential": 8.0,
            "living_street": 7.0,
            "service": 5.0,
            "pedestrian": 5.0,
            "track": 3.5,
            "cycleway": 2.5,
            "footway": 2.0,
            "path": 1.8,
            "steps": 1.8,
        }
        major = {"motorway", "trunk", "primary", "secondary", "tertiary"}
        ordered: list[tuple[int, dict[str, object], str]] = []
        for element in elements:
            highway = str(element.get("tags", {}).get("highway", ""))
            if highway in road_widths:
                ordered.append((round(road_widths[highway]), element, highway))
        ordered.sort(key=lambda record: record[0], reverse=True)
        for _sort_width, element, highway in ordered:
            tags = element.get("tags", {})
            points = self.geometry(element)
            width = road_widths[highway]
            if tags.get("area") == "yes" and len(points) >= 3:
                self.polygon(points, (117, 115, 105))
                continue
            if highway in {"footway", "path", "cycleway", "steps", "track"}:
                colour = (169, 151, 105) if tags.get("surface") in {"sand", "dirt", "unpaved", "gravel"} else (151, 145, 125)
                self.line(points, (55, 56, 51), width + 1.8)
                self.line(points, colour, width)
                continue
            self.line(points, (43, 46, 45), width + 3.2)
            road_colour = (91, 95, 92) if highway in major else (101, 103, 97)
            self.line(points, road_colour, width)
            if highway in major:
                centre_colour = (213, 200, 115) if tags.get("oneway") != "yes" else (211, 211, 195)
                self.draw_dashed_line(points, centre_colour, 0.75, 10.0, 8.0)

    def draw_dashed_line(
        self,
        points: list[tuple[float, float]],
        colour: tuple[int, int, int],
        width_metres: float,
        dash_metres: float,
        gap_metres: float,
    ) -> None:
        dash = dash_metres / self.metres_per_pixel
        gap = gap_metres / self.metres_per_pixel
        remaining = dash
        drawing = True
        for start, end in zip(points, points[1:]):
            dx, dy = end[0] - start[0], end[1] - start[1]
            length = math.hypot(dx, dy)
            if length <= 0.01:
                continue
            travelled = 0.0
            while travelled < length:
                step = min(remaining, length - travelled)
                if drawing:
                    a = travelled / length
                    b = (travelled + step) / length
                    segment = [
                        (start[0] + dx * a, start[1] + dy * a),
                        (start[0] + dx * b, start[1] + dy * b),
                    ]
                    self.draw.line(segment, fill=colour, width=self.width_pixels(width_metres))
                travelled += step
                remaining -= step
                if remaining <= 0.001:
                    drawing = not drawing
                    remaining = dash if drawing else gap

    def render_building_footprints(self, source: Path | None) -> None:
        if source is None:
            return
        extract = json.loads(source.read_text())
        for element in extract.get("elements", []):
            tags = element.get("tags", {})
            if "building" not in tags:
                continue
            points = self.geometry(element)
            if len(points) >= 3:
                self.draw.polygon(points, fill=(72, 73, 68), outline=(42, 44, 43), width=1)

    def save(self) -> None:
        self.args.output.parent.mkdir(parents=True, exist_ok=True)
        self.image = self.image.filter(ImageFilter.UnsharpMask(radius=0.8, percent=55, threshold=3))
        self.image.save(self.args.output, optimize=True)


def main() -> None:
    args = arguments()
    extract = json.loads(args.source.read_text())
    elements = extract.get("elements", [])
    renderer = MapRenderer(args)
    renderer.render_land_features(elements)
    renderer.render_coast(elements)
    renderer.apply_surface_detail()
    renderer.render_waterways_and_rail(elements)
    renderer.render_roads(elements)
    renderer.render_building_footprints(args.buildings_source)
    renderer.save()
    print(f"Wrote {args.output} at {args.resolution}x{args.resolution} ({renderer.metres_per_pixel:.2f} m/px)")


if __name__ == "__main__":
    main()
