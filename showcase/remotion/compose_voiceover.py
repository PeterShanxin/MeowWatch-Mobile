"""Synthesized narration for the launch film.

Each line is spoken by a Microsoft neural voice (edge-tts) and placed at a film
time. Writes source-media/voiceover.mp3 and src/voiceover.json (the spoken
intervals, used to duck the score). Requires network access; the outputs are
committed so rendering does not.
"""
from pathlib import Path
import asyncio
import json
import subprocess
import tempfile

import edge_tts

HERE = Path(__file__).resolve().parent
VOICE = 'en-US-AvaNeural'
RATE = '-6%'
LENGTH = 67.5
SAMPLE_RATE = 44100

# (film second, line). Each line must end before the next begins.
LINES = [
    (0.6, 'Long-distance movie nights usually start like this.'),
    (5.9, 'Meet MeowWatch.'),
    (10.0, 'Start a room, and send the invite. Joining is always free.'),
    (17.4, "If you're watching a video link, the invite brings the movie along."),
    (22.9, 'Two screens, one movie night. Press play on the phone, and the laptop plays too.'),
    (31.8, 'Pause on either side, and you both pause.'),
    (37.6, 'Send a reaction, and it floats up on their screen at the same moment.'),
    (44.9, 'Then pick up right where you left off.'),
    (48.4, 'Guests always join free. Hosts get one free movie night a day.'),
    (54.4, "For more nights, there's MeowWatch Plus."),
    (61.3, 'MeowWatch. Movie night, even miles apart.'),
]


def duration(path: Path) -> float:
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(path)],
                         check=True, capture_output=True, text=True)
    return float(out.stdout)


async def speak(text: str, path: Path) -> None:
    await edge_tts.Communicate(text, VOICE, rate=RATE).save(str(path))


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        clips = []
        for index, (start, text) in enumerate(LINES):
            clip = Path(tmp) / f'line-{index:02d}.mp3'
            asyncio.run(speak(text, clip))
            clips.append((start, clip, duration(clip)))
        intervals = []
        for index, (start, clip, length) in enumerate(clips):
            end = start + length
            limit = LINES[index + 1][0] if index + 1 < len(LINES) else LENGTH
            if end > limit - .15:
                raise SystemExit(f'Line {index} ends at {end:.2f}s, past {limit:.2f}s: {LINES[index][1]}')
            intervals.append([round(start, 3), round(end, 3)])
        inputs = [arg for _, clip, _ in clips for arg in ('-i', str(clip))]
        delays = ''.join(f'[{i}:a]adelay={round(start * 1000)}|{round(start * 1000)}[d{i}];'
                         for i, (start, _, _) in enumerate(clips))
        mixed = ''.join(f'[d{i}]' for i in range(len(clips)))
        graph = f'{delays}{mixed}amix=inputs={len(clips)}:normalize=0,apad,atrim=0:{LENGTH},loudnorm=I=-18:TP=-2[out]'
        output = HERE / 'source-media' / 'voiceover.mp3'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', *inputs, '-filter_complex', graph, '-map', '[out]',
                        '-ar', str(SAMPLE_RATE), '-ac', '1', '-b:a', '128k', str(output)], check=True)
    (HERE / 'src' / 'voiceover.json').write_text(json.dumps(intervals, indent=1) + '\n')
    for (start, end), (_, text) in zip(intervals, LINES):
        print(f'{start:6.2f}-{end:6.2f}  {text}')


if __name__ == '__main__':
    main()
