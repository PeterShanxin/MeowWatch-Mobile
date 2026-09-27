"""Cut the film's 1x app captures from the raw local recordings.

Raw recordings stay outside the repository. The bounded excerpts written to
source-media/ are the film's only app footage; see source-media/README.md.
"""
from pathlib import Path
import argparse
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

# name: (recording, start seconds, duration seconds, crop "w:h:x:y" or None, output width)
CUTS = {
    'phone-start': ('take4-phone.mkv', 108.0, 16.0, None, 720),
    'phone-invite': ('take4-phone.mkv', 128.0, 5.0, None, 720),
    'phone-continue': ('take4-phone.mkv', 138.0, 5.0, None, 720),
    'phone-paywall': ('take4-phone.mkv', 305.0, 32.0, None, 720),
    'phone-themes': ('take3-phone.mkv', 30.0, 16.0, None, 720),
    'phone-invite-video': ('take5-invite.mp4', 2.8, 27.0, None, 720),
    'together-sync': ('take5-desktop.mp4', 0.0, 26.0, '1728:810:43:118', 1728),
    'together-react': ('take6-desktop.mp4', 5.0, 11.0, '1728:810:43:118', 1728),
}


def cut(recordings: Path, name: str, spec) -> Path:
    recording, start, duration, crop, width = spec
    filters = [f'crop={crop}'] if crop else []
    filters += [f'scale={width}:-2:flags=lanczos', 'fps=30', 'setsar=1']
    output = HERE / 'source-media' / f'{name}.mp4'
    subprocess.run([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
        '-ss', str(start), '-i', str(recordings / recording), '-t', str(duration),
        '-an', '-vf', ','.join(filters), '-c:v', 'libx264', '-preset', 'slow',
        '-crf', '17', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(output),
    ], check=True)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recordings', type=Path,
                        help='Directory with the raw captures; omit to reuse committed excerpts')
    args = parser.parse_args()
    if args.recordings:
        for name, spec in CUTS.items():
            print(cut(args.recordings, name, spec))
    media = HERE / 'public' / 'media'
    media.mkdir(parents=True, exist_ok=True)
    for clip in (HERE / 'source-media').glob('*.mp4'):
        shutil.copyfile(clip, media / clip.name)
    music = HERE / 'public' / 'music'
    music.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(HERE / 'source-media' / 'voiceover.mp3', music / 'voiceover.mp3')
    for folder, files in {
        'brand': ['meowwatch.svg'],
        'fonts': ['DMSans.ttf', 'DMSerifDisplay.ttf', 'DMSans-OFL.txt', 'DMSerifDisplay-OFL.txt'],
    }.items():
        destination = HERE / 'public' / folder
        destination.mkdir(parents=True, exist_ok=True)
        for name in files:
            shutil.copyfile(ROOT / 'assets' / folder / name, destination / name)


if __name__ == '__main__':
    main()
