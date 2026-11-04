#!/usr/bin/env python3
"""Trace owner-approved PDF reference contours. Authoring-only PIL/numpy/scipy.

No AI regeneration, network, fonts, app dependency or private property photo.
Supply unmodified reference PNGs extracted from the pinned owner PDF.
The reusable production SVG masters are tracked; normal exports use them directly.
Run with the workspace's existing imaging runtime, then export PNGs with sharp.
"""
from collections import defaultdict
import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'mobile_app/assets/brand'
REF = None
PDF_SHA = 'f96761f6422339fc8b7b5dc09d3d935a7dc76dc9f0840e317b37f9eca9781bc2'
STOPS = [(0, '#16c1c1'), (.08, '#06979d'), (.30, '#015a60'),
         (.55, '#01484d'), (.80, '#003d44'), (1, '#012a30')]


def simplify(points, epsilon=.65):
    """Closed RDP with two non-degenerate arcs; do not replace small islands."""
    def arc(p):
        if len(p) < 3:
            return p
        start, end = np.asarray(p[0]), np.asarray(p[-1])
        delta = end - start
        a = np.asarray(p)
        t = np.clip(((a - start) @ delta) / max(float(delta @ delta), 1), 0, 1)
        distances = np.linalg.norm(a - start - t[:, None] * delta, axis=1)
        index = int(np.argmax(distances))
        if distances[index] <= epsilon:
            return [p[0], p[-1]]
        return arc(p[:index + 1])[:-1] + arc(p[index:])
    if len(points) < 5:
        return points
    split = max(range(1, len(points)), key=lambda i: math.dist(points[0], points[i]))
    return arc(points[:split + 1])[:-1] + arc(points[split:] + [points[0]])[:-1]


def contours(mask):
    """Trace the exact directed boundary edges of the selected pixels."""
    height, width = mask.shape
    edges = defaultdict(list)
    for y, x in np.argwhere(mask):
        x, y = int(x), int(y)
        if y == 0 or not mask[y - 1, x]: edges[(x, y)].append((x + 1, y))
        if x == width - 1 or not mask[y, x + 1]: edges[(x + 1, y)].append((x + 1, y + 1))
        if y == height - 1 or not mask[y + 1, x]: edges[(x + 1, y + 1)].append((x, y + 1))
        if x == 0 or not mask[y, x - 1]: edges[(x, y + 1)].append((x, y))
    result = []
    while edges:
        first = next(iter(edges))
        current, previous = first, (first[0] - 1, first[1])
        points = []
        while True:
            points.append(current)
            choices = edges[current]
            dx, dy = current[0] - previous[0], current[1] - previous[1]
            def turn(p):
                nx, ny = p[0] - current[0], p[1] - current[1]
                return math.atan2(dx * ny - dy * nx, dx * nx + dy * ny)
            following = max(choices, key=turn)
            choices.remove(following)
            if not choices: del edges[current]
            previous, current = current, following
            if current == first: break
        points = simplify(points)
        if len(points) >= 3:
            result.append(points)
    return result


def area(p):
    return sum(x * p[(i + 1) % len(p)][1] - y * p[(i + 1) % len(p)][0]
               for i, (x, y) in enumerate(p)) / 2


def select(mask, minimum, reject_border=False):
    labels, count = ndimage.label(mask)
    selected = np.zeros(mask.shape, dtype=bool)
    components = 0
    for label in range(1, count + 1):
        ys, xs = np.where(labels == label)
        if len(xs) < minimum: continue
        if reject_border and (xs.min() == 0 or ys.min() == 0 or
                              xs.max() == mask.shape[1] - 1 or ys.max() == mask.shape[0] - 1):
            continue
        selected[labels == label] = True
        components += 1
    return selected, components


def path(polygons):
    return ' '.join('M' + ' L'.join(f'{x:.3f},{y:.3f}' for x, y in p) + ' Z' for p in polygons)


def gradient():
    stops = ''.join(f'<stop offset="{offset}" stop-color="{color}"/>' for offset, color in STOPS)
    return f'<linearGradient id="brand" x1="0" y1="0" x2="0" y2="1">{stops}</linearGradient>'


