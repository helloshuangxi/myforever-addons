"""Draw the small avatar status badges used by MyForeverChat."""
from pathlib import Path
from PIL import Image, ImageDraw

folder = Path(__file__).resolve().parent.parent / "_forever_/Interface/AddOns/MyForeverChat/Media/Presence"
folder.mkdir(parents=True, exist_ok=True)
for name, color in (("online", "#58e194"), ("offline", "#929ca7"), ("unknown", "#aeb8c0"), ("muted", "#ffcf75")):
    image = Image.new("RGBA", (128, 128))
    draw = ImageDraw.Draw(image)
    draw.ellipse((4, 4, 124, 124), fill="#19242c")
    if name == "unknown":
        draw.ellipse((25, 25, 103, 103), outline=color, width=11)
    elif name == "muted":
        draw.rounded_rectangle((43, 31, 85, 82), radius=19, fill=color)
        draw.rectangle((35, 72, 92, 84), fill=color)
        draw.ellipse((58, 83, 70, 96), fill=color)
        draw.line((25, 28, 104, 103), fill="#19242c", width=16)
        draw.line((25, 28, 104, 103), fill=color, width=8)
    else:
        draw.ellipse((24, 24, 104, 104), fill=color)
    image.resize((32, 32), Image.Resampling.LANCZOS).save(folder / f"{name}.tga")
print(f"Created four avatar badges in {folder}")
