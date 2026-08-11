"""
Generate app icons for 睿測 EdgeWise
Creates icons for both Android (mipmap) and iOS (AppIcon.appiconset)
"""

from PIL import Image, ImageDraw
import os

# === Configuration ===
BASE_DIR = r"c:\Users\scsor\OneDrive\Desktop\corner_vision_free_research_v1"
ANDROID_RES = os.path.join(BASE_DIR, "android", "app", "src", "main", "res")
IOS_ICONSET = os.path.join(BASE_DIR, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")

# === Icon Design ===
def create_base_icon(size=1024):
    """Create the base icon image at given size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # --- Rounded square background with gradient ---
    corner_radius = int(size * 0.225)
    steps = size // 2
    for i in range(steps):
        ratio = i / steps
        r = int(15 + ratio * 50)
        g = int(20 + ratio * 30)
        b = int(60 + ratio * 80)
        color = (r, g, b, 255)

        cr = max(1, corner_radius - int((1 - ratio) * corner_radius * 0.3))
        x0, y0 = i, i
        x1, y1 = size - i - 1, size - i - 1
        draw.rounded_rectangle([x0, y0, x1, y1], radius=cr, fill=color)

    # --- Center geometric "E" / Edge logo ---
    cx, cy = size / 2, size / 2
    s = size / 1024

    white = (255, 255, 255, 255)
    light_blue = (120, 200, 255, 220)

    bar_w = int(220 * s)
    bar_h = int(36 * s)
    spine_w = int(36 * s)
    spine_h = int(340 * s)

    # Vertical spine
    spine_x0 = int(cx - spine_w // 2)
    spine_y0 = int(cy - spine_h // 2)
    spine_x1 = spine_x0 + spine_w
    spine_y1 = spine_y0 + spine_h
    draw.rounded_rectangle(
        [spine_x0, spine_y0, spine_x1, spine_y1],
        radius=int(spine_w // 2), fill=white
    )

    # Top bar
    bar_top_y = spine_y0
    bar_x0 = spine_x0
    bar_x1 = bar_x0 + bar_w
    draw.rounded_rectangle(
        [bar_x0, bar_top_y, bar_x1, bar_top_y + bar_h],
        radius=int(bar_h // 2), fill=white
    )

    # Middle bar (70% width)
    bar_mid_y = int(cy - bar_h // 2)
    bar_mid_x1 = bar_x0 + int(bar_w * 0.7)
    draw.rounded_rectangle(
        [bar_x0, bar_mid_y, bar_mid_x1, bar_mid_y + bar_h],
        radius=int(bar_h // 2), fill=white
    )

    # Bottom bar
    bar_bot_y = spine_y1 - bar_h
    draw.rounded_rectangle(
        [bar_x0, bar_bot_y, bar_x1, bar_bot_y + bar_h],
        radius=int(bar_h // 2), fill=white
    )

    # Edge accent arrow at top-right
    accent_size = int(50 * s)
    tip_x = bar_x1 + int(15 * s)
    tip_y = bar_top_y + bar_h // 2
    accent_points = [
        (tip_x, tip_y),
        (tip_x - accent_size, tip_y - accent_size // 2),
        (tip_x - accent_size, tip_y + accent_size // 2),
    ]
    draw.polygon(accent_points, fill=light_blue)

    return img


# === Size definitions ===
ANDROID_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


# === Generate ===
def main():
    print("Creating base icon (1024x1024)...")
    base_icon = create_base_icon(1024)

    # Save base icon for iOS
    base_path = os.path.join(IOS_ICONSET, "Icon-App-1024x1024@1x.png")
    base_icon.save(base_path, "PNG")
    print(f"  Saved: {base_path}")

    # Generate Android icons
    print("\nGenerating Android icons...")
    for folder, size in ANDROID_SIZES.items():
        target_dir = os.path.join(ANDROID_RES, folder)
        os.makedirs(target_dir, exist_ok=True)
        resized = base_icon.resize((size, size), Image.LANCZOS)
        icon_path = os.path.join(target_dir, "ic_launcher.png")
        resized.save(icon_path, "PNG")
        print(f"  Saved: {icon_path} ({size}x{size})")

    # Generate remaining iOS icons
    print("\nGenerating iOS icons...")
    for filename, size in IOS_SIZES.items():
        if filename == "Icon-App-1024x1024@1x.png":
            continue
        icon_path = os.path.join(IOS_ICONSET, filename)
        resized = base_icon.resize((size, size), Image.LANCZOS)
        resized.save(icon_path, "PNG")
        print(f"  Saved: {icon_path} ({size}x{size})")

    print("\nAll icons generated successfully!")
    print(f"   Android: {len(ANDROID_SIZES)} sizes in {ANDROID_RES}/mipmap-*")
    print(f"   iOS:     {len(IOS_SIZES)} sizes in {IOS_ICONSET}")


if __name__ == "__main__":
    main()
