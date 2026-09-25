"""Prepare unchanged 1x native clips for the Remotion edit on a hosted runner."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.submission_demo.compose import validate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('edit', type=Path)
    args = parser.parse_args()
    plan = validate(args.edit)
    public = Path(__file__).parent / 'public'
    media = public / 'media'
    media.mkdir(parents=True, exist_ok=True)
    for shot in plan['shots']:
        for clip in shot['clips']:
            source = plan['sources'][clip['source']]['path']
            destination = media / f"{shot['id']}-{clip['role']}.mp4"
            subprocess.run([
                'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                '-ss', str(clip['in']), '-i', str(source), '-t', str(shot['duration']),
                '-an', '-vf', 'fps=30,setsar=1', '-c:v', 'libx264',
                '-threads', '2', '-preset', 'fast', '-crf', '18',
                '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(destination),
            ], check=True)
    for folder, files in {
        'brand': ['meowwatch.svg'],
        'fonts': ['DMSans.ttf', 'DMSerifDisplay.ttf', 'DMSans-OFL.txt', 'DMSerifDisplay-OFL.txt'],
    }.items():
        destination = public / folder
        destination.mkdir(exist_ok=True)
        for name in files:
            shutil.copyfile(ROOT / 'assets' / folder / name, destination / name)
    (media / 'source-edit.json').write_text(json.dumps(plan['edl'], indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
