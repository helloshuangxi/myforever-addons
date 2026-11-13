"""Draw original 32px TGA chat faces without external image assets."""
from pathlib import Path
from PIL import Image, ImageDraw

folder = Path(__file__).resolve().parent.parent / "_forever_/Interface/AddOns/MyForeverChat/Media/Emotes"
folder.mkdir(parents=True, exist_ok=True)
names = ["smile", "laugh", "wink", "love", "sad", "cry", "angry", "surprise", "cool", "sweat", "sleep", "heart"]
for name in names:
    image = Image.new("RGBA", (128,128))
    d = ImageDraw.Draw(image)
    dark, pink = "#62462d", "#ee6b82"
    if name != "heart":
        d.ellipse((6,6,122,122), fill="#ffd55c", outline="#e4a52c", width=4)
        d.ellipse((20,77,39,87), fill="#f5ac6a"); d.ellipse((89,77,108,87), fill="#f5ac6a")
    def heart(cx, cy, scale=1):
        r=12*scale
        d.ellipse((cx-r,cy-r,cx+3*scale,cy+3*scale),fill=pink)
        d.ellipse((cx-3*scale,cy-r,cx+r,cy+3*scale),fill=pink)
        d.polygon([(cx-r,cy-2*scale),(cx+r,cy-2*scale),(cx,cy+15*scale)],fill=pink)
    if name == "heart":
        heart(64,57,3.5)
    elif name == "love":
        heart(43,47,0.85); heart(86,47,0.85)
    elif name == "cool":
        d.rounded_rectangle((22,38,59,63),radius=7,fill="#293646")
        d.rounded_rectangle((69,38,106,63),radius=7,fill="#293646")
        d.line((57,45,71,45),fill=dark,width=5)
    elif name in ("laugh","sleep"):
        d.arc((29,42,54,57),180,350,fill=dark,width=5)
        d.arc((76,42,101,57),180,350,fill=dark,width=5)
    else:
        d.ellipse((35,42,45,57),fill=dark)
        if name == "wink": d.line((78,50,94,50),fill=dark,width=5)
        else: d.ellipse((83,42,93,57),fill=dark)
    if name in ("smile","wink","love","cool","sweat"):
        d.arc((37,57,92,96),8,172,fill=dark,width=5)
    elif name == "laugh":
        d.pieslice((37,61,92,102),0,180,fill=dark)
        d.line((40,80,90,80),fill="#fff5d9",width=6)
    elif name in ("sad","cry","angry"):
        d.arc((42,81,87,105),190,350,fill=dark,width=5)
    elif name in ("surprise","sleep"):
        d.ellipse((55,77,73,97),fill=dark)
    if name == "angry":
        d.line((27,31,50,40),fill=dark,width=5); d.line((77,40,100,31),fill=dark,width=5)
    if name in ("cry","sweat"):
        x=29 if name=="cry" else 99
        d.polygon([(x,57),(x-7,75),(x+7,75)],fill="#62b6ec")
        d.ellipse((x-7,69,x+7,83),fill="#62b6ec")
    image.resize((32,32),Image.Resampling.LANCZOS).save(folder/f"{name}.tga")
print(f"Created {len(names)} original TGA faces in {folder}")
