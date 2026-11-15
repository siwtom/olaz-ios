#!/usr/bin/env python3
"""
Generate an iOS App Store compliant 1024x1024 RGB PNG (no alpha channel)
at Sources/OlazIOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png.
Uses only Python standard library modules.
"""

from __future__ import annotations

import pathlib
import struct
import zlib

ROOT_DIR = pathlib.Path(__file__).resolve().parent.parent
SRC_ICON = ROOT_DIR / "Sources" / "Olaz" / "Resources" / "Olaz" / "AppIcon-a.png"
OUT_ICON = (
    ROOT_DIR
    / "Sources"
    / "OlazIOS"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "AppIcon.png"
)

SIZE = 1024


def _png_chunk(tag: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)


def _encode_rgb_png(width: int, height: int, rows: list[bytes]) -> bytes:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # color_type=2 (RGB, no alpha)
    raw = bytearray()
    for row in rows:
        raw.append(0)  # filter type 0 (None)
        raw.extend(row)
    idat = zlib.compress(bytes(raw), level=6)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", idat)
        + _png_chunk(b"IEND", b"")
    )


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def _decode_png_rgba(data: bytes) -> tuple[int, int, list[bytearray]] | None:
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    pos = 8
    width = height = 0
    bit_depth = color_type = interlace = 0
    idat_parts = bytearray()
    while pos + 8 <= len(data):
        length = struct.unpack_from(">I", data, pos)[0]
        tag = data[pos + 4 : pos + 8]
        payload = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", payload)
        elif tag == b"IDAT":
            idat_parts.extend(payload)
        elif tag == b"IEND":
            break
    if bit_depth != 8 or interlace != 0 or color_type not in (2, 6):
        return None
    bpp = 4 if color_type == 6 else 3
    stride = width * bpp
    raw = zlib.decompress(bytes(idat_parts))
    if len(raw) < height * (stride + 1):
        return None

    rows: list[bytearray] = []
    prev = bytearray(stride)
    offset = 0
    for _ in range(height):
        filt = raw[offset]
        offset += 1
        scan = bytearray(raw[offset : offset + stride])
        offset += stride
        if filt == 1:  # Sub
            for i in range(bpp, stride):
                scan[i] = (scan[i] + scan[i - bpp]) & 0xFF
        elif filt == 2:  # Up
            for i in range(stride):
                scan[i] = (scan[i] + prev[i]) & 0xFF
        elif filt == 3:  # Average
            for i in range(stride):
                left = scan[i - bpp] if i >= bpp else 0
                scan[i] = (scan[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif filt == 4:  # Paeth
            for i in range(stride):
                left = scan[i - bpp] if i >= bpp else 0
                up = prev[i]
                up_left = prev[i - bpp] if i >= bpp else 0
                scan[i] = (scan[i] + _paeth(left, up, up_left)) & 0xFF
        elif filt != 0:
            return None
        rows.append(scan)
        prev = scan

    if color_type == 2:
        rgba_rows: list[bytearray] = []
        for scan in rows:
            out = bytearray(width * 4)
            out[0::4] = scan[0::3]
            out[1::4] = scan[1::3]
            out[2::4] = scan[2::3]
            out[3::4] = b"\xff" * width
            rgba_rows.append(out)
        return width, height, rgba_rows
    return width, height, rows


def _composite_over_gradient(rgba_rows: list[bytearray], width: int, height: int) -> list[bytes]:
    # Full-bleed Zalo blue background gradient (#0070FF -> #0052CC)
    rgb_rows: list[bytes] = []
    denom = max(1, height - 1)
    for y in range(height):
        t = y / denom
        bg_r = 0
        bg_g = int(round(0x70 * (1.0 - t) + 0x52 * t))
        bg_b = int(round(0xFF * (1.0 - t) + 0xCC * t))
        src = rgba_rows[y]
        dst = bytearray(width * 3)
        dst[0::3] = bytes([bg_r]) * width
        dst[1::3] = bytes([bg_g]) * width
        dst[2::3] = bytes([bg_b]) * width
        for x in range(width):
            si = x * 4
            a = src[si + 3]
            if a == 255:
                di = x * 3
                dst[di] = src[si]
                dst[di + 1] = src[si + 1]
                dst[di + 2] = src[si + 2]
            elif a > 0:
                di = x * 3
                inv = 255 - a
                dst[di] = (src[si] * a + bg_r * inv) // 255
                dst[di + 1] = (src[si + 1] * a + bg_g * inv) // 255
                dst[di + 2] = (src[si + 2] * a + bg_b * inv) // 255
        rgb_rows.append(bytes(dst))
    return rgb_rows


def _generate_fallback_rgb(size: int) -> list[bytes]:
    cx, cy = size * 0.5, size * 0.47
    rx, ry = size * 0.30, size * 0.24
    tail_x1, tail_y1 = size * 0.33, size * 0.64
    tail_x2, tail_y2 = size * 0.25, size * 0.78
    tail_x3, tail_y3 = size * 0.47, size * 0.67

    def sign(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
        return (px - bx) * (ay - by) - (ax - bx) * (py - by)

    rgb_rows: list[bytes] = []
    for y in range(size):
        t = y / max(1, size - 1)
        bg_r = 0
        bg_g = int(round(0x6E * (1.0 - t) + 0x4E * t))
        bg_b = int(round(0xFF * (1.0 - t) + 0xD4 * t))
        row = bytearray(size * 3)
        row[0::3] = bytes([bg_r]) * size
        row[1::3] = bytes([bg_g]) * size
        row[2::3] = bytes([bg_b]) * size
        dy = (y - cy) / ry
        dy2 = dy * dy
        in_y_bubble = dy2 <= 1.0
        in_y_tail = tail_y1 <= y <= tail_y2
        if in_y_bubble or in_y_tail:
            for x in range(size):
                hit = False
                if in_y_bubble:
                    dx = (x - cx) / rx
                    if dx * dx + dy2 <= 1.0:
                        hit = True
                if not hit and in_y_tail:
                    d1 = sign(x, y, tail_x1, tail_y1, tail_x2, tail_y2)
                    d2 = sign(x, y, tail_x2, tail_y2, tail_x3, tail_y3)
                    d3 = sign(x, y, tail_x3, tail_y3, tail_x1, tail_y1)
                    if not (((d1 < 0) or (d2 < 0) or (d3 < 0)) and ((d1 > 0) or (d2 > 0) or (d3 > 0))):
                        hit = True
                if hit:
                    di = x * 3
                    row[di] = 255
                    row[di + 1] = 255
                    row[di + 2] = 255
        rgb_rows.append(bytes(row))
    return rgb_rows


def main() -> int:
    OUT_ICON.parent.mkdir(parents=True, exist_ok=True)
    rgb_rows: list[bytes] | None = None
    width = height = SIZE

    if SRC_ICON.exists():
        decoded = _decode_png_rgba(SRC_ICON.read_bytes())
        if decoded and decoded[0] == SIZE and decoded[1] == SIZE:
            width, height, rgba_rows = decoded
            rgb_rows = _composite_over_gradient(rgba_rows, width, height)

    if rgb_rows is None:
        rgb_rows = _generate_fallback_rgb(SIZE)

    OUT_ICON.write_bytes(_encode_rgb_png(width, height, rgb_rows))
    print(f"Generated {OUT_ICON} ({width}x{height} RGB, no alpha)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
