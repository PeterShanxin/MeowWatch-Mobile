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
PAUSE = .38
LENGTH = 70.5
SAMPLE_RATE = 44100

# (film second, line). Each line must end before the next begins. The name is
# written as two words so the voice says "Meow Watch" clearly; "|" splits a line
# into separately spoken parts with a short pause between them.
LINES = [
    (0.6, 'Long-distance movie nights usually start like this.'),
    (8.7, 'Meet our app, | Meow | Watch!'),
    (13.0, 'Start a room, and send the invite. Joining is always free.'),
    (20.4, "If you're watching a video link, the invite brings the movie along."),
    (25.9, 'Two screens, one movie night. Press play on the phone, and the laptop plays too.'),
    (34.8, 'Pause on either side, and you both pause.'),
    (40.6, 'Send a reaction, and it floats up on their screen at the same moment.'),
    (47.9, 'Then pick up right where you left off.'),
    (51.4, 'Guests always join free. Hosts get one free movie night a day.'),
    (57.4, "For more nights, there's Meow Watch Plus."),
    (64.1, 'Meow | Watch. | Movie night, even miles apart.'),
]


def duration(path: Path) -> float:
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(path)],
                         check=True, capture_output=True, text=True)
    return float(out.stdout)


async def speak(text: str, path: Path) -> None:
    await edge_tts.Communicate(text, VOICE, rate=RATE).save(str(path))


def speak_line(text: str, path: Path) -> None:
    parts = [part.strip() for part in text.split('|')]
    if len(parts) == 1:
        asyncio.run(speak(text, path))
        return
    clips = []
    for index, part in enumerate(parts):
        clip = path.with_name(f'{path.stem}-{index}.mp3')
        asyncio.run(speak(part, clip))
        clips.append(clip)
    # Trim each part's own leading/trailing silence, then join with a fixed pause.
    trim = 'silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse'
    inputs = [arg for clip in clips for arg in ('-i', str(clip))]
    chain = ''.join(f'[{i}:a]{trim},apad=pad_dur={PAUSE}[p{i}];' for i in range(len(clips)))
    joined = ''.join(f'[p{i}]' for i in range(len(clips)))
    subprocess.run(['ffmpeg', '-v', 'error', '-y', *inputs, '-filter_complex',
                    f'{chain}{joined}concat=n={len(clips)}:v=0:a=1[out]', '-map', '[out]', str(path)], check=True)


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        clips = []
        for index, (start, text) in enumerate(LINES):
            clip = Path(tmp) / f'line-{index:02d}.mp3'
            speak_line(text, clip)
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
