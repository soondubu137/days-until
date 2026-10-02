#!/usr/bin/env python3
"""Builds the Days Until icon set in design/assets: the runway mark, the lockups with the
wordmark, the macOS app icon and the favicon, each as SVG and PNG.

Everything is drawn here on Apple's 1024 pt icon grid: an 824 pt squircle with a 100 pt margin.
The wordmark is "Days Until" in Inter SemiBold (SIL Open Font License) at -0.02 em tracking,
converted to outlines once with Core Text, so the files don't depend on an installed font.

PNGs are rendered by headless Google Chrome at 2048 px and scaled down with Pillow. The app
icon's 16 and 32 px sizes use simpler artwork, with fewer and heavier ticks, that stays legible.

It also writes the icon the app uses, DaysUntil/AppIcon.icon, in Icon Composer's format: the
runway in layers, so macOS 26 draws it in Liquid Glass and in Dark, Clear and Tinted modes.
Xcode makes the flat icon for macOS 13 to 15 from the same file.

Usage: scripts/make-icons.py
"""

import concurrent.futures
import json
import math
import pathlib
import shutil
import subprocess
import tempfile
import time

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "design" / "assets"
APP_ICON = ROOT / "DaysUntil" / "AppIcon.icon"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
NAME = "days-until"

C = 512       # the centre of the 1024 grid
HALF = 412    # half the squircle's side