def svg(width, height, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">'
            f'<defs>{gradient()}</defs>{body}</svg>\n')


def native(width, height, body, dp_width=108, dp_height=108):
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android" '
            'xmlns:aapt="http://schemas.android.com/aapt" '
            f'android:width="{dp_width}dp" android:height="{dp_height}dp" '
            f'android:viewportWidth="{width}" android:viewportHeight="{height}">{body}</vector>\n')


def write(relative, text):
    p = ROOT / relative
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def overlap(mask, polygons):
    # Sample polygon interiors at pixel centers. ImageDraw's inclusive integer
    # edges inflate a traced outline by a pixel and bias small text measurements.
    a = np.zeros(mask.shape, dtype=bool)
    for p in polygons:
        low = max(0, math.ceil(min(y for _, y in p) - .5))
        high = min(mask.shape[0], math.ceil(max(y for _, y in p) - .5))
        for row in range(low, high):
            y = row + .5
            intersections = []
            for i, (x1, y1) in enumerate(p):
                x2, y2 = p[(i + 1) % len(p)]
                if (y1 <= y < y2) or (y2 <= y < y1):
                    intersections.append(x1 + (y - y1) * (x2 - x1) / (y2 - y1))
            intersections.sort()
            assert len(intersections) % 2 == 0
            for left, right in zip(intersections[::2], intersections[1::2]):
                a[row, max(0, math.ceil(left - .5)):min(mask.shape[1], math.ceil(right - .5))] ^= True
    return float(np.logical_and(a, mask).sum() / np.logical_or(a, mask).sum())


