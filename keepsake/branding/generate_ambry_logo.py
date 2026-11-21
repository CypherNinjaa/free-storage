#!/usr/bin/env python3
"""Generates every Ambry logo asset from one geometry, using only the Python standard library.

The mark is an ambry (a small arched wall cabinet for keeping precious things) seen as a window onto a sunrise:
a cream arch, an amber sun rising behind two hills, on a warm amber tile.

Outputs
  keepsake/branding/       ambry-logo.svg, ambry-icon-1024.png (full bleed), ambry-play-512.png (Play Store)
  keepsake/mobile/assets/  ambry-logo.png (rounded tile, used inside the app), ambry-splash.png,
                           ambry-splash-android12.png
  Android res              legacy mipmap PNGs, adaptive icon vector drawables (background, foreground,
                           monochrome) and the notification icon vector

Run from anywhere:  python keepsake/branding/generate_ambry_logo.py
"""

import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # .../keepsake
BRANDING = os.path.join(ROOT, 'branding')
ASSETS = os.path.join(ROOT, 'mobile', 'assets')
RES = os.path.join(ROOT, 'mobile', 'android', 'app', 'src', 'main', 'res')

# Palette
AMBER_TOP = (0xFD, 0xB4, 0x4B)
AMBER_BOTTOM = (0xEE, 0x7F, 0x22)
CREAM = (0xFF, 0xF6, 0xE6)
SUN = (0xF9, 0xA8, 0x25)
HILL_BACK = (0xF0, 0x8A, 0x2E)
HILL_FRONT = (0xB8, 0x54, 0x0F)

# Geometry, in units of the arch half-width `a`, origin at the top centre of the arch, y pointing down.
HEIGHT = 2.6        # arch height
CORNER = 0.20       # bottom corner radius
FRAME = 0.09        # cream frame between the arch edge and the picture inside it
SUN_X, SUN_Y, SUN_R = -0.10, 1.56, 0.40
MONO_SUN_X, MONO_SUN_Y, MONO_SUN_R = -0.12, 1.16, 0.33  # monochrome: the sun floats free of the hills
MONO_FRAME = 0.15   # monochrome frame thickness


def hex_color(rgb):
    return '#%02X%02X%02X' % rgb


def bump(t):
    t = max(-1.0, min(1.0, t))
    return (math.cos(math.pi * t) + 1.0) / 2.0


def back_hill(x):
    return 2.40 - 0.78 * bump((x - 0.40) / 1.30)


def front_hill(x):
    return 2.30 - 0.38 * bump((x + 0.45) / 1.35)


# ----------------------------------------------------------------------------------------------------------
# Signed distance functions (negative inside), in arch units


def sd_arch(x, y, inset=0.0):
    a = 1.0 - inset
    top = inset
    bottom = HEIGHT - inset
    rc = max(CORNER - inset, 0.02)
    d_circle = math.hypot(x, y - (top + a)) - a
    y0 = top + a - rc
    cy = (y0 + bottom) / 2.0
    hy = (bottom - y0) / 2.0
    qx = abs(x) - (a - rc)
    qy = abs(y - cy) - (hy - rc)
    d_box = math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - rc
    return min(d_circle, d_box)


def sd_below(curve, x, y):
    f = curve(x)
    eps = 1e-3
    slope = (curve(x + eps) - curve(x - eps)) / (2 * eps)
    return (f - y) / math.sqrt(1.0 + slope * slope)


def sd_round_square(px, py, size, radius):
    if radius <= 0:
        return max(-px, px - size, -py, py - size)
    half = size / 2.0
    qx = abs(px - half) - (half - radius)
    qy = abs(py - half) - (half - radius)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - radius


# ----------------------------------------------------------------------------------------------------------
# Rasterizer


