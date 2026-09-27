import React from 'react';
import {Video} from '@remotion/media';
import {AbsoluteFill, Img, Sequence, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {FPS, clamp, ink, night, paper, pop, ramp, sans, serif, soft} from './theme';

export const Paper: React.FC<{children?: React.ReactNode}> = ({children}) => (
  <AbsoluteFill
    style={{
      backgroundColor: paper,
      backgroundImage: 'radial-gradient(rgba(22,24,29,0.11) 1.3px, transparent 1.4px)',
      backgroundSize: '30px 30px',
    }}
  >
    {children}
  </AbsoluteFill>
);

// Phone recordings are 1272 × 2772; the frame keeps that ratio.
const PHONE_RATIO = 1272 / 2772;

/** A stretch of one recording: `at` seconds into the source, shown for `frames`. */
export type Cut = {src: string; at: number; frames: number};

export const PhoneCuts: React.FC<{cuts: Cut[]; height?: number; style?: React.CSSProperties}> = ({
  cuts,
  height = 900,
  style,
}) => {
  let from = 0;
  return (
    <div
      style={{
        height,
        width: height * PHONE_RATIO + 24,
        padding: 12,
        borderRadius: 64,
        background: night,
        boxShadow: '0 50px 90px -30px rgba(22,24,29,0.45)',
        ...style,
      }}
    >
      <div style={{position: 'relative', width: '100%', height: '100%', borderRadius: 52, overflow: 'hidden', background: night}}>
        {cuts.map((cut) => {
          const start = from;
          from += cut.frames;
          return (
            <Sequence key={`${cut.src}-${cut.at}`} from={start} durationInFrames={cut.frames}>
              <Video
                src={staticFile(`media/${cut.src}.mp4`)}
                trimBefore={Math.round(cut.at * FPS)}
                muted
                objectFit="cover"
                style={{position: 'absolute', inset: 0, width: '100%', height: '100%'}}
              />
            </Sequence>
          );
        })}
      </div>
    </div>
  );
};

/** One statement per screen; each word rises out of a soft blur in turn. */
export const Statement: React.FC<{
  lines: string[];
  delay?: number;
  size?: number;
  align?: 'left' | 'center';
  color?: string;
}> = ({lines, delay = 0, size = 96, align = 'left', color = ink}) => {
  const frame = useCurrentFrame();
  let order = 0;
  return (
    <div style={{fontFamily: serif, fontSize: size, lineHeight: 1.08, color, textAlign: align, letterSpacing: -1}}>
      {lines.map((line) => (
        <div key={line} style={{paddingBottom: size * 0.06}}>
          {line.split(' ').map((word, index, words) => {
            const start = delay + order++ * 4;
            const t = ramp(frame, start, start + 20);
            return (
              <span
                key={`${word}-${index}`}
                style={{
                  display: 'inline-block',
                  marginRight: index < words.length - 1 ? '0.25em' : 0,
                  opacity: t,
                  filter: `blur(${(1 - t) * 12}px)`,
                  transform: `translateY(${(1 - t) * 0.35}em)`,
                }}
              >
                {word}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};

export const Kicker: React.FC<{text: string; delay?: number}> = ({text, delay = 0}) => {
  const frame = useCurrentFrame();
  return (
    <div style={{fontFamily: sans, fontSize: 28, fontWeight: 500, color: soft, opacity: ramp(frame, delay, delay + 12), marginTop: 18}}>
      {text}
    </div>
  );
};

/** Says what the footage is; shown whenever a real capture is on screen. */
export const SourceLabel: React.FC<{text: string}> = ({text}) => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        position: 'absolute',
        left: 70,
        bottom: 30,
        fontFamily: sans,
        fontSize: 19,
        fontWeight: 500,
        letterSpacing: 0.3,
        color: soft,
        opacity: ramp(frame, 6, 18),
        display: 'flex',
        alignItems: 'center',
        gap: 10,
      }}
    >
      <span style={{width: 9, height: 9, borderRadius: 9, background: '#D9534F'}} />
      {text}
    </div>
  );
};

/** A caption pill pinned to a moment in real footage. */
export const Pill: React.FC<{text: string; from: number; to: number; x: number; y: number}> = ({text, from, to, x, y}) => {
  const frame = useCurrentFrame();
  if (frame < from || frame > to) return null;
  const scale = pop(frame, from);
  const out = interpolate(frame, [to - 8, to], [1, 0], clamp);
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        transform: `translate(-50%, -50%) scale(${0.85 + scale * 0.15})`,
        opacity: Math.min(scale, out),
        padding: '14px 28px',
        borderRadius: 999,
        background: ink,
        color: paper,
        fontFamily: sans,
        fontSize: 30,
        fontWeight: 600,
        whiteSpace: 'nowrap',
        boxShadow: '0 20px 40px -18px rgba(0,0,0,0.5)',
      }}
    >
      {text}
    </div>
  );
};

export const Mark: React.FC<{size: number}> = ({size}) => (
  <Img src={staticFile('brand/meowwatch.svg')} style={{width: size, height: size, borderRadius: size * 0.23, display: 'block'}} />
);
