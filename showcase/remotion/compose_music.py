"""Original late-night score for the launch film. Synthesized; no samples.

120 BPM grid (the film changes scene on the beat) played with a half-time
feel: electric piano, warm pad, sub bass, brushed drums and a music box that
answers the opening countdown. Times below are film seconds.
"""
from pathlib import Path
import wave

import numpy as np
from scipy.signal import butter, sosfilt

RATE = 44100
LENGTH = 68
BEAT = .5
BAR = 4 * BEAT
rng = np.random.default_rng(20260927)
mix = np.zeros((RATE * LENGTH, 2))

# Scene boundaries in the 2,025-frame cut.
TITLE, GROOVE, TOGETHER, REACT, CONTINUE, PLUS_TALK, PLUS, ENDING = 5.5, 9.5, 22.5, 37, 44.5, 48, 54, 60.5


def add(sound: np.ndarray, start: float, gain: float = 1., pan: float = 0.) -> None:
    offset = round(start * RATE)
    count = min(len(sound), len(mix) - offset)
    if offset < 0 or count <= 0:
        return
    angle = (pan + 1) * np.pi / 4
    mix[offset:offset + count, 0] += sound[:count] * gain * np.cos(angle)
    mix[offset:offset + count, 1] += sound[:count] * gain * np.sin(angle)


def lowpass(signal: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return sosfilt(butter(order, cutoff, 'low', fs=RATE, output='sos'), signal)


def highpass(signal: np.ndarray, cutoff: float, order: int = 2) -> np.ndarray:
    return sosfilt(butter(order, cutoff, 'high', fs=RATE, output='sos'), signal)


def hz(midi: float) -> float:
    return 440 * 2 ** ((midi - 69) / 12)


def times(duration: float) -> np.ndarray:
    return np.arange(round(duration * RATE)) / RATE


def epiano(midi: float, duration: float) -> np.ndarray:
    """Tine-like FM electric piano with a short bell partial."""
    t, f = times(duration), hz(midi)
    index = 1.1 * np.exp(-t * 3.5) + .12
    body = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * f * t))
    tine = .18 * np.sin(2 * np.pi * f * 14 * t) * np.exp(-t * 30)
    envelope = np.minimum(t / .004, 1) * np.exp(-t * 1.6) * np.minimum((duration - t) / .25, 1)
    tremolo = 1 + .06 * np.sin(2 * np.pi * 4.6 * t)
    return (body + tine) * envelope * tremolo


def pad(midi: float, duration: float) -> np.ndarray:
    t, f = times(duration), hz(midi)
    signal = sum(np.sin(2 * np.pi * f * n * (1 + detune) * t) / n ** 2
                 for n in range(1, 7) for detune in (-.0018, 0, .0021))
    envelope = np.minimum(t / 1.2, 1) * np.minimum((duration - t) / 1.4, 1)
    return lowpass(signal * envelope, 1600)


def music_box(midi: float) -> np.ndarray:
    t, f = times(1.8), hz(midi)
    signal = np.sin(2 * np.pi * f * t) + .35 * np.sin(2 * np.pi * f * 3.98 * t) * np.exp(-t * 6)
    return signal * np.minimum(t / .003, 1) * np.exp(-t * 3)


def sub(midi: float, duration: float) -> np.ndarray:
    t, f = times(duration), hz(midi)
    signal = np.sin(2 * np.pi * f * t) + .15 * np.sin(4 * np.pi * f * t)
    return signal * np.minimum(t / .02, 1) * np.minimum((duration - t) / .2, 1) * np.exp(-t * .6)


def kick() -> np.ndarray:
    t = times(.35)
    sweep = 45 * t + 50 * .04 * (1 - np.exp(-t / .04))
    return np.sin(2 * np.pi * sweep) * np.exp(-t * 9)


def brush() -> np.ndarray:
    t = times(.28)
    noise = lowpass(highpass(rng.normal(0, 1, len(t)), 700), 5200)
    return noise * np.minimum(t / .012, 1) * np.exp(-t * 11)


def shaker() -> np.ndarray:
    t = times(.07)
    return highpass(rng.normal(0, 1, len(t)), 6500) * np.minimum(t / .01, 1) * np.exp(-t * 55)


# Two bars per chord: Dmaj9, F#m7, Gmaj9, Gm6 (the minor iv is the "miles apart").
CHORDS = [
    (38, [54, 57, 61, 64]),
    (42, [52, 57, 61, 64]),
    (43, [54, 57, 59, 62]),
    (43, [52, 55, 58, 62]),
]
# Melody as positions in the current chord (top voice first), so it always fits the harmony.
MOTIF = [(0, 3), (1.5, 2), (2, 1), (4, 2), (5.5, 1), (6, 0)]