def render(size, scale, top, tile=None, corner=0.0, mode='color'):
    """Renders a size x size RGBA image.

    scale  pixels per arch unit (arch half-width in pixels)
    top    y of the arch top in pixels (the arch is centred horizontally)
    tile   None for a transparent background, otherwise draw the amber tile
    corner tile corner radius as a fraction of size
    mode   'color' (cream arch, sun, hills) or 'white' (single-colour silhouette for notifications)
    """
    cx = size / 2.0
    out = bytearray(size * size * 4)
    radius = corner * size
    x_min = int(cx - 1.05 * scale) - 1
    x_max = int(cx + 1.05 * scale) + 2
    y_min = int(top - 0.05 * scale) - 1
    y_max = int(top + (HEIGHT + 0.05) * scale) + 2
    for py in range(size):
        t = (py + 0.5) / size
        for px in range(size):
            r = g = b = al = 0.0

            def over(color, cov):
                nonlocal r, g, b, al
                if cov <= 0.0:
                    return
                if cov > 1.0:
                    cov = 1.0
                r = color[0] * cov + r * (1 - cov)
                g = color[1] * cov + g * (1 - cov)
                b = color[2] * cov + b * (1 - cov)
                al = cov + al * (1 - cov)

            if tile:
                cov = 0.5 - sd_round_square(px + 0.5, py + 0.5, size, radius)
                if cov > 0:
                    over(tuple(AMBER_TOP[i] + (AMBER_BOTTOM[i] - AMBER_TOP[i]) * t for i in range(3)), cov)
            if x_min <= px <= x_max and y_min <= py <= y_max:
                x = (px + 0.5 - cx) / scale
                y = (py + 0.5 - top) / scale
                d_arch = sd_arch(x, y)
                if mode == 'white':
                    frame = max(d_arch, -sd_arch(x, y, MONO_FRAME))
                    sun = math.hypot(x - MONO_SUN_X, y - MONO_SUN_Y) - MONO_SUN_R
                    land = max(min(sd_below(back_hill, x, y), sd_below(front_hill, x, y)), sd_arch(x, y, MONO_FRAME))
                    over((255, 255, 255), 0.5 - min(frame, sun, land) * scale)
                else:
                    over(CREAM, 0.5 - d_arch * scale)
                    d_inner = sd_arch(x, y, FRAME)
                    over(SUN, 0.5 - max(math.hypot(x - SUN_X, y - SUN_Y) - SUN_R, d_inner) * scale)
                    over(HILL_BACK, 0.5 - max(sd_below(back_hill, x, y), d_inner) * scale)
                    over(HILL_FRONT, 0.5 - max(sd_below(front_hill, x, y), d_inner) * scale)
            i = (py * size + px) * 4
            if al > 0:
                out[i] = min(255, int(round(r / al)))
                out[i + 1] = min(255, int(round(g / al)))
                out[i + 2] = min(255, int(round(b / al)))
                out[i + 3] = min(255, int(round(al * 255)))
    return bytes(out)


def write_png(path, size, rgba):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    stride = size * 4
    raw = b''.join(b'\x00' + rgba[y * stride:(y + 1) * stride] for y in range(size))

    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)
    print('wrote', os.path.relpath(path, ROOT), size)


# Layouts: the arch half-width and top as fractions of the image size.
TILE_SCALE = 0.255                          # arch fills ~66 % of the tile height
TILE_TOP = (1 - HEIGHT * TILE_SCALE) / 2
ADAPTIVE_SCALE = 20.5 / 108                 # fits Android's 66 dp safe circle in the 108 dp canvas
ADAPTIVE_TOP = (1 - HEIGHT * ADAPTIVE_SCALE) / 2


def tile_png(path, size, corner):
    write_png(path, size, render(size, TILE_SCALE * size, TILE_TOP * size, tile=True, corner=corner))


# ----------------------------------------------------------------------------------------------------------
# Vector paths (SVG and Android VectorDrawable share the same path syntax)