# "Days Until", Inter SemiBold at 1000 units per em, baseline at y = 0.
WORDMARK = (
    "M319.3 -0.0L135.3 -0.0L135.3 -112.8L313.0 -112.8Q389.2 -112.8 440.2 -140.9Q491.2 -168.9 517.1 -224.9Q543.0 -280.8 543.0 -364.7Q543.0 -447.8 517.1 -503.4Q491.2 -559.1 441.2 -586.9Q391.1 -614.7 316.4 -614.7L131.3 -614.7L131.3 -727.5L324.2 -727.5Q432.6 -727.5 510.3 -684.1Q587.9 -640.6 629.6 -559.1Q671.4 -477.5 671.4 -364.7Q671.4 -251.0 629.6 -169.2Q587.9 -87.4 509.0 -43.7Q430.2 -0.0 319.3 -0.0ZM203.6 -727.5L203.6 -0.0L73.2 -0.0L73.2 -727.5ZM921.9 11.2Q870.1 11.2 828.6 -7.6Q787.1 -26.4 763.2 -63.0Q739.3 -99.6 739.3 -153.3Q739.3 -199.7 756.6 -230.0Q773.9 -260.3 803.5 -278.3Q833.0 -296.4 870.1 -305.7Q907.2 -314.9 947.3 -318.8Q994.6 -324.2 1024.4 -328.1Q1054.2 -332.0 1068.1 -340.8Q1082.1 -349.6 1082.1 -368.2L1082.1 -370.6Q1082.1 -397.5 1071.3 -416.3Q1060.6 -435.1 1039.3 -445.1Q1018.1 -455.1 986.8 -455.1Q955.1 -455.1 931.9 -445.3Q908.7 -435.5 894.1 -419.9Q879.4 -404.3 872.6 -386.2L754.9 -410.2Q771.0 -458.5 804.7 -490.0Q838.4 -521.5 885.0 -537.1Q931.7 -552.7 986.3 -552.7Q1024.9 -552.7 1064.2 -543.7Q1103.5 -534.7 1136.2 -513.2Q1169.0 -491.7 1189.0 -455.6Q1209.0 -419.4 1209.0 -364.7L1209.0 -0.0L1087.4 -0.0L1087.4 -75.2L1082.5 -75.2Q1070.3 -52.2 1049.1 -32.5Q1027.9 -12.7 996.4 -0.7Q964.9 11.2 921.9 11.2ZM954.6 -83.0Q994.2 -83.0 1022.7 -98.6Q1051.3 -114.3 1067.2 -139.9Q1083.0 -165.5 1083.0 -195.8L1083.0 -260.3Q1076.7 -255.4 1061.8 -251.0Q1046.9 -246.6 1028.6 -243.2Q1010.3 -239.7 992.5 -237.3Q974.6 -234.9 962.4 -233.4Q934.1 -229.5 911.2 -220.7Q888.2 -211.9 875.3 -196.0Q862.3 -180.2 862.3 -154.8Q862.3 -131.3 874.3 -115.5Q886.2 -99.6 907.0 -91.3Q927.8 -83.0 954.6 -83.0ZM1301.8 194.8L1331.6 95.7L1346.7 99.6Q1375.5 106.9 1398.0 103.8Q1420.4 100.6 1435.6 84.2Q1450.7 67.9 1457.1 36.6L1464.9 2.0L1258.8 -545.9L1394.6 -545.9L1494.2 -249.0Q1511.8 -196.3 1523.0 -144.0Q1534.2 -91.8 1547.9 -37.1L1514.7 -37.1Q1527.9 -91.8 1541.1 -144.3Q1554.2 -196.8 1571.8 -249.0L1674.8 -545.9L1809.1 -545.9L1574.7 70.3Q1558.1 113.8 1533.2 144.8Q1508.3 175.8 1472.2 191.9Q1436.1 208.0 1386.8 208.0Q1359.9 208.0 1337.2 204.1Q1314.5 200.2 1301.8 194.8ZM2082.1 11.2Q2019.1 11.2 1970.8 -6.8Q1922.4 -24.9 1891.4 -59.6Q1860.4 -94.2 1851.1 -143.6L1969.8 -166.0Q1981.0 -125.5 2009.6 -105.7Q2038.1 -85.9 2084.5 -85.9Q2131.4 -85.9 2159.0 -104.7Q2186.6 -123.5 2186.6 -151.4Q2186.6 -174.8 2168.5 -190.2Q2150.4 -205.6 2112.9 -213.9L2019.6 -233.9Q1942.4 -250.5 1904.4 -288.6Q1866.3 -326.7 1866.3 -386.7Q1866.3 -437.5 1894.1 -474.6Q1921.9 -511.7 1971.5 -532.2Q2021.1 -552.7 2086.5 -552.7Q2148.5 -552.7 2193.2 -535.2Q2237.9 -517.6 2265.4 -486.1Q2293.0 -454.6 2303.8 -412.1L2190.5 -389.6Q2181.2 -418.5 2156.8 -438.2Q2132.4 -458.0 2087.9 -458.0Q2047.4 -458.0 2020.3 -440.2Q1993.2 -422.4 1993.2 -394.5Q1993.2 -370.6 2011.3 -355.0Q2029.4 -339.4 2070.9 -330.6L2163.6 -311.0Q2241.3 -294.4 2278.9 -257.8Q2316.5 -221.2 2316.5 -163.6Q2316.5 -111.8 2286.7 -72.5Q2256.9 -33.2 2203.9 -11.0Q2150.9 11.2 2082.1 11.2ZM2937.6 10.7Q2848.7 10.7 2782.3 -22.7Q2715.9 -56.2 2679.3 -115.5Q2642.7 -174.8 2642.7 -252.4L2642.7 -727.5L2773.0 -727.5L2773.0 -263.2Q2773.0 -217.8 2793.3 -182.1Q2813.6 -146.5 2850.4 -126.2Q2887.3 -106.0 2937.6 -106.0Q2987.9 -106.0 3024.8 -126.2Q3061.6 -146.5 3081.9 -182.1Q3102.1 -217.8 3102.1 -263.2L3102.1 -727.5L3232.5 -727.5L3232.5 -252.4Q3232.5 -174.8 3195.7 -115.5Q3158.8 -56.2 3092.6 -22.7Q3026.5 10.7 2937.6 10.7ZM3479.6 -319.8L3479.6 -0.0L3352.7 -0.0L3352.7 -545.9L3472.8 -545.9L3474.7 -411.1L3464.5 -411.1Q3487.4 -481.9 3531.9 -517.3Q3576.3 -552.7 3643.2 -552.7Q3699.3 -552.7 3741.3 -528.8Q3783.3 -504.9 3806.5 -459.0Q3829.7 -413.1 3829.7 -347.2L3829.7 -0.0L3702.8 -0.0L3702.8 -327.6Q3702.8 -382.3 3674.4 -413.6Q3646.1 -444.8 3596.3 -444.8Q3562.6 -444.8 3536.2 -430.2Q3509.9 -415.5 3494.7 -387.5Q3479.6 -359.4 3479.6 -319.8ZM4196.9 -545.9L4196.9 -446.3L3886.9 -446.3L3886.9 -545.9ZM3964.5 -675.8L4091.4 -675.8L4091.4 -153.8Q4091.4 -124.0 4104.1 -110.1Q4116.8 -96.2 4145.6 -96.2Q4154.4 -96.2 4168.8 -98.4Q4183.2 -100.6 4192.0 -102.5L4212.1 -4.4Q4191.1 2.0 4169.1 4.6Q4147.1 7.3 4127.1 7.3Q4048.5 7.3 4006.5 -31.7Q3964.5 -70.8 3964.5 -143.1ZM4277.5 -0.0L4277.5 -545.9L4404.5 -545.9L4404.5 -0.0ZM4341.0 -623.0Q4310.7 -623.0 4289.0 -643.6Q4267.2 -664.1 4267.2 -692.4Q4267.2 -721.7 4289.0 -741.9Q4310.7 -762.2 4341.0 -762.2Q4371.7 -762.2 4393.5 -741.9Q4415.2 -721.7 4415.2 -692.9Q4415.2 -664.1 4393.5 -643.6Q4371.7 -623.0 4341.0 -623.0ZM4646.2 -727.5L4646.2 -0.0L4519.2 -0.0L4519.2 -727.5Z"
)
WORDMARK_LEFT, WORDMARK_RIGHT = 73.2, 4646.2   # the glyphs' ink, without side bearings
CAP_HEIGHT, DESCENDER = 727.5, 208.0