def chord_at(second: float) -> tuple[int, list[int]]:
    # The film's last scene lands on the tonic rather than mid-progression.
    if second >= ENDING - BEAT:
        return CHORDS[0]
    return CHORDS[int(second // (2 * BAR)) % len(CHORDS)]


def section_at(second: float) -> str:
    if second < GROOVE:
        return 'intro'
    if CONTINUE <= second < PLUS_TALK:
        return 'soft'
    if PLUS_TALK <= second < PLUS:
        return 'break'
    if second >= ENDING - BEAT:
        return 'end'
    return 'full' if TOGETHER <= second < CONTINUE or second >= PLUS else 'groove'


def energy_at(second: float) -> float:
    if second < TITLE:
        return .0
    if PLUS_TALK <= second < PLUS or second >= ENDING or CONTINUE <= second < PLUS_TALK:
        return .45
    if TOGETHER <= second < CONTINUE:
        return 1.
    return .8


# Opening: a room tone and a music box that counts down with the chat bubbles.
room = lowpass(rng.normal(0, 1, len(mix)), 900) * .006
crackle = np.zeros(len(mix))
crackle[rng.integers(0, len(mix), 260)] = rng.choice([-1, 1], 260) * rng.uniform(.05, .18, 260)
add(room + lowpass(crackle, 3000), 0, 1.)
for second, pitch in [(26 / 30, 81), (38 / 30, 78), (50 / 30, 74), (62 / 30, 69), (62 / 30, 73)]:
    add(music_box(pitch), second, .11, .2)
for second, pitch in [(88 / 30, 69), (98 / 30, 68), (122 / 30, 81)]:
    add(music_box(pitch), second, .07, -.3)
add(pad(62, 3.2), 2.6, .02)

# Lights down: one warm swell and a low hit on the title's downbeat.
add(sub(38, 3.5), TITLE, .16)
for index, pitch in enumerate(CHORDS[0][1] + [69, 73]):
    add(pad(pitch, 4.5), TITLE - .4, .03, (index - 2.5) / 3)

for beat in range(round(TITLE / BEAT), round(LENGTH / BEAT)):
    start = beat * BEAT
    energy = energy_at(start)
    bass, chord = chord_at(start)
    in_bar = beat % 8
    if in_bar == 0:
        for index, pitch in enumerate(chord):
            add(pad(pitch, 4.3), start, .022 * max(energy, .6), (index - 1.5) / 3)
        add(sub(bass, 3.8), start, .11 * max(energy, .5))
    section = section_at(start)
    # Half-time: kick on 1 and the "and" of 2; brush on 3.
    if section in ('groove', 'full'):
        if beat % 4 == 0 or (beat % 4 == 1 and in_bar >= 4):
            add(kick(), start + (BEAT / 2 if beat % 4 == 1 else 0), .2 * energy)
    if section in ('groove', 'full', 'soft') and beat % 4 == 2:
        add(brush(), start, .09 * energy, .1)
    if section == 'full':
        for step in range(4):
            add(shaker(), start + step * BEAT / 4, (.022 if step % 2 else .012) * energy, -.4)
    # Electric piano: soft stabs on the offbeats, voiced across the chord.
    if section in ('groove', 'full', 'soft', 'break') and beat % 2 == 1:
        for index, pitch in enumerate(chord):
            add(epiano(pitch + 12, 1.1), start + index * .012, .07 * max(energy, .5), (index - 1.5) / 4)

# A short melody, answered once per chord, over the paired screens and the Plus return.
for first, last in ((TOGETHER + 2 * BAR - TOGETHER % (2 * BAR), CONTINUE), (PLUS + 2 * BAR - PLUS % (2 * BAR), ENDING - BEAT)):
    phrase = first
    while phrase + 3.5 <= last:
        _, chord = chord_at(phrase)
        for offset, position in MOTIF:
            add(epiano(chord[position] + 12, 1.6), phrase + offset * BEAT, .055, .25)
        phrase += 2 * BAR

# A soft swell back into the Plus section.
add(pad(57, 2.2), PLUS - 2, .035, -.2)
add(pad(62, 2.2), PLUS - 2, .03, .2)
add(brush(), PLUS - BEAT, .07)

# Ending: Dmaj9 rings out over the tonic.
for index, pitch in enumerate([50, 57, 61, 64, 66, 69]):
    add(epiano(pitch + 12, 5.5), ENDING + index * .07, .06, (index - 2.5) / 4)

# Soft room reverb from a few decaying delay taps, then gentle glue.
wet = np.zeros_like(mix)
for delay, gain in [(.043, .32), (.071, .27), (.113, .22), (.167, .17), (.241, .12), (.337, .08)]:
    shift = round(delay * RATE)
    wet[shift:, 0] += mix[:-shift, 1] * gain
    wet[shift:, 1] += mix[:-shift, 0] * gain
mix += lowpass(wet.T, 4200).T * .7
mix = highpass(mix.T, 38).T

fade_in = np.minimum(np.arange(len(mix)) / (RATE * .8), 1)
fade_out = np.minimum((len(mix) - np.arange(len(mix))) / (RATE * 3.5), 1)
mix *= (fade_in * fade_out)[:, None]
mix = np.tanh(mix * 1.4)
mix *= .7 / max(float(np.max(np.abs(mix))), .01)
pcm = (mix * 32767).astype('<i2')
output = Path(__file__).parent / 'public/music/soundtrack.wav'
output.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(output), 'wb') as handle:
    handle.setnchannels(2)
    handle.setsampwidth(2)
    handle.setframerate(RATE)
    handle.writeframes(pcm.tobytes())
print(f'Original score: {LENGTH}s, 120 BPM half-time, stereo, {output}')
