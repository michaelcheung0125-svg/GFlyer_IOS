#!/usr/bin/env python3
"""
App 的飛豬圖：由 JetPiggy 品牌中心的飛豬正本轉出，寫到 GFlyerIOS/Resources/Assets.xcassets，兩個版本共用。

    python scripts/make_brand_art.py                         正本在 ../JetPiggy-Brand
    python scripts/make_brand_art.py --brand D:/JetPiggy-Brand

正本換了（品牌中心 mascot/poses/），重跑這個程式，再看一次圖。圖和 Android 的
tools/make_brand_art.py 用同一套正本和做法（GFlyer-Suite DRIFT D36），不要拿 Android 的輸出檔再縮：
Android 的 App 圖示是自適應圖示的前景，四邊留了安全區。

| 輸出 | 正本 | 用在哪裏 |
|---|---|---|
| AppIcon.appiconset/gflyer_app_icon.png | sit | App 圖示（1024，不透明） |
| GFlyerIcon.imageset/gflyer_icon_art.png | sit | 主畫面導覽列的小圖示，和 App 圖示同一個構圖 |
| GFlyerMarker.imageset/gflyer_current_location.png | head_small | 地圖上的選取位置（定位針，針尖在 96% 高度） |
"""
from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "GFlyerIOS" / "Resources" / "Assets.xcassets"
PAPER = (0xF7, 0xF3, 0xE8)  # 正本的紙底
INK = (0x16, 0x16, 0x16)
BLUE = (0x2A, 0x63, 0xA5)  # 風鏡藍：品牌中心 identity/README.md 裏網站用的文字藍

# 包住角色的最小圓佔圖示闊度的比例。Android 桌面上看得到的是自適應圖示中間的 72dp，
# 角色的圓是 66dp 安全區（前景圖 512px 裏的 352px，看得到的部分是 384px），
# 用同一個比例，iOS 的圖示看起來就和 Android 桌面上的一樣。iOS 把圖示裁成圓角方形，
# 比圓形多留了四個角，所以這個比例不會裁到角色。
ICON_CIRCLE = 352 / 384


def load(poses: Path, name: str) -> Image.Image:
    image = Image.open(poses / f"jetpiggy_{name}.png").convert("RGB")
    corner = image.getpixel((2, 2))
    if corner != PAPER:
        raise SystemExit(f"jetpiggy_{name}.png 的底色是 {corner}，不是紙底 {PAPER}：程式靠同色紙底拼接，要先處理正本。")
    return image


def content_mask(image: Image.Image) -> Image.Image:
    """和紙底不同的部分（角色本身）。"""
    diff = ImageChops.difference(image, Image.new("RGB", image.size, PAPER)).convert("L")
    return diff.point(lambda v: 255 if v > 24 else 0)


