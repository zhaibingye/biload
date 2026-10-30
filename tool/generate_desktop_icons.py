"""Regenerate desktop icons from assets/brand/biload.svg.

Development dependencies: python -m pip install resvg-py Pillow
"""
from io import BytesIO
from pathlib import Path

from PIL import Image
from resvg_py import svg_to_bytes


def main():
    root = Path(__file__).resolve().parent.parent
    svg = root / 'assets/brand/biload.svg'
    # Render once at full resolution, then downsample for small desktop icons.
    master = Image.open(BytesIO(svg_to_bytes(svg_path=str(svg), width=1024)))
    macos = root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    for size in (16, 32, 64, 128, 256, 512, 1024):
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            macos / f'app_icon_{size}.png')
    master.save(root / 'windows/runner/resources/app_icon.ico',
                sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
    print('Updated Windows ICO and macOS AppIcon; Linux uses the source SVG.')


if __name__ == '__main__':
    main()
