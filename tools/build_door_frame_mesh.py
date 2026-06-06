from __future__ import annotations

import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "models" / "door_frame_between_rooms.glb"
TEXTURE_NAME = "simple_wood_door_wood.png"


class MeshBuilder:
    def __init__(self) -> None:
        self.positions: list[tuple[float, float, float]] = []
        self.normals: list[tuple[float, float, float]] = []
        self.uvs: list[tuple[float, float]] = []
        self.indices: list[int] = []

    def _add_vertex(
        self,
        pos: tuple[float, float, float],
        normal: tuple[float, float, float],
        uv: tuple[float, float],
    ) -> int:
        self.positions.append(pos)
        self.normals.append(normal)
        self.uvs.append(uv)
        return len(self.positions) - 1

    def add_box(
        self,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        uv_scale: float = 1.8,
    ) -> None:
        cx, cy, cz = center
        sx, sy, sz = (v * 0.5 for v in size)
        x0, x1 = cx - sx, cx + sx
        y0, y1 = cy - sy, cy + sy
        z0, z1 = cz - sz, cz + sz

        faces = [
            (((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)), (0, 0, 1)),
            (((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)), (0, 0, -1)),
            (((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)), (1, 0, 0)),
            (((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)), (-1, 0, 0)),
            (((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)), (0, 1, 0)),
            (((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)), (0, -1, 0)),
        ]

        for verts, normal in faces:
            start = len(self.positions)
            for x, y, z in verts:
                if abs(normal[2]) > 0.5:
                    uv = (x * uv_scale, y * uv_scale)
                elif abs(normal[0]) > 0.5:
                    uv = (z * uv_scale, y * uv_scale)
                else:
                    uv = (x * uv_scale, z * uv_scale)
                self._add_vertex((x, y, z), normal, uv)
            self.indices.extend([start, start + 1, start + 2, start, start + 2, start + 3])

    def add_cylinder(
        self,
        center: tuple[float, float, float],
        radius: float,
        length: float,
        axis: str,
        segments: int = 16,
        uv_v_scale: float = 1.7,
    ) -> None:
        cx, cy, cz = center
        half = length * 0.5

        def point(axis_pos: float, angle: float) -> tuple[float, float, float]:
            ca = math.cos(angle)
            sa = math.sin(angle)
            if axis == "x":
                return (cx + axis_pos, cy + ca * radius, cz + sa * radius)
            if axis == "y":
                return (cx + ca * radius, cy + axis_pos, cz + sa * radius)
            return (cx + ca * radius, cy + sa * radius, cz + axis_pos)

        def normal(angle: float) -> tuple[float, float, float]:
            ca = math.cos(angle)
            sa = math.sin(angle)
            if axis == "x":
                return (0, ca, sa)
            if axis == "y":
                return (ca, 0, sa)
            return (ca, sa, 0)

        for i in range(segments):
            a0 = math.tau * i / segments
            a1 = math.tau * (i + 1) / segments
            start = len(self.positions)
            for axis_pos, angle, u in [
                (-half, a0, i / segments),
                (half, a0, i / segments),
                (half, a1, (i + 1) / segments),
                (-half, a1, (i + 1) / segments),
            ]:
                v = (axis_pos + half) * uv_v_scale
                self._add_vertex(point(axis_pos, angle), normal(angle), (u, v))
            self.indices.extend([start, start + 1, start + 2, start, start + 2, start + 3])


def _align(offset: int, alignment: int) -> int:
    return (alignment - offset % alignment) % alignment