# The runway: elapsed ticks, today's mark with its dot, the ticks ahead (the weekend taller),
# and the destination: an accent well holding the house. `None` is today.
FULL = dict(heights=[84, 84, 84, None, 150, 240, 240], tick=34, step=60, gap=28, well=105,
            mark=42, mark_height=380, dot=46, house=58)
# For 16 and 32 px: one tick either side of today, heavier, and a bigger well.
SMALL = dict(heights=[120, None, 250], tick=64, step=116, gap=36, well=150,
             mark=76, mark_height=420, dot=72, house=84)

# The app icon's appearances. Tinted uses a stand-in for the colour the person picks.
TINT = "#8FD3C8"
ICON = {
    "default": dict(bg=("#FFFFFF", "#E6E8ED"), elapsed="#C9CCD3", ahead="#8A8D95",
                    accent=("#3EA0FF", "#0068F0"), house="#FFFFFF", dark=False),
    "dark": dict(bg=("#3A3A3F", "#1B1B1E"), elapsed="#55565C", ahead="#A3A4AB",
                 accent=("#4AA8FF", "#0A74FF"), house="#FFFFFF", dark=True),
    "tinted": dict(bg=("#2B2B2F", "#141416"), elapsed=TINT + "55", ahead=TINT + "AA",
                   accent=(TINT, TINT), house="#18181A", dark=True),
}

# The flat mark, in macOS's own colours: system grays and system blue, light and dark.
MARK = {
    "": dict(elapsed="#C7C7CC", ahead="#8E8E93", accent="#007AFF", house="#FFFFFF"),
    "dark": dict(elapsed="#48484A", ahead="#98989D", accent="#0A84FF", house="#FFFFFF"),
    "black": dict(ink="#000000"),
    "white": dict(ink="#FFFFFF"),
}
LABEL = {"": "#1D1D1F", "dark": "#F5F5F7", "black": "#000000", "white": "#FFFFFF"}


