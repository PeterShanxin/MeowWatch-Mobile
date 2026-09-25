"""Original 120 BPM electronic score. No samples or borrowed recording."""
from pathlib import Path
import wave
import numpy as np

RATE = 32000
LENGTH = 94
BEAT = .5
rng = np.random.default_rng(20260925)
mix = np.zeros((RATE * LENGTH, 2), dtype=np.float64)


def add(sound, start, gain=1., pan=0.):
    offset = round(start * RATE)
    count = min(len(sound), len(mix) - offset)
    if offset < 0 or count <= 0:
        return
    angle = (pan + 1) * np.pi / 4
    mix[offset:offset + count, 0] += sound[:count] * gain * np.cos(angle)
    mix[offset:offset + count, 1] += sound[:count] * gain * np.sin(angle)


def note(midi, duration, kind='keys'):
    t = np.arange(round(duration * RATE)) / RATE
    f = 440 * 2 ** ((midi - 69) / 12)
    attack = np.minimum(t / .012, 1)
    release = np.minimum((duration - t) / .13, 1)
    if kind == 'pad':
        signal = (np.sin(2 * np.pi * f * t) + .27 * np.sin(2 * np.pi * f * 1.003 * t)
                  + .15 * np.sin(2 * np.pi * f * 2 * t))
        envelope = np.minimum(t / .25, 1) * np.minimum((duration - t) / .5, 1)
    elif kind == 'bass':
        signal = np.sin(2 * np.pi * f * t) + .2 * np.sin(2 * np.pi * f * 2 * t)
        envelope = attack * release * np.exp(-t * 2.4)
    else:
        signal = np.sin(2 * np.pi * f * t + .7 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 7))
        envelope = attack * release * np.exp(-t * 2.8)
    return signal * envelope


def drums(start, beat, energy):
    if beat % 2 == 0:
        t = np.arange(round(.24 * RATE)) / RATE
        kick = np.sin(2 * np.pi * (48 * t + 70 * .025 * (1 - np.exp(-t / .025))))
        add(kick * np.exp(-t * 22), start, .18 * energy)
    if beat % 4 in (1, 3):
        t = np.arange(round(.13 * RATE)) / RATE
        noise = rng.normal(0, 1, len(t))
        filtered = np.diff(noise, prepend=0) * .25
        add((filtered + .16 * np.sin(2 * np.pi * 185 * t)) * np.exp(-t * 34), start, .065 * energy)
    for half in (0, .5):
        t = np.arange(round(.045 * RATE)) / RATE
        noise = rng.normal(0, 1, len(t))
        hat = np.diff(noise, prepend=0) * np.exp(-t * 100)
        add(hat, start + half * BEAT, (.018 if half else .027) * energy, -.35 if half else .35)


# Two bars per harmony; Dmaj7, Bm7, Gmaj7 and Aadd9.
chords = [(50, [62, 66, 69, 73]), (47, [59, 62, 66, 69]),
          (43, [55, 59, 62, 66]), (45, [57, 61, 64, 71])]
for beat in range(round(LENGTH / BEAT)):
    start = beat * BEAT
    bass, chord = chords[(beat // 8) % len(chords)]
    energy = .45 if start < 4 else (.7 if 51 <= start < 65 else 1.)
    if start >= 89:
        energy = .5
    if beat % 8 == 0:
        for index, pitch in enumerate(chord):
            add(note(pitch, 4.4, 'pad'), start, .029 * energy, (index - 1.5) / 3)
    if start >= 4:
        drums(start, beat, energy)
        if beat % 2 == 0:
            add(note(bass - 12, .75, 'bass'), start, .14 * energy)
    if beat % 2 == 0 or 20 <= start < 45:
        pitch = chord[[0, 2, 1, 3][beat % 4]] + 12
        sound = note(pitch, 1.5)
        add(sound, start, .061 * energy, -.22)
        add(sound, start + .375, .016 * energy, .45)
        add(sound, start + .75, .006 * energy, -.45)

fade_in = np.minimum(np.arange(len(mix)) / (RATE * 1.1), 1)
fade_out = np.minimum((len(mix) - np.arange(len(mix))) / (RATE * 3.2), 1)
mix *= (fade_in * fade_out)[:, None]
mix = np.tanh(mix * 1.8)
mix *= .63 / max(float(np.max(np.abs(mix))), .01)
pcm = (mix * 32767).astype('<i2')
output = Path(__file__).parent / 'public/music/soundtrack.wav'
output.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(output), 'wb') as handle:
    handle.setnchannels(2)
    handle.setsampwidth(2)
    handle.setframerate(RATE)
    handle.writeframes(pcm.tobytes())
print(f'Original score: {LENGTH}s, 120 BPM, stereo, {output}')