def main():
    global REF
    parser = argparse.ArgumentParser()
    parser.add_argument('--reference-dir', required=True, type=Path)
    REF = parser.parse_args().reference_dir
    OUT.mkdir(parents=True, exist_ok=True)
    mark_ref = np.array(Image.open(REF / 'mark-reference.png').convert('RGB'))
    # Measured frame bounds in REF-B01, matching the approved preview's source crop.
    frame = (254, 242, 1280, 1270)
    cropped = mark_ref[frame[1]:frame[3], frame[0]:frame[2]]
    mask, count = select(np.all(cropped > 220, axis=2), 20, reject_border=True)
    assert count == 5, 'House, Yemen and its three reference islands must remain separate.'
    mark_pixels = contours(mask)
    mark = [[(x * 1024 / cropped.shape[1], y * 1024 / cropped.shape[0]) for x, y in p]
            for p in mark_pixels]
    word_ref = np.array(Image.open(REF / 'wordmark-reference.png').convert('RGB'))[:, :900]
    ink = ((word_ref[:, :, 0] < 110) &
           (word_ref[:, :, 1].astype(int) > word_ref[:, :, 0].astype(int) + 10) &
           (word_ref[:, :, 2].astype(int) > word_ref[:, :, 0].astype(int) + 10))
    ink, word_count = select(ink, 30)
    assert word_count == 8, 'Outlined Arabic and Aqer letter components changed.'
    word_pixels = contours(ink)
    # Preserve REF-B02 text/mark proportions; reuse canonical B01 house/Yemen geometry.
    factor = 1024 / 440
    word = [[((x - 173) * factor, (y - 292) * factor) for x, y in p] for p in word_pixels]
    offset, total = 1736, 2760
    md, wd = path(mark), path(word)
    rounded = 'M220,0 H804 Q1024,0 1024,220 V804 Q1024,1024 804,1024 H220 Q0,1024 0,804 V220 Q0,0 220,0 Z'
    mark_body = f'<path d="{rounded}" fill="url(#brand)"/><path d="{md}" fill="white" fill-rule="evenodd"/>'
    word_body = (f'<path d="{wd}" fill="#015a60" fill-rule="evenodd"/>'
                 f'<g transform="translate({offset},0)">{mark_body}</g>')
    write('mobile_app/assets/brand/aqer-mark.svg', svg(1024, 1024, mark_body))
    write('mobile_app/assets/brand/aqer-wordmark.svg', svg(total, 1024, word_body))
    write('mobile_app/assets/brand/aqer-monochrome.svg', svg(1024, 1024,
          f'<path d="{md}" fill="white" fill-rule="evenodd"/>'))
    mono_word = f'<path d="{wd}" fill="white" fill-rule="evenodd"/><g transform="translate({offset},0)"><path d="{md}" fill="white" fill-rule="evenodd"/></g>'
    write('mobile_app/assets/brand/aqer-watermark.svg', svg(total, 1024, mono_word))
    radius = max(math.hypot(x - 512, y - 512) for p in mark for x, y in p)
    safe_scale = math.floor((33 / 108 * 1024 / radius) * 1000000) / 1000000
    native_path = f'<path android:pathData="{md}" android:fillColor="#FFFFFFFF" android:fillType="evenOdd"/>'
    fg = f'<group android:pivotX="512" android:pivotY="512" android:scaleX="{safe_scale}" android:scaleY="{safe_scale}">{native_path}</group>'
    write('mobile_app/android/app/src/main/res/drawable/aqer_icon_foreground.xml', native(1024, 1024, fg))
    grad = ''.join(f'<item android:offset="{o}" android:color="{c}"/>' for o, c in STOPS)
    fill = ('<aapt:attr name="android:fillColor"><gradient android:startX="0" android:startY="0" '
            f'android:endX="0" android:endY="1024" android:type="linear">{grad}</gradient></aapt:attr>')
    bg = f'<path android:pathData="M0,0 H1024 V1024 H0 Z">{fill}</path>'
    write('mobile_app/android/app/src/main/res/drawable/aqer_icon_background.xml', native(1024, 1024, bg))
    full_mark = f'<path android:pathData="{rounded}">{fill}</path>{native_path}'
    # Native Android12 splash leaves breathing room for the system icon mask.
    launch = f'<group android:pivotX="512" android:pivotY="512" android:scaleX="0.65" android:scaleY="0.65">{full_mark}</group>'
    write('mobile_app/android/app/src/main/res/drawable/aqer_splash_icon.xml', native(1024, 1024, launch, 240, 240))
    full_word = f'<path android:pathData="{wd}" android:fillColor="#FF015A60" android:fillType="evenOdd"/><group android:translateX="{offset}">{full_mark}</group>'
    write('mobile_app/android/app/src/main/res/drawable/aqer_wordmark.xml', native(total, 1024, full_word, 220, 82))
    normalized = []
    # Existing renderer uses a square transparent stamp; center the full lockup in it.
    for polygons in [word, [[(x + offset, y) for x, y in p] for p in mark]]:
        layer = {'polygons': [], 'holes': []}
        for p in polygons:
            group = 'polygons' if area(p) > 0 else 'holes'
            layer[group].append([[round(x / total, 7), round((y + (total - 1024) / 2) / total, 7)] for x, y in p])
        normalized.append(layer)
    geometry = {'approval': 'owner-approved', 'approved_on': '2026-10-21',
                'source_pdf_sha256': PDF_SHA, 'source_reference': 'REF-B01 and REF-B02',
                'layers': normalized}
    write('backend-api-runtime/resources/brand/aqer-approved.json', json.dumps(geometry, separators=(',', ':')) + '\n')
    measurement = {'source_pdf_sha256': PDF_SHA, 'owner_approved_on': '2026-10-21',
        'mark_frame_pixels': frame, 'mark_components': count, 'word_components': word_count,
        'mark_contour_overlap': overlap(mask, mark_pixels),
        'word_contour_overlap': overlap(ink, word_pixels), 'rdp_tolerance_px': .65,
        'adaptive_foreground_scale': safe_scale,
        'adaptive_max_radius_dp': radius / 1024 * safe_scale * 108,
        'gradient_stops_estimated_from_reference': STOPS,
        'disclosed_difference': 'Raster highlights and reflected drop shadows are simplified to a stable vector gradient; no pixel-identical lighting claim.'}
    assert measurement['mark_contour_overlap'] > .985
    assert measurement['word_contour_overlap'] > .98
    assert measurement['adaptive_max_radius_dp'] <= 33
    write('docs/brand/MEASUREMENTS.json', json.dumps(measurement, indent=2) + '\n')
    print(json.dumps(measurement))


if __name__ == '__main__':
    main()