def squircle():
    """The macOS icon shape: a superellipse, which is close to Apple's continuous corners."""
    points = []
    for i in range(240):
        t = 2 * math.pi * i / 240
        c, s = math.cos(t), math.sin(t)
        x = C + HALF * math.copysign(abs(c) ** 0.4, c)
        y = C + HALF * math.copysign(abs(s) ** 0.4, s)
        points.append(f"{x:.1f} {y:.1f}")
    return "M" + " L".join(points) + "Z"


SQUIRCLE = squircle()


def layout(spec):
    """Places the runway's parts on the 1024 grid, centred on the squircle."""
    count = len(spec["heights"])
    span = spec["step"] * (count - 1) + spec["tick"] + spec["gap"] + 2 * spec["well"]
    x0 = C - span / 2 + spec["tick"] / 2
    base = C + (spec["mark_height"] + spec["dot"]) / 2
    ticks, today = [], None
    for i, height in enumerate(spec["heights"]):
        x = x0 + spec["step"] * i
        if height is None:
            today = x
        else:
            ticks.append((x, height, today is None))
    well_x = x0 + spec["step"] * (count - 1) + spec["tick"] / 2 + spec["gap"] + spec["well"]
    return dict(spec, ticks=ticks, today=today, base=base, well_x=well_x, well_y=base - spec["well"],
                left=x0 - spec["tick"] / 2, right=well_x + spec["well"],
                top=base - spec["mark_height"] - spec["dot"])


def house(cx, cy, s, fill):
    """Our own house, not SF Symbols' (Apple doesn't allow those in icons): an overhanging roof,
    a chimney on its right slope, and a doorway cut out of the body, open at the ground."""
    roof = f"M{cx - s:.1f} {cy - 0.02 * s:.1f} L{cx:.1f} {cy - 0.92 * s:.1f} L{cx + s:.1f} {cy - 0.02 * s:.1f}"
    # The body's outline runs around the doorway, so the door is a true opening: rounded at the
    # top, square where it meets the ground.
    left, right, top, bottom, r = cx - 0.68 * s, cx + 0.68 * s, cy - 0.32 * s, cy + 0.85 * s, 0.12 * s
    door, lintel, d = 0.19 * s, cy + 0.3 * s, 0.09 * s
    body = (
        f"M{left:.1f} {top + r:.1f} A{r:.1f} {r:.1f} 0 0 1 {left + r:.1f} {top:.1f} H{right - r:.1f} "
        f"A{r:.1f} {r:.1f} 0 0 1 {right:.1f} {top + r:.1f} V{bottom - r:.1f} A{r:.1f} {r:.1f} 0 0 1 {right - r:.1f} {bottom:.1f} "
        f"H{cx + door:.1f} V{lintel + d:.1f} A{d:.1f} {d:.1f} 0 0 0 {cx + door - d:.1f} {lintel:.1f} "
        f"H{cx - door + d:.1f} A{d:.1f} {d:.1f} 0 0 0 {cx - door:.1f} {lintel + d:.1f} V{bottom:.1f} "
        f"H{left + r:.1f} A{r:.1f} {r:.1f} 0 0 1 {left:.1f} {bottom - r:.1f} Z"
    )
    return (
        f'<rect x="{cx + 0.43 * s:.1f}" y="{cy - 0.82 * s:.1f}" width="{0.24 * s:.1f}" height="{0.5 * s:.1f}" rx="{0.05 * s:.1f}" fill="{fill}"/>'
        f'<path d="{roof}" fill="none" stroke="{fill}" stroke-width="{0.2 * s:.1f}" stroke-linecap="round" stroke-linejoin="round"/>'
        f'<path d="M{cx - 0.68 * s:.1f} {cy - 0.3 * s:.1f} L{cx:.1f} {cy - 0.86 * s:.1f} L{cx + 0.68 * s:.1f} {cy - 0.3 * s:.1f} Z" fill="{fill}"/>'
        f'<path d="{body}" fill="{fill}"/>'
    )


