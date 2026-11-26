"""Compose the App Store screenshots from the raw app renders.

Build 2 was rejected under guideline 2.3.10: the uploaded shots were phone
mockups wearing a *painted* status bar, and the iPad set showed an iPhone. So
this pipeline has two halves and neither of them draws a device:

  1. test/store_screenshots_test.dart renders the real widget tree at each
     store's exact canvas size and writes store/raw/<device>/*.png.
  2. this script lays a headline over that render — no frame, no status bar.

Run (from the repo root, after regenerating the raw renders):

    python store/compose_screenshots.py

Writes store/listing/<device>/01..05.png, overwriting in place.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "store" / "raw"
OUT = ROOT / "store" / "listing"

# The app uses the system font, so the headlines do too (the raw renders load
# this same file — see test/store_screenshots_test.dart).
SYSTEM_FONT = "/System/Library/Fonts/SFNS.ttf"

# Deep blue ramp behind the light app panel: the app's control blue, darkened,
# with the orange of the collection bar as the accent.
TOP = (18, 78, 190)
BOTTOM = (8, 32, 96)
GLOW_A = (64, 148, 255)   # top-left glow
GLOW_B = (20, 56, 150)    # bottom-right glow
HEADLINE = (255, 255, 255)
SUBHEAD = (206, 222, 250)
ACCENT = (255, 149, 0)

# App Store canvases. The raw render for each is exactly these pixels, so the
# app is shown at true device proportions.
DEVICES = {
    "ios_iphone_6.7": (1290, 2796),
    "ios_iphone_6.5": (1284, 2778),
    "ios_ipad_12.9": (2048, 2732),
}

SHOTS = [
    ("01_ledger", "All your rent in one place",
     "See who has paid and what's pending at a glance"),
    ("02_unit_detail", "Rent, bills and deductions",
     "Electricity, water and deposits on every unit's ledger"),
    ("03_reports", "Know where you stand",
     "Charges, deductions and income by month, quarter or year"),
    ("04_add_unit", "Add a unit in seconds",
     "Tenant, rent, deposit and rent start date"),
    ("05_settings", "Built for Nepal",
     "Bikram Sambat dates, Nepali Rupees, PIN lock and backup"),
]

# The US storefront set (`--market us`): same shots rendered in US Dollars
# with AD dates, read from store/raw_us/ and written to store/listing_us/.
SHOTS_US = SHOTS[:4] + [
    ("05_settings", "Private and backed up",
     "PIN lock, automatic cloud backup, export any time"),
]


def _system_font(size, weight):
    f = ImageFont.truetype(SYSTEM_FONT, size)
    # Axes: width, optical size, grade, weight.
    f.set_variation_by_axes([100, min(96, max(17, size)), 400, weight])
    return f


def display_font(size):
    return _system_font(size, 800)


def body_font(size, weight=500):
    return _system_font(size, weight)


def fit(make_font, text, max_width, start, floor=8):
    """Largest size at or below `start` whose `text` fits `max_width`."""
    size = start
    while size > floor:
        font = make_font(size)
        if font.getbbox(text)[2] <= max_width:
            return font
        size -= 2
    return make_font(floor)


def background(w, h):
    """Vertical blue ramp plus the two soft corner glows."""
    bg = Image.new("RGB", (w, h))
    px = bg.load()
    for y in range(h):
        t = y / (h - 1)
        row = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = row

    # Glows are painted small and upscaled — a cheap, smooth radial falloff.
    def glow(cx, cy, radius, color, strength):
        s = 96
        layer = Image.new("L", (s, s), 0)
        d = ImageDraw.Draw(layer)
        r = radius / max(w, h) * s
        d.ellipse([s * cx - r, s * cy - r, s * cx + r, s * cy + r], fill=strength)
        layer = layer.filter(ImageFilter.GaussianBlur(s / 7)).resize(
            (w, h), Image.LANCZOS)
        bg.paste(Image.new("RGB", (w, h), color), (0, 0), layer)

    glow(0.10, 0.04, max(w, h) * 0.42, GLOW_A, 120)
    glow(0.95, 0.92, max(w, h) * 0.36, GLOW_B, 110)
    return bg


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, img.width - 1, img.height - 1], radius, fill=255)
    img.putalpha(mask)
    return img


def compose(device, index, raw_name, headline, subhead):
    w, h = DEVICES[device]
    raw_path = RAW / device / f"{raw_name}.png"
    shot = Image.open(raw_path).convert("RGB")
    if shot.size != (w, h):
        raise SystemExit(f"{raw_path} is {shot.size}, expected {(w, h)}")

    canvas = background(w, h)
    draw = ImageDraw.Draw(canvas)

    margin = round(w * 0.055)
    text_width = w - 2 * margin

    hf = fit(display_font, headline, text_width, round(h * 0.060))
    sf = fit(body_font, subhead, text_width, round(h * 0.0225))

    y = round(h * 0.043)
    draw.text((margin, y), headline, font=hf, fill=HEADLINE)
    y += hf.getbbox(headline)[3] + round(h * 0.012)

    rule_h = max(4, round(h * 0.0032))
    draw.rounded_rectangle(
        [margin, y, margin + round(w * 0.115), y + rule_h], rule_h, fill=ACCENT)
    y += rule_h + round(h * 0.026)

    draw.text((margin, y), subhead, font=sf, fill=SUBHEAD)
    y += sf.getbbox(subhead)[3] + round(h * 0.030)

    # Fit the render into what's left, keeping true device proportions.
    avail_w = w - 2 * round(w * 0.075)
    avail_h = h - y - round(h * 0.035)
    scale = min(avail_w / w, avail_h / h)
    panel = shot.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    panel = rounded(panel, round(w * 0.022))

    px = (w - panel.width) // 2
    py = y

    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [px, py + round(h * 0.004), px + panel.width, py + panel.height],
        round(w * 0.022), fill=(0, 0, 0, 120))
    canvas.paste(Image.alpha_composite(
        canvas.convert("RGBA"), shadow.filter(
            ImageFilter.GaussianBlur(w * 0.012))).convert("RGB"), (0, 0))
    canvas.paste(panel, (px, py), panel)

    dest = OUT / device / f"{index:02d}.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dest, optimize=True)
    print(f"  {dest.relative_to(ROOT)}  {canvas.size}")


if __name__ == "__main__":
    import sys
    shots = SHOTS
    if sys.argv[1:] == ["--market", "us"]:
        RAW = ROOT / "store" / "raw_us"
        OUT = ROOT / "store" / "listing_us"
        shots = SHOTS_US
    for device in DEVICES:
        print(device)
        for i, (raw_name, headline, subhead) in enumerate(shots, start=1):
            compose(device, i, raw_name, headline, subhead)
