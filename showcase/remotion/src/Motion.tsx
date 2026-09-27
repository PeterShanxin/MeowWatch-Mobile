import React from 'react';
import {interpolate, useCurrentFrame} from 'remotion';
import {FPS, clamp, sans} from './theme';

// The score is 120 BPM in 4/4: one beat every 15 frames, one bar every 60.
export const BEAT = FPS / 2;
const BAR = BEAT * 4;

const HUD_COLOR = 'rgba(134,128,118,0.6)';
const hudText: React.CSSProperties = {
  position: 'absolute',
  fontFamily: sans,
  fontSize: 14,
  fontWeight: 700,
  letterSpacing: 3,
  color: HUD_COLOR,
  display: 'flex',
  alignItems: 'center',
  gap: 12,
  fontVariantNumeric: 'tabular-nums',
};

const Corner: React.FC<{x: 'left' | 'right'; y: 'top' | 'bottom'}> = ({x, y}) => (
  <div
    style={{
      position: 'absolute',
      [x]: 30,
      [y]: 30,
      width: 24,
      height: 24,
      [`border${y === 'top' ? 'Top' : 'Bottom'}`]: `2px solid ${HUD_COLOR}`,
      [`border${x === 'left' ? 'Left' : 'Right'}`]: `2px solid ${HUD_COLOR}`,
    }}
  />
);

const pad = (value: number) => String(value).padStart(2, '0');

/** Viewfinder frame: corner marks, bar counter locked to the score, and timecode. */
export const Hud: React.FC<{totalFrames: number}> = ({totalFrames}) => {
  const frame = useCurrentFrame();
  const beatPhase = (frame % BEAT) / BEAT;
  const pulse = interpolate(beatPhase, [0, 0.35, 1], [1, 0.25, 0.25], clamp);
  const seconds = Math.floor(frame / FPS);
  const timecode = `00:${pad(Math.floor(seconds / 60))}:${pad(seconds % 60)}:${pad(frame % FPS)}`;
  const bar = Math.floor(frame / BAR) + 1;
  const bars = Math.ceil(totalFrames / BAR);
  const beat = (Math.floor(frame / BEAT) % 4) + 1;
  return (
    <>
      <Corner x="left" y="top" />
      <Corner x="right" y="top" />
      <Corner x="left" y="bottom" />
      <Corner x="right" y="bottom" />
      <div style={{...hudText, left: 70, top: 34}}>MEOWWATCH · LAUNCH FILM 2026</div>
      <div style={{...hudText, right: 70, top: 34}}>
        <span style={{width: 8, height: 8, borderRadius: 8, background: '#D9534F', opacity: pulse}} />
        BAR {pad(bar)}/{pad(bars)} · BEAT {beat}/4 · 120 BPM
      </div>
      <div style={{...hudText, right: 70, bottom: 34}}>{timecode}</div>
    </>
  );
};