def ticks(r, elapsed, ahead):
    w = r["tick"]
    return "".join(
        f'<rect x="{x - w / 2:.1f}" y="{r["base"] - h:.1f}" width="{w}" height="{h}" rx="{w / 2}" fill="{elapsed if gone else ahead}"/>'
        for x, h, gone in r["ticks"]
    )


def today(r, fill):
    x, w, h = r["today"], r["mark"], r["mark_height"]
    return (
        f'<rect x="{x - w / 2:.1f}" y="{r["base"] - h:.1f}" width="{w}" height="{h}" rx="{w / 2}" fill="{fill}"/>'
        f'<circle cx="{x:.1f}" cy="{r["base"] - h:.1f}" r="{r["dot"]}" fill="{fill}"/>'
    )


def stops(*colours):
    """Gradient stops; a colour may carry alpha as #RRGGBBAA or as a (colour, opacity) pair."""
    out = ""
    for i, colour in enumerate(colours):
        colour, opacity = colour if isinstance(colour, tuple) else (colour, 1)
        if len(colour) == 9:
            colour, opacity = colour[:7], int(colour[7:], 16) / 255
        out += f'<stop offset="{i / max(len(colours) - 1, 1):.2f}" stop-color="{colour}" stop-opacity="{opacity:.2f}"/>'
    return out


def icon(id, appearance="default", spec=FULL, shadow=True):
    """The app icon's defs and drawing on the 1024 grid, with ids prefixed by `id`."""
    a, r = ICON[appearance], layout(spec)
    dark = a["dark"]
    defs = (
        f'<linearGradient id="{id}bg" x1="0" y1="0" x2="0" y2="1">{stops(*a["bg"])}</linearGradient>'
        f'<linearGradient id="{id}rim" x1="0" y1="0" x2="0" y2="1">'
        f'{stops(("#FFFFFF", 0.45 if dark else 0.9), ("#FFFFFF", 0.08 if dark else 0.15), ("#FFFFFF", 0.18 if dark else 0.35))}</linearGradient>'
        f'<linearGradient id="{id}ac" x1="0" y1="0" x2="0" y2="1">{stops(*a["accent"])}</linearGradient>'
        f'<linearGradient id="{id}hl" x1="0" y1="0" x2="0" y2="1">{stops(("#FFFFFF", 0.45), ("#FFFFFF", 0))}</linearGradient>'
        f'<clipPath id="{id}clip"><path d="{SQUIRCLE}"/></clipPath>'
        f'<filter id="{id}sh" x="-20%" y="-20%" width="140%" height="150%">'
        f'<feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000" flood-opacity="{0.45 if dark else 0.22}"/></filter>'
        f'<filter id="{id}gs" x="-30%" y="-30%" width="160%" height="170%">'
        f'<feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="{0.42 if dark else 0.16}"/></filter>'
    )
    body = (
        ticks(r, a["elapsed"], a["ahead"])
        + f'<g filter="url(#{id}gs)">{today(r, f"url(#{id}ac)")}'
        + f'<circle cx="{r["well_x"]:.1f}" cy="{r["well_y"]:.1f}" r="{r["well"]}" fill="url(#{id}ac)"/></g>'
        + f'<circle cx="{r["well_x"]:.1f}" cy="{r["well_y"]:.1f}" r="{r["well"] - 3}" fill="url(#{id}hl)"/>'
        + house(r["well_x"], r["well_y"] + 0.1 * r["house"], r["house"], a["house"])
    )
    drawing = (
        f'<path d="{SQUIRCLE}" fill="url(#{id}bg)"' + (f' filter="url(#{id}sh)"' if shadow else "") + "/>"
        f'<g clip-path="url(#{id}clip)">{body}</g>'
        f'<path d="{SQUIRCLE}" fill="none" stroke="url(#{id}rim)" stroke-width="5"/>'
    )
    return defs, drawing


