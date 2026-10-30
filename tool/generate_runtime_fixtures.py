"""Generate small, original media samples used by packaged runtime verification."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--ffmpeg', default='ffmpeg')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent / 'test/fixtures/media'
root.mkdir(parents=True, exist_ok=True)
videos = [
    ('avc.mp4', ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '30']),
    ('hevc.mp4', ['-c:v', 'libx265', '-preset', 'ultrafast', '-crf', '35', '-x265-params', 'pools=1:frame-threads=1:log-level=error']),
    ('av1.mp4', ['-c:v', 'libaom-av1', '-cpu-used', '8', '-crf', '45', '-b:v', '0', '-threads', '2']),
]
for name, options in videos:
    subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
                    '-i', 'testsrc2=s=128x72:r=8', '-t', '2', '-an', *options,
                    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(root / name)], check=True)
for name, options in [
    ('aac.m4a', ['-c:a', 'aac', '-b:a', '128k']),
    ('hires.flac', ['-c:a', 'flac', '-sample_fmt', 's32', '-ar', '96000']),
    ('dolby.eac3', ['-c:a', 'eac3', '-ac', '6', '-b:a', '384k']),
]:
    subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
                    '-i', 'sine=frequency=440:sample_rate=48000', '-t', '2', '-vn', *options,
                    str(root / name)], check=True)
for path in sorted(root.iterdir()):
    print(f'{path.name}: {path.stat().st_size} bytes')