def build_glb(builder: MeshBuilder, out: Path) -> None:
    positions = b"".join(struct.pack("<3f", *p) for p in builder.positions)
    normals = b"".join(struct.pack("<3f", *n) for n in builder.normals)
    uvs = b"".join(struct.pack("<2f", *uv) for uv in builder.uvs)
    indices = b"".join(struct.pack("<I", i) for i in builder.indices)

    blob = bytearray()
    views = []

    def append(data: bytes, target: int) -> int:
        blob.extend(b"\0" * _align(len(blob), 4))
        offset = len(blob)
        blob.extend(data)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(views) - 1

    pos_view = append(positions, 34962)
    norm_view = append(normals, 34962)
    uv_view = append(uvs, 34962)
    idx_view = append(indices, 34963)

    xs = [p[0] for p in builder.positions]
    ys = [p[1] for p in builder.positions]
    zs = [p[2] for p in builder.positions]

    gltf = {
        "asset": {"version": "2.0", "generator": "Room45 door frame mesh builder"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "DoorFrameBetweenRooms", "mesh": 0}],
        "meshes": [
            {
                "name": "DoorFrameBetweenRoomsMesh",
                "primitives": [
                    {
                        "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                        "indices": 3,
                        "material": 0,
                    }
                ],
            }
        ],
        "materials": [
            {
                "name": "Simple wood door matching wood",
                "pbrMetallicRoughness": {
                    "baseColorTexture": {"index": 0},
                    "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.68,
                },
            }
        ],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": [{"uri": TEXTURE_NAME}],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
        "accessors": [
            {
                "bufferView": pos_view,
                "componentType": 5126,
                "count": len(builder.positions),
                "type": "VEC3",
                "min": [min(xs), min(ys), min(zs)],
                "max": [max(xs), max(ys), max(zs)],
            },
            {"bufferView": norm_view, "componentType": 5126, "count": len(builder.normals), "type": "VEC3"},
            {"bufferView": uv_view, "componentType": 5126, "count": len(builder.uvs), "type": "VEC2"},
            {
                "bufferView": idx_view,
                "componentType": 5125,
                "count": len(builder.indices),
                "type": "SCALAR",
            },
        ],
    }

    json_chunk = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * _align(len(json_chunk), 4)
    bin_chunk = bytes(blob)
    bin_chunk += b"\0" * _align(len(bin_chunk), 4)

    total_len = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total_len))
        f.write(struct.pack("<I4s", len(json_chunk), b"JSON"))
        f.write(json_chunk)
        f.write(struct.pack("<I4s", len(bin_chunk), b"BIN\0"))
        f.write(bin_chunk)


def build_frame() -> MeshBuilder:
    b = MeshBuilder()

    opening_w = 0.95
    opening_h = 2.05
    inner_x = opening_w * 0.5
    depth = 0.16
    casing_w = 0.145
    casing_outer_w = opening_w + casing_w * 2.0
    casing_top_h = 0.145
    casing_top_bottom = 2.030

    # Plain square door box inside the wall opening.
    b.add_box((-inner_x - 0.030, opening_h * 0.5, 0), (0.060, opening_h, depth), 1.30)
    b.add_box((inner_x + 0.030, opening_h * 0.5, 0), (0.060, opening_h, depth), 1.30)
    b.add_box((0, opening_h + 0.030, 0), (opening_w + 0.12, 0.060, depth), 1.30)

    for side in (-1, 1):
        face_z = side * 0.098

        # Flat apartment casing: one clean squared U-shape with no layered top.
        b.add_box((-inner_x - casing_w * 0.5, casing_top_bottom * 0.5, face_z), (casing_w, casing_top_bottom, 0.045), 1.35)
        b.add_box((inner_x + casing_w * 0.5, casing_top_bottom * 0.5, face_z), (casing_w, casing_top_bottom, 0.045), 1.35)
        b.add_box((0, casing_top_bottom + casing_top_h * 0.5, face_z), (casing_outer_w, casing_top_h, 0.045), 1.35)

        # Shallow side stops only; no top stop, otherwise the header reads as steps.
        b.add_box((-inner_x - 0.006, 1.020, face_z + side * 0.015), (0.024, 1.980, 0.026), 1.35)
        b.add_box((inner_x + 0.006, 1.020, face_z + side * 0.015), (0.024, 1.980, 0.026), 1.35)

    return b


if __name__ == "__main__":
    mesh = build_frame()
    build_glb(mesh, OUT)
    print(f"Wrote {OUT.relative_to(ROOT)}")
    print(f"vertices={len(mesh.positions)} triangles={len(mesh.indices) // 3}")