def mark(id, variant, spec=FULL):
    """The flat runway mark on the 1024 grid. In one ink, the house is cut out of the well."""
    m, r = MARK[variant], layout(spec)
    hx, hy, hs = r["well_x"], r["well_y"] + 0.1 * r["house"], r["house"]
    well = f'<circle cx="{r["well_x"]:.1f}" cy="{r["well_y"]:.1f}" r="{r["well"]}"'
    if "ink" in m:
        ink = m["ink"]
        defs = (f'<mask id="{id}cut" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">'
                f'<rect width="1024" height="1024" fill="#FFFFFF"/>{house(hx, hy, hs, "#000000")}</mask>')
        # Elapsed and ahead keep their order as two strengths of the ink.
        faint = ticks(r, "ELAPSED", "AHEAD").replace('fill="ELAPSED"', f'fill="{ink}" fill-opacity="0.3"')
        faint = faint.replace('fill="AHEAD"', f'fill="{ink}" fill-opacity="0.6"')
        return defs, faint + today(r, ink) + f'{well} fill="{ink}" mask="url(#{id}cut)"/>'
    drawing = (ticks(r, m["elapsed"], m["ahead"]) + today(r, m["accent"]) + f'{well} fill="{m["accent"]}"/>'
               + house(hx, hy, hs, m["house"]))
    return "", drawing


def wordmark(x, baseline, cap, fill):
    """The wordmark with its ink starting at `x` and a cap height of `cap`."""
    s = cap / CAP_HEIGHT
    return (f'<path transform="translate({x - WORDMARK_LEFT * s:.2f} {baseline:.2f}) scale({s:.5f})" '
            f'd="{WORDMARK}" fill="{fill}"/>'), (WORDMARK_RIGHT - WORDMARK_LEFT) * s, DESCENDER * s


def svg(view, defs, drawing, title):
    x, y, w, h = view
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x:g} {y:g} {w:g} {h:g}" width="{w:g}" height="{h:g}" role="img">'
            f"<title>{title}</title><defs>{defs}</defs>{drawing}</svg>\n")


# --- The set ---------------------------------------------------------------------------------