def fit_on_paper(image: Image.Image, box_size: int, center: tuple[int, int], canvas: int) -> Image.Image:
    """把角色縮放到 box_size 的方框內，放在紙底畫布的 center。紙底同色，所以拼接不會有邊。"""
    box = content_mask(image).getbbox()
    if box is None:
        raise SystemExit("正本是空白的")
    figure = image.crop(box)
    scale = box_size / max(figure.width, figure.height)
    figure = figure.resize((max(1, round(figure.width * scale)), max(1, round(figure.height * scale))), Image.LANCZOS)
    out = Image.new("RGB", (canvas, canvas), PAPER)
    out.paste(figure, (center[0] - figure.width // 2, center[1] - figure.height // 2))
    return out


def convex_hull(points: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """凸包（monotone chain）。"""
    points = sorted(set(points))

    def cross(o, a, b) -> int:
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower: list[tuple[int, int]] = []
    upper: list[tuple[int, int]] = []
    for p in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def enclosing_circle(points: list[tuple[int, int]]) -> tuple[float, float, float]:
    """包住所有點的最小圓（Welzl），回傳圓心和半徑。"""

    def through2(a, b):
        cx, cy = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        return cx, cy, math.dist(a, (cx, cy))

    def through3(a, b, c):
        (ax, ay), (bx, by), (cx, cy) = a, b, c
        d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
        if abs(d) < 1e-9:
            return None
        ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
        uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d
        return ux, uy, math.dist(a, (ux, uy))

    def inside(circle, p) -> bool:
        return math.dist(circle[:2], p) <= circle[2] + 1e-6

    points = points[:]
    random.Random(1).shuffle(points)
    circle = (points[0][0], points[0][1], 0.0)
    for i, p in enumerate(points):
        if inside(circle, p):
            continue
        circle = (p[0], p[1], 0.0)
        for j, q in enumerate(points[:i]):
            if inside(circle, q):
                continue
            circle = through2(p, q)
            for r in points[:j]:
                if not inside(circle, r):
                    circle = through3(p, q, r) or circle
    return circle


def app_icon(poses: Path, size: int) -> Image.Image:
    """
    App 圖示：整隻坐着的飛豬放在紙底中間，包住角色的最小圓佔 ICON_CIRCLE。角色不是方的
    （翅膀、尾巴伸出去），用外框方塊來縮會縮得太小。不透明，因為 App Store 不收有透明的 App 圖示。
    """
    image = load(poses, "sit")
    step = 4  # 縮小再找邊界點，誤差在圖示上不到 1 像素
    small = content_mask(image.resize((image.width // step, image.height // step)))
    points = [(x * step, y * step) for y in range(small.height) for x in range(small.width) if small.getpixel((x, y))]
    if not points:
        raise SystemExit("正本是空白的")
    cx, cy, radius = enclosing_circle(convex_hull(points))
    scale = (size * ICON_CIRCLE / 2) / radius
    figure = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    out = Image.new("RGB", (size, size), PAPER)
    out.paste(figure, (round(size / 2 - cx * scale), round(size / 2 - cy * scale)))
    return out


def location_pin(poses: Path, size: int) -> Image.Image:
    """
    定位針：墨線外框、風鏡藍的針身，中間的紙底圓圈放豬頭；針尖在 96% 高度（MainView 的
    Annotation 錨點是 0.5, 0.96）。針身要用深色：淺色的地圖上，紙底的針看不出在哪裏。
    和 Android 的定位針相同。
    """
    scale = 4  # 先畫大四倍再縮小，邊緣才平滑
    big = size * scale
    cx, cy, radius = big // 2, round(big * 0.41), round(big * 0.39)
    tip_y = round(big * 0.96)
    stroke = round(big * 0.03)
    ring = round(big * 0.06)  # 藍色針身在豬頭圓圈外面露出的闊度

    def drop(draw: ImageDraw.ImageDraw, r: float, tip: float, fill) -> None:
        distance = tip - cy
        angle = math.asin(min(1.0, r / distance))
        dx, dy = r * math.cos(angle), r * math.sin(angle)
        draw.polygon([(cx - dx, cy + dy), (cx, tip), (cx + dx, cy + dy)], fill=fill)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)

    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    drop(draw, radius, tip_y, INK + (255,))
    body = radius - stroke
    body_tip = tip_y - stroke / math.sin(math.asin(radius / (tip_y - cy)))
    drop(draw, body, body_tip, BLUE + (255,))

    # 豬頭圓圈：紙底，外面一圈細墨線，和藍色針身分開
    face = body - ring
    line = round(stroke * 0.6)
    draw.ellipse((cx - face - line, cy - face - line, cx + face + line, cy + face + line), fill=INK + (255,))
    head = fit_on_paper(load(poses, "head_small"), box_size=round(face * 1.55), center=(face, face), canvas=face * 2)
    mask = Image.new("L", head.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, head.width - 1, head.height - 1), fill=255)
    canvas.paste(head, (cx - face, cy - face), mask)
    return canvas.resize((size, size), Image.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser(description="產生 App 的飛豬圖")
    parser.add_argument("--brand", type=Path, default=ROOT.parent / "JetPiggy-Brand", help="品牌中心的資料夾")
    args = parser.parse_args()
    poses = args.brand / "mascot" / "poses"
    if not poses.is_dir():
        raise SystemExit(f"找不到飛豬正本：{poses}")

    outputs = {
        OUT / "AppIcon.appiconset" / "gflyer_app_icon.png": app_icon(poses, 1024),
        OUT / "GFlyerIcon.imageset" / "gflyer_icon_art.png": app_icon(poses, 512),
        OUT / "GFlyerMarker.imageset" / "gflyer_current_location.png": location_pin(poses, 512),
    }
    for path, image in outputs.items():
        if not path.parent.is_dir():
            raise SystemExit(f"找不到 {path.parent.relative_to(ROOT).as_posix()}：asset catalog 的 Contents.json 要先在")
        image.save(path, optimize=True)
        print(f"{path.relative_to(ROOT).as_posix()}  {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