def fmt(v):
    s = ('%.2f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def arch_path(scale, ox, oy, inset=0.0):
    """Closed arch outline in absolute coordinates; (ox, oy) is the top centre of the arch."""
    a = (1.0 - inset) * scale
    rc = max(CORNER - inset, 0.02) * scale
    top = oy + inset * scale
    bottom = oy + (HEIGHT - inset) * scale
    left, right = ox - a, ox + a
    return (
        f'M{fmt(left)},{fmt(top + a)} '
        f'A{fmt(a)},{fmt(a)} 0 0,1 {fmt(right)},{fmt(top + a)} '
        f'L{fmt(right)},{fmt(bottom - rc)} '
        f'A{fmt(rc)},{fmt(rc)} 0 0,1 {fmt(right - rc)},{fmt(bottom)} '
        f'L{fmt(left + rc)},{fmt(bottom)} '
        f'A{fmt(rc)},{fmt(rc)} 0 0,1 {fmt(left)},{fmt(bottom - rc)} Z'
    )


def circle_path(cx, cy, r):
    return (f'M{fmt(cx - r)},{fmt(cy)} A{fmt(r)},{fmt(r)} 0 1,0 {fmt(cx + r)},{fmt(cy)} '
            f'A{fmt(r)},{fmt(r)} 0 1,0 {fmt(cx - r)},{fmt(cy)} Z')


def hill_path(curve, scale, ox, oy, steps=48):
    """Region under a hill curve, extending past the arch (callers clip it to the arch)."""
    xs = [-1.1 + 2.2 * i / steps for i in range(steps + 1)]
    pts = [f'{fmt(ox + x * scale)},{fmt(oy + curve(x) * scale)}' for x in xs]
    bottom = oy + (HEIGHT + 0.2) * scale
    return f'M{fmt(ox - 1.1 * scale)},{fmt(bottom)} L' + ' L'.join(pts) + f' L{fmt(ox + 1.1 * scale)},{fmt(bottom)} Z'


def land_path(scale, ox, oy, steps=64):
    """Monochrome landscape: the union of both hills, clipped to the inner edge of the frame."""
    inner = 1.0 - MONO_FRAME
    xs = [-inner + 2 * inner * i / steps for i in range(steps + 1)]
    pts = [f'{fmt(ox + x * scale)},{fmt(oy + min(back_hill(x), front_hill(x)) * scale)}' for x in xs]
    bottom = oy + (HEIGHT - MONO_FRAME) * scale
    rc = max(CORNER - MONO_FRAME, 0.02) * scale
    left, right = ox - inner * scale, ox + inner * scale
    return (f'M{pts[0]} L' + ' L'.join(pts[1:]) +
            f' L{fmt(right)},{fmt(bottom - rc)} A{fmt(rc)},{fmt(rc)} 0 0,1 {fmt(right - rc)},{fmt(bottom)}'
            f' L{fmt(left + rc)},{fmt(bottom)} A{fmt(rc)},{fmt(rc)} 0 0,1 {fmt(left)},{fmt(bottom - rc)} Z')


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    print('wrote', os.path.relpath(path, ROOT))


def svg_master():
    size = 1024
    s = TILE_SCALE * size
    ox, oy = size / 2, TILE_TOP * size
    arch = arch_path(s, ox, oy)
    inner = arch_path(s, ox, oy, FRAME)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}">
  <title>Ambry</title>
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{hex_color(AMBER_TOP)}"/>
      <stop offset="1" stop-color="{hex_color(AMBER_BOTTOM)}"/>
    </linearGradient>
    <clipPath id="picture"><path d="{inner}"/></clipPath>
  </defs>
  <rect width="{size}" height="{size}" rx="{fmt(0.23 * size)}" fill="url(#tile)"/>
  <path d="{arch}" fill="{hex_color(CREAM)}"/>
  <g clip-path="url(#picture)">
    <path d="{circle_path(ox + SUN_X * s, oy + SUN_Y * s, SUN_R * s)}" fill="{hex_color(SUN)}"/>
    <path d="{hill_path(back_hill, s, ox, oy)}" fill="{hex_color(HILL_BACK)}"/>
    <path d="{hill_path(front_hill, s, ox, oy)}" fill="{hex_color(HILL_FRONT)}"/>
  </g>
</svg>
'''


def vector(width_dp, viewport, body, extra_ns=''):
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by keepsake/branding/generate_ambry_logo.py; edit the generator, not this file. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"{extra_ns}
  android:width="{width_dp}dp"
  android:height="{width_dp}dp"
  android:viewportWidth="{viewport}"
  android:viewportHeight="{viewport}">
{body}
</vector>
'''


