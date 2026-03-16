#!/usr/bin/env python3
"""Generate App Store screenshots for iOS / iPad / macOS size presets."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

try:
    from PIL import Image, ImageColor, ImageOps
except ModuleNotFoundError as exc:
    if exc.name != "PIL":
        raise
    raise SystemExit(
        "Missing dependency: Pillow\n"
        "Install with: python3 -m pip install Pillow"
    )

SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp"}
MAX_SCREENSHOTS = 10

Size = Tuple[int, int]

SIZE_PRESETS: Dict[str, Dict[str, List[Size]]] = {
    # iPhone screenshot sizes (common App Store Connect presets).
    "ios": {
        "portrait": [(1242, 2688), (1284, 2778), (1290, 2796)],
        "landscape": [(2688, 1242), (2778, 1284), (2796, 1290)],
    },
    # iPad 12.9"/13" accepted sizes.
    "ipad": {
        "portrait": [(2048, 2732), (2064, 2752)],
        "landscape": [(2732, 2048), (2752, 2064)],
    },
    # macOS screenshot sizes (landscape only).
    "macos": {
        "portrait": [],
        "landscape": [(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)],
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate App Store screenshots for iOS / iPad / macOS presets."
    )
    parser.add_argument(
        "--input",
        default="input",
        help="Input directory containing source screenshots. Default: input",
    )
    parser.add_argument(
        "--output",
        default="output",
        help="Output directory. Default: output",
    )
    parser.add_argument(
        "--platform",
        choices=["ios", "ipad", "macos", "all"],
        default="all",
        help="Target platform preset. Default: all",
    )
    parser.add_argument(
        "--orientation",
        choices=["portrait", "landscape", "both"],
        default="both",
        help="Target orientation. Default: both",
    )
    parser.add_argument(
        "--bg",
        default="#FFFFFF",
        help="Background color, e.g. #FFFFFF",
    )
    parser.add_argument(
        "--padding",
        type=float,
        default=0.06,
        help="Inner padding ratio (0.0~0.45). Default: 0.06",
    )
    parser.add_argument(
        "--format",
        choices=["png", "jpg"],
        default="png",
        help="Output image format. Default: png",
    )
    return parser.parse_args()


def list_input_files(input_dir: Path) -> List[Path]:
    if not input_dir.exists():
        raise FileNotFoundError(f"Input folder not found: {input_dir}")
    files = sorted(
        [path for path in input_dir.iterdir() if path.suffix.lower() in SUPPORTED_EXTS]
    )
    if not files:
        raise FileNotFoundError(f"No supported images found in: {input_dir}")
    if len(files) > MAX_SCREENSHOTS:
        raise ValueError(
            f"Found {len(files)} images, but App Store Connect accepts at most "
            f"{MAX_SCREENSHOTS} screenshots per display size."
        )
    return files


def get_target_platforms(platform_arg: str) -> List[str]:
    if platform_arg == "all":
        return ["ios", "ipad", "macos"]
    return [platform_arg]


def get_target_sizes(platform: str, orientation: str) -> Iterable[Size]:
    preset = SIZE_PRESETS[platform]
    if orientation == "portrait":
        return preset["portrait"]
    if orientation == "landscape":
        return preset["landscape"]
    return [*preset["portrait"], *preset["landscape"]]


def fit_to_canvas(
    image: Image.Image,
    canvas_size: Size,
    background_color: str,
    padding_ratio: float,
) -> Image.Image:
    canvas_w, canvas_h = canvas_size
    usable_w = int(canvas_w * (1 - padding_ratio * 2))
    usable_h = int(canvas_h * (1 - padding_ratio * 2))

    background_rgba = ImageColor.getrgb(background_color) + (255,)
    canvas = Image.new("RGBA", canvas_size, background_rgba)
    fitted = ImageOps.contain(image, (usable_w, usable_h), Image.Resampling.LANCZOS)

    x = (canvas_w - fitted.width) // 2
    y = (canvas_h - fitted.height) // 2
    canvas.alpha_composite(fitted, (x, y))
    return canvas


def save_image(image: Image.Image, output_path: Path, out_format: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if out_format == "jpg":
        image.convert("RGB").save(output_path, "JPEG", quality=95, optimize=True)
    else:
        image.save(output_path, "PNG")


def process_one(
    src_path: Path,
    output_root: Path,
    platforms: Iterable[str],
    orientation: str,
    background_color: str,
    padding_ratio: float,
    out_format: str,
) -> None:
    with Image.open(src_path) as raw:
        image = ImageOps.exif_transpose(raw).convert("RGBA")

    ext = ".jpg" if out_format == "jpg" else ".png"
    for platform in platforms:
        for width, height in get_target_sizes(platform, orientation):
            out_path = (
                output_root
                / platform
                / f"{width}x{height}"
                / f"{src_path.stem}_{width}x{height}{ext}"
            )
            result = fit_to_canvas(
                image=image,
                canvas_size=(width, height),
                background_color=background_color,
                padding_ratio=padding_ratio,
            )
            save_image(result, out_path, out_format)
            print(f"Saved: {out_path}")


def main() -> None:
    args = parse_args()

    if not (0.0 <= args.padding <= 0.45):
        raise ValueError("--padding must be between 0.0 and 0.45")

    # Validate color early.
    ImageColor.getrgb(args.bg)

    input_dir = Path(args.input)
    output_dir = Path(args.output)
    files = list_input_files(input_dir)
    platforms = get_target_platforms(args.platform)

    for file_path in files:
        process_one(
            src_path=file_path,
            output_root=output_dir,
            platforms=platforms,
            orientation=args.orientation,
            background_color=args.bg,
            padding_ratio=args.padding,
            out_format=args.format,
        )
    print("\nDone.")


if __name__ == "__main__":
    main()