def build():
    files = []   # (svg path, [(png path, width)])

    def add(folder, name, content, widths, png=None):
        path = OUTPUT / folder / f"{name}.svg"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        files.append((path, [(path.with_name(f"{png or name}-{w}.png"), w) for w in widths]))

    sizes = [128, 256, 512, 1024]
    r = layout(FULL)
    pad = 64

    # 01 · The mark alone, for small spaces and one-colour printing.
    for variant in MARK:
        suffix = f"-{variant}" if variant else ""
        defs, drawing = mark("m", variant)
        view = (r["left"] - pad, r["top"] - pad, r["right"] - r["left"] + 2 * pad, r["base"] - r["top"] + 2 * pad)
        add("01-mark", f"{NAME}-mark{suffix}", svg(view, defs, drawing, "Days Until"), sizes)

    # 02 · Horizontal and 03 · stacked lockups. In colour they use the app icon, as Apple
    # presents its apps; in one ink, the flat mark.
    for variant in MARK:
        suffix = f"-{variant}" if variant else ""
        colour = variant in ("", "dark")
        if colour:
            defs, drawing = icon("i", "dark" if variant == "dark" else "default")
            box, shadow = (100, 100, 924, 924), 56   # the squircle, and its shadow below
        else:
            defs, drawing = mark("m", variant)
            box, shadow = (r["left"], r["top"], r["right"], r["base"]), 0
        art_w, art_h = box[2] - box[0], box[3] - box[1]

        def place(scale, x, y):
            """The art at `scale`, its top left corner at (x, y), and the box it then covers."""
            g = f'<g transform="translate({x - box[0] * scale:.2f} {y - box[1] * scale:.2f}) scale({scale:.4f})">{drawing}</g>'
            return g, (x, y, x + art_w * scale, y + art_h * scale + shadow * scale)

        def lockup(folder, name, art, art_box, x, baseline, cap, pad):
            text, width, descender = wordmark(x, baseline, cap, LABEL[variant])
            ascender = cap * 762 / CAP_HEIGHT   # the l and t rise a little above the capitals
            left, top = min(art_box[0], x), min(art_box[1], baseline - ascender)
            right, bottom = max(art_box[2], x + width), max(art_box[3], baseline + descender)
            view = (left - pad, top - pad, right - left + 2 * pad, bottom - top + 2 * pad)
            add(folder, name, svg(view, defs, art + text, "Days Until"), sizes)

        # Horizontal. In colour the capitals are a third of the squircle's height, centred on it.
        # The flat mark is 1.6 times their height, standing on the baseline, so today's dot rises
        # above them.
        cap = 0.32 * 824
        if colour:
            art, art_box = place(1, 100, 100)
            baseline = C + cap / 2
        else:
            art, art_box = place(1.6 * cap / art_h, 0, 0)
            baseline = art_box[3]
        lockup("02-horizontal", f"{NAME}-horizontal{suffix}", art, art_box, art_box[2] + 0.5 * cap, baseline,
               cap, 0.2 * cap)

        # Stacked: the wordmark centred under the art. The flat mark is 70% of the wordmark's width.
        cap = 0.24 * 824
        width = (WORDMARK_RIGHT - WORDMARK_LEFT) * cap / CAP_HEIGHT
        if colour:
            art, art_box = place(1, 100, 100)
            cap_top = 924 + 0.15 * 824
        else:
            scale = 0.7 * width / art_w
            art, art_box = place(scale, C - art_w * scale / 2, 0)
            cap_top = art_box[3] + 0.55 * cap
        lockup("03-stacked", f"{NAME}-stacked{suffix}", art, art_box, C - width / 2, cap_top + cap, cap, 0.3 * cap)

    # 04 · The app icon on Apple's grid, its margin included, as the system expects. 16 and 32 px
    # come from the small artwork.
    full = (0, 0, 1024, 1024)
    defs, drawing = icon("i")
    add("04-app-icon", f"{NAME}-icon", svg(full, defs, drawing, "Days Until"), [64, 128, 256, 512, 1024])
    defs, drawing = icon("i", spec=SMALL)
    add("04-app-icon", f"{NAME}-icon-small", svg(full, defs, drawing, "Days Until"), [16, 32],
        png=f"{NAME}-icon")
    for appearance in ("dark", "tinted"):
        defs, drawing = icon("i", appearance)
        add("04-app-icon", f"{NAME}-icon-{appearance}", svg(full, defs, drawing, "Days Until"), [1024])

    # 05 · The favicon: the small artwork, filling its square, no shadow.
    defs, drawing = icon("i", spec=SMALL, shadow=False)
    add("05-favicon", "favicon", svg((100, 100, 824, 824), defs, drawing, "Days Until"), [16, 32, 48])
    return files


