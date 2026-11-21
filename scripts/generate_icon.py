import zlib
import struct
import math
import os

def create_app_icon():
    W, H = 1024, 1024
    pixels = bytearray(W * H * 4)
    cx, cy = W / 2.0, H / 2.0

    # Shield polygon (center top to bottom tip)
    for y in range(H):
        ny = (y - cy) / (H / 2.0)
        row_offset = y * W * 4
        for x in range(W):
            nx = (x - cx) / (W / 2.0)
            dist = math.sqrt(nx * nx + ny * ny)

            # Deep dark gradient background (opaque, continuous for iOS icon mask)
            bg_t = min(1.0, dist * 0.9)
            r = int(14 * (1.0 - bg_t) + 7 * bg_t)
            g = int(20 * (1.0 - bg_t) + 11 * bg_t)
            b = int(38 * (1.0 - bg_t) + 22 * bg_t)

            # Outer subtle radial ring glow
            ring_dist = abs(dist - 0.70)
            if ring_dist < 0.15:
                glow = ((1.0 - ring_dist / 0.15) ** 2) * 0.45
                r = min(255, int(r + 40 * glow))
                g = min(255, int(g + 110 * glow))
                b = min(255, int(b + 230 * glow))

            # Shield shape
            sy = ny + 0.04
            sx = abs(nx)
            in_shield = False
            shield_dist = 0.0

            if -0.56 < sy < 0.58:
                max_sx = 0.50 * (1.0 - (sy + 0.56) * 0.16) if sy < 0.0 else 0.50 * 0.84 * (1.0 - (sy / 0.58) ** 1.8)
                if sx < max_sx:
                    in_shield = True
                    shield_dist = 1.0 - (sx / max_sx)

            if in_shield:
                # Glass fill
                s_t = (sy + 0.56) / 1.14
                sr = int(20 + s_t * 14)
                sg = int(34 + s_t * 26)
                sb = int(68 + s_t * 54)

                # Neon border
                edge = 1.0 - shield_dist
                if edge > 0.85:
                    b_int = (edge - 0.85) / 0.15
                    sr = int(sr + 90 * b_int)
                    sg = int(sg + 180 * b_int)
                    sb = int(sb + 255 * b_int)

                r, g, b = sr, sg, sb

            # Minimalist speed / lightning emblem in center
            poly = [
                (0.04, -0.36),
                (-0.20, 0.02),
                (-0.02, 0.02),
                (-0.14, 0.38),
                (0.20, -0.04),
                (0.02, -0.04)
            ]

            inside_bolt = False
            j = len(poly) - 1
            for i in range(len(poly)):
                xi, yi = poly[i]
                xj, yj = poly[j]
                if ((yi > ny) != (yj > ny)) and (nx < (xj - xi) * (ny - yi) / (yj - yi) + xi):
                    inside_bolt = not inside_bolt
                j = i

            if inside_bolt:
                bolt_t = (ny + 0.36) / 0.74
                r = int(0 * bolt_t + 40 * (1.0 - bolt_t))
                g = int(215 * bolt_t + 245 * (1.0 - bolt_t))
                b = 255
            else:
                # Subtle bolt aura
                min_d = 999.0
                for pt in poly:
                    d = math.sqrt((nx - pt[0])**2 + (ny - pt[1])**2)
                    if d < min_d: min_d = d
                if min_d < 0.16:
                    bglow = ((1.0 - min_d / 0.16) ** 2) * 0.7
                    r = min(255, int(r + 35 * bglow))
                    g = min(255, int(g + 130 * bglow))
                    b = min(255, int(b + 220 * bglow))

            idx = row_offset + x * 4
            pixels[idx] = min(255, max(0, r))
            pixels[idx+1] = min(255, max(0, g))
            pixels[idx+2] = min(255, max(0, b))
            pixels[idx+3] = 255

    # Encode PNG
    raw = bytearray()
    for row in range(H):
        raw.append(0)
        s = row * W * 4
        raw.extend(pixels[s:s + W * 4])

    ihdr = struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)
    idat = zlib.compress(raw, 9)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

    png_bytes = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")

    out_dir = "App/Assets.xcassets/AppIcon.appiconset"
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "icon_1024.png")
    with open(out_path, "wb") as f:
        f.write(png_bytes)
    print(f"Icon created successfully at {out_path} ({len(png_bytes)} bytes)")

if __name__ == "__main__":
    create_app_icon()