def adaptive_vectors():
    v = 108
    s = ADAPTIVE_SCALE * v
    ox, oy = v / 2, ADAPTIVE_TOP * v
    arch = arch_path(s, ox, oy)
    inner = arch_path(s, ox, oy, FRAME)
    background = vector(108, v, f'''  <path android:pathData="M0,0h108v108h-108z">
    <aapt:attr name="android:fillColor">
      <gradient android:type="linear" android:startX="54" android:startY="0" android:endX="54" android:endY="108">
        <item android:offset="0" android:color="{hex_color(AMBER_TOP)}"/>
        <item android:offset="1" android:color="{hex_color(AMBER_BOTTOM)}"/>
      </gradient>
    </aapt:attr>
  </path>''', extra_ns='\n  xmlns:aapt="http://schemas.android.com/aapt"')
    foreground = vector(108, v, f'''  <path android:fillColor="{hex_color(CREAM)}" android:pathData="{arch}"/>
  <group>
    <clip-path android:pathData="{inner}"/>
    <path android:fillColor="{hex_color(SUN)}" android:pathData="{circle_path(ox + SUN_X * s, oy + SUN_Y * s, SUN_R * s)}"/>
    <path android:fillColor="{hex_color(HILL_BACK)}" android:pathData="{hill_path(back_hill, s, ox, oy)}"/>
    <path android:fillColor="{hex_color(HILL_FRONT)}" android:pathData="{hill_path(front_hill, s, ox, oy)}"/>
  </group>''')
    mono_body = f'''  <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd"
    android:pathData="{arch} {arch_path(s, ox, oy, MONO_FRAME)}"/>
  <path android:fillColor="#FFFFFFFF" android:pathData="{circle_path(ox + MONO_SUN_X * s, oy + MONO_SUN_Y * s, MONO_SUN_R * s)}"/>
  <path android:fillColor="#FFFFFFFF" android:pathData="{land_path(s, ox, oy)}"/>'''
    monochrome = vector(108, v, mono_body)
    # Notification icons use a 24 dp canvas; the mark fills it with a 2 dp margin.
    n = 24
    ns = 20 / HEIGHT  # arch height 20 dp
    nox, noy = n / 2, 2
    notification = vector(24, n, f'''  <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd"
    android:pathData="{arch_path(ns, nox, noy)} {arch_path(ns, nox, noy, MONO_FRAME)}"/>
  <path android:fillColor="#FFFFFFFF" android:pathData="{circle_path(nox + MONO_SUN_X * ns, noy + MONO_SUN_Y * ns, MONO_SUN_R * ns)}"/>
  <path android:fillColor="#FFFFFFFF" android:pathData="{land_path(ns, nox, noy)}"/>''')
    return background, foreground, monochrome, notification


def main():
    write_text(os.path.join(BRANDING, 'ambry-logo.svg'), svg_master())
    background, foreground, monochrome, notification = adaptive_vectors()
    write_text(os.path.join(RES, 'drawable', 'ic_launcher_background.xml'), background)
    write_text(os.path.join(RES, 'drawable', 'ic_launcher_foreground.xml'), foreground)
    write_text(os.path.join(RES, 'drawable', 'ic_launcher_monochrome.xml'), monochrome)
    write_text(os.path.join(RES, 'drawable', 'notification_icon.xml'), notification)

    # Legacy launcher icons (minSdk 26 always uses the adaptive icon; these are fallbacks).
    for folder, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        tile_png(os.path.join(RES, 'mipmap-' + folder, 'ic_launcher.png'), px, corner=0.23)

    tile_png(os.path.join(ASSETS, 'ambry-logo.png'), 1024, corner=0.23)
    tile_png(os.path.join(ASSETS, 'ambry-splash.png'), 320, corner=0.23)
    # Android 12+ splash icon drawn on an amber icon background: 960 px, content inside a 640 px circle.
    size = 960
    write_png(os.path.join(ASSETS, 'ambry-splash-android12.png'), size,
              render(size, ADAPTIVE_SCALE * size, ADAPTIVE_TOP * size))
    tile_png(os.path.join(BRANDING, 'ambry-icon-1024.png'), 1024, corner=0.0)
    tile_png(os.path.join(BRANDING, 'ambry-play-512.png'), 512, corner=0.0)


if __name__ == '__main__':
    main()