def srgb(colour):
    r, g, b = (int(colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def app_icon(scratch):
    """DaysUntil/AppIcon.icon: one full-canvas PNG per part of the runway, and icon.json, which
    stacks them in three groups over the system's white gradient. The blue groups are opaque
    glass, so the blue keeps its strength; the ticks are plain, and in Dark mode the days ahead
    turn lighter than the days gone, so they still read as nearer."""
    r = layout(FULL)
    hx, hy, hs = r["well_x"], r["well_y"] + 0.1 * r["house"], r["house"]
    blue = "#0088FF"   # macOS 26's system blue
    a, d = ICON["default"], ICON["dark"]
    layers = {
        "house": ("", house(hx, hy, hs, "#FFFFFF")),
        "well": ("", f'<circle cx="{r["well_x"]:.1f}" cy="{r["well_y"]:.1f}" r="{r["well"]}" fill="{blue}"/>'),
        "today": ("", today(r, blue)),
        "ahead": ("", ticks(r, "none", a["ahead"])),
        "elapsed": ("", ticks(r, a["elapsed"], "none")),
    }
    files = []
    for name, (defs, drawing) in layers.items():
        path = scratch / f"layer-{name}.svg"
        # The canvas is the squircle itself, so the layers span its 824 pt.
        path.write_text(svg((100, 100, 824, 824), defs, drawing, name))
        files.append((path, [(APP_ICON / "Assets" / f"{name}.png", 1024)]))

    def layer(name, fill, dark=None, glass=True):
        fills = [{"value": fill}] + ([{"appearance": "dark", "value": dark}] if dark else [])
        return {"fill-specializations": fills, "glass": glass, "image-name": f"{name}.png", "name": name}

    gradient = {"automatic-gradient": srgb(blue)}
    shadow = {"kind": "neutral", "opacity": 0.5}
    icon = {
        "fill": {"automatic-gradient": srgb("#FFFFFF")},
        "groups": [
            {"layers": [layer("house", {"solid": srgb("#FFFFFF")}), layer("well", gradient)],
             "shadow": shadow, "translucency": {"enabled": False, "value": 0.5}},
            {"layers": [layer("today", gradient)],
             "shadow": shadow, "translucency": {"enabled": False, "value": 0.5}},
            {"layers": [layer("ahead", {"solid": srgb(a["ahead"])}, {"solid": srgb(d["ahead"])}, glass=False),
                        layer("elapsed", {"solid": srgb(a["elapsed"])}, {"solid": srgb(d["elapsed"])}, glass=False)],
             "shadow": shadow, "translucency": {"enabled": False, "value": 0.5}},
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (APP_ICON / "Assets").mkdir(parents=True, exist_ok=True)
    (APP_ICON / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")
    return files


def render(svg_path, outputs, scratch):
    """Renders `svg_path` at 2048 px wide in Chrome, then scales it down to each width."""
    text = svg_path.read_text()
    w, h = (float(v) for v in text.split('viewBox="')[1].split('"')[0].split()[2:])
    big_w, big_h = 2048, round(2048 * h / w)
    page = scratch / f"{svg_path.stem}.html"
    page.write_text(f'<html><body style="margin:0;background:transparent">'
                    f'<img src="{svg_path.as_uri()}" style="display:block;width:{big_w}px;height:{big_h}px"></body></html>')
    shot = scratch / f"{svg_path.stem}.png"
    chrome = subprocess.Popen([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                               "--default-background-color=00000000", "--allow-file-access-from-files",
                               f"--user-data-dir={scratch / ('profile-' + svg_path.stem)}",
                               f"--window-size={big_w},{big_h}", f"--screenshot={shot}", page.as_uri()],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Chrome writes the screenshot but doesn't always quit afterwards, so wait for the file instead.
    size, deadline = -1, time.monotonic() + 60
    while time.monotonic() < deadline:
        time.sleep(0.5)
        if shot.exists() and shot.stat().st_size == size > 0:
            break
        size = shot.stat().st_size if shot.exists() else -1
    chrome.kill()
    chrome.wait()
    image = Image.open(shot).convert("RGBA")
    assert image.size == (big_w, big_h), f"{svg_path.name}: Chrome drew {image.size}, not {(big_w, big_h)}"
    for path, width in outputs:
        height = round(width * h / w)
        image.resize((width, height), Image.LANCZOS).save(path, optimize=True)


def main():
    for folder in (OUTPUT, APP_ICON):
        if folder.exists():
            shutil.rmtree(folder)
    with tempfile.TemporaryDirectory() as scratch, concurrent.futures.ThreadPoolExecutor(4) as pool:
        scratch = pathlib.Path(scratch)
        files, layers = build(), app_icon(scratch)
        for job in [pool.submit(render, path, outputs, scratch) for path, outputs in files + layers]:
            job.result()
    count = sum(1 + len(outputs) for _, outputs in files)
    print(f"Wrote {count} files to {OUTPUT.relative_to(ROOT)} and {len(layers) + 1} to {APP_ICON.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
