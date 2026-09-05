#!/usr/bin/env python3
"""Turn the hero towers' triangles the right way out.

The Q1, Soul and Ocean GLBs ship no NORMAL attribute, so Godot derives both the
lighting and the back-face culling from triangle winding. The kit's winding is
inconsistent -- a third of Q1's wall faces are wound inward -- and every one of
those faces is culled, so you look straight through the tower.

Godot's glTF importer mirrors one axis to convert +Z-forward to -Z-forward,
which reverses winding. A face therefore has to be wound *inward* in the file
to arrive *outward* in the engine, which is what this pass writes.

Walls are judged against the tower's vertical axis and roofs and soffits
against its centre. Rewriting only the index buffer in place leaves positions,
UVs, the texture and every byte of the JSON chunk untouched.

    python3 tools/fix_tower_winding.py 3dassets/q1_tower.glb
"""

from __future__ import annotations

import json
import struct
import sys

COMPONENTS = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
SHAPES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}


def _accessor(data: bytes, gltf: dict, binary_offset: int, index: int):
    accessor = gltf["accessors"][index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    offset = binary_offset + view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    code, size = COMPONENTS[accessor["componentType"]]
    width = SHAPES[accessor["type"]]
    count = accessor["count"] * width
    values = struct.unpack("<%d%s" % (count, code), data[offset : offset + count * size])
    if width == 1:
        return list(values), offset, code, size
    grouped = [values[i * width : (i + 1) * width] for i in range(accessor["count"])]
    return grouped, offset, code, size


def rewind(path: str) -> tuple[int, int]:
    data = open(path, "rb").read()
    if data[:4] != b"glTF":
        raise SystemExit("%s is not a binary glTF" % path)
    json_length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20 : 20 + json_length])
    binary_offset = 20 + json_length + 8

    buffer = bytearray(data)
    turned = 0
    total = 0
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4:
                continue
            indices, offset, code, size = _accessor(
                data, gltf, binary_offset, primitive["indices"]
            )
            points, _, _, _ = _accessor(
                data, gltf, binary_offset, primitive["attributes"]["POSITION"]
            )
            centre = [sum(p[axis] for p in points) / len(points) for axis in range(3)]
            wound = list(indices)
            for triangle in range(0, len(indices), 3):
                a, b, c = (points[indices[triangle + k]] for k in range(3))
                u = [b[i] - a[i] for i in range(3)]
                v = [c[i] - a[i] for i in range(3)]
                normal = [
                    u[1] * v[2] - u[2] * v[1],
                    u[2] * v[0] - u[0] * v[2],
                    u[0] * v[1] - u[1] * v[0],
                ]
                offset_from_centre = [
                    (a[i] + b[i] + c[i]) / 3.0 - centre[i] for i in range(3)
                ]
                horizontal = (normal[0] ** 2 + normal[2] ** 2) ** 0.5
                vertical = abs(normal[1])
                if horizontal > vertical * 0.1:
                    # A wall: judge it against the tower's vertical axis, so a
                    # face near the roof is not dragged upward by its height.
                    facing = (
                        normal[0] * offset_from_centre[0]
                        + normal[2] * offset_from_centre[2]
                    )
                else:
                    facing = sum(normal[i] * offset_from_centre[i] for i in range(3))
                # Inward in the file is outward in the engine.
                if facing > 0.0:
                    wound[triangle + 1], wound[triangle + 2] = (
                        wound[triangle + 2],
                        wound[triangle + 1],
                    )
                    turned += 1
                total += 1
            buffer[offset : offset + len(indices) * size] = struct.pack(
                "<%d%s" % (len(wound), code), *wound
            )

    open(path, "wb").write(bytes(buffer))
    return turned, total


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for target in sys.argv[1:]:
        turned, total = rewind(target)
        print("%s: turned %d of %d triangles" % (target, turned, total))
