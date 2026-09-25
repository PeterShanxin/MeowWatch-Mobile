import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Brand} from './Brand';
import {blue, cream, ink, muted, peach, reveal} from './theme';

export const Closing: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const lockup = spring({frame: frame - 47, fps, config: {damping: 24, stiffness: 85}});
  const route = reveal(frame, 11, 55);

  return (
    <AbsoluteFill style={{background: ink, overflow: 'hidden'}}>
      <div style={{position: 'absolute', inset: 0, background: cream, translate: `${interpolate(frame, [0, 18], [0, 1990], {extrapolateRight: 'clamp'})}px 0`, zIndex: 12}} />
      <svg width="1920" height="1080" style={{position: 'absolute', inset: 0}}>
        <path d="M 132 343 C 420 130, 670 110, 960 520" fill="none" stroke={peach} strokeWidth="3" strokeDasharray="1100" strokeDashoffset={1100 * (1 - route)} />
        <path d="M 1788 343 C 1500 130, 1250 110, 960 520" fill="none" stroke={blue} strokeWidth="3" strokeDasharray="1100" strokeDashoffset={1100 * (1 - route)} />
        <circle cx="132" cy="343" r={17 * reveal(frame, 10, 17)} fill={peach} />
        <circle cx="1788" cy="343" r={17 * reveal(frame, 10, 17)} fill={blue} />
        <circle cx="960" cy="520" r={23 * reveal(frame, 54, 18)} fill={cream} />
      </svg>
      <div style={{position: 'absolute', left: 790, top: 127, opacity: reveal(frame, 35, 21), scale: 0.9 + 0.1 * lockup}}><Brand size={58} /></div>
      <div
        style={{
          position: 'absolute',
          left: 101,
          right: 101,
          top: 354,
          textAlign: 'center',
          color: cream,
          fontFamily: 'DM Sans',
          fontSize: 157,
          fontWeight: 800,
          lineHeight: 1,
          letterSpacing: -9,
          opacity: lockup,
          translate: `0 ${interpolate(lockup, [0, 1], [83, 0])}px`,
        }}
      >
        TOGETHER.
      </div>
      <div style={{position: 'absolute', left: 462, top: 621, width: 996, height: 3, background: '#3B5869'}} />
      <div style={{position: 'absolute', left: 462, top: 621, width: 996 * reveal(frame, 62, 26), height: 3, background: `linear-gradient(90deg, ${peach}, ${blue})`}} />
      <div
        style={{
          position: 'absolute',
          top: 679,
          left: 130,
          right: 130,
          textAlign: 'center',
          color: cream,
          fontFamily: 'DM Serif Display',
          fontSize: 64,
          opacity: reveal(frame, 68, 22),
        }}
      >
        Watch together, wherever you are.
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 147, textAlign: 'center', color: muted, fontFamily: 'DM Sans', fontSize: 26, opacity: reveal(frame, 77, 18)}}>A new Android counterpart to open-source MeowWatch.</div>
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 66, textAlign: 'center', color: blue, fontFamily: 'DM Sans', fontSize: 18, fontWeight: 700, letterSpacing: 4, opacity: reveal(frame, 83, 19)}}>ANDROID　 ·　 OPEN SOURCE　 ·　 AGPL-3.0-ONLY</div>
    </AbsoluteFill>
  );
};
