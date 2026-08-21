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

DISPLAY = ROOT / "assets" / "fonts" / "Fraunces.ttf"
BODY = ROOT / "assets" / "fonts" / "HankenGrotesk.ttf"

# Sampled from the previous marketing art so the listing keeps its look.
TOP = (33, 53, 94)
BOTTOM = (14, 24, 48)
WARM = (150, 92, 78)      # top-left glow
COOL = (34, 62, 112)      # bottom-right glow
HEADLINE = (255, 255, 255)
SUBHEAD = (170, 186, 212)
ACCENT = (243, 118, 32)

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
    ("02_unit_detail", "Mark rent paid in one tap",
     "Deposits, charges and full history for every unit"),
    ("03_reports", "Know where you stand",
     "Monthly, quarterly and yearly income summaries"),
    ("04_add_unit", "Add a unit in seconds",
     "Tenant, rent, deposit and lease start date"),
    ("05_settings", "Built for Nepal",
     "Bikram Sambat calendar, PIN lock and cloud backup"),
]


def display_font(size):
    """Fraunces at its display optical size and heaviest weight."""
    f = ImageFont.truetype(str(DISPLAY), size)
    f.set_variation_by_axes([144, 900, 0, 1])  # opsz, wght, soft, wonk
    return f


def body_font(size, weight=400):
    f = ImageFont.truetype(str(BODY), size)
    f.set_variation_by_axes([weight])
    return f


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
    """Vertical navy ramp plus the two soft corner glows."""
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

    glow(0.10, 0.05, max(w, h) * 0.42, WARM, 150)
    glow(0.08, 0.62, max(w, h) * 0.30, WARM, 70)
    glow(0.95, 0.90, max(w, h) * 0.35, COOL, 90)
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
    for device in DEVICES:
        print(device)
        for i, (raw_name, headline, subhead) in enumerate(SHOTS, start=1):
            compose(device, i, raw_name, headline, subhead)
