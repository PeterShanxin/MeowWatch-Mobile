import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Brand} from './Brand';
import {blue, cream, ink, peach, reveal} from './theme';

const KineticLine: React.FC<{frame: number; from: number; top: number; children: React.ReactNode; serif?: boolean; outline?: boolean}> = ({frame, from, top, children, serif = false, outline = false}) => {
  const inValue = reveal(frame, from, 21);
  return (
    <div style={{position: 'absolute', left: 100, right: 100, top, height: 166, overflow: 'hidden'}}>
      <div
        style={{
          fontFamily: serif ? 'DM Serif Display' : 'DM Sans',
          fontSize: serif ? 139 : 165,
          fontWeight: serif ? 400 : 800,
          letterSpacing: serif ? -4 : -8,
          lineHeight: 1,
          color: outline ? 'transparent' : cream,
          WebkitTextStroke: outline ? `2px ${blue}` : undefined,
          translate: `${interpolate(inValue, [0, 1], [-118, 0])}px ${interpolate(inValue, [0, 1], [160, 0])}px`,
          opacity: inValue,
          whiteSpace: 'nowrap',
        }}
      >
        {children}
      </div>
    </div>
  );
};

export const Opening: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const impact = spring({frame: frame - 5, fps, config: {damping: 24, stiffness: 94}});
  return (
    <AbsoluteFill style={{background: ink, overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          top: -320,
          left: interpolate(frame, [0, 43], [-1250, 1100], {extrapolateRight: 'clamp'}),
          width: 760,
          height: 1700,
          rotate: '27deg',
          background: '#2C7095',
          opacity: 0.65,
        }}
      />
      <div style={{position: 'absolute', top: 80, left: 100, opacity: reveal(frame, 31, 18)}}><Brand size={39} /></div>
      <KineticLine frame={frame} from={6} top={250}>MOVIE NIGHT.</KineticLine>
      <div style={{position: 'absolute', top: 432, left: 110, fontFamily: 'DM Serif Display', fontSize: 70, color: peach, opacity: reveal(frame, 20, 16), rotate: '-8deg'}}>even</div>
      <KineticLine frame={frame} from={25} top={527} serif outline>MILES APART.</KineticLine>
      <div style={{position: 'absolute', left: 106, top: 736, width: 1694, height: 3, background: '#315064', opacity: 0.6}} />
      <div style={{position: 'absolute', left: 106, top: 736, width: 1694 * reveal(frame, 44, 30), height: 3, background: `linear-gradient(90deg, ${peach}, ${blue})`}} />
      <div style={{position: 'absolute', left: 98, top: 722, width: 30, height: 30, borderRadius: 15, background: peach, opacity: reveal(frame, 44, 15)}} />
      <div style={{position: 'absolute', right: 104, top: 722, width: 30, height: 30, borderRadius: 15, background: blue, opacity: reveal(frame, 65, 13)}} />
      <div
        style={{
          position: 'absolute',
          left: 110,
          top: 786,
          color: cream,
          fontFamily: 'DM Serif Display',
          fontSize: 80,
          letterSpacing: -1.7,
          opacity: reveal(frame, 52, 22),
          translate: `0 ${interpolate(impact, [0, 1], [24, 0])}px`,
        }}
      >
        Watch together. Stay close.
      </div>
      <div style={{position: 'absolute', bottom: 55, left: 107, color: blue, fontFamily: 'DM Sans', fontSize: 19, fontWeight: 700, letterSpacing: 3, opacity: reveal(frame, 66, 15)}}>MEOWWATCH MOBILE</div>
    </AbsoluteFill>
  );
};
