import React from 'react';
import {
  AbsoluteFill,
  Img,
  Interactive,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {Brand} from './Brand';
import {blue, cream, ink, muted, peach, reveal} from './theme';

export const Opening: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const title = spring({frame: frame - 8, fps, config: {damping: 22, stiffness: 85}});
  const line = reveal(frame, 15, 30);
  return (
    <AbsoluteFill style={{background: ink, overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          width: 930,
          height: 930,
          border: '1px solid #2E5265',
          borderRadius: '50%',
          right: -105,
          top: 82,
          scale: 0.91 + 0.09 * line,
          opacity: 0.55,
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: 680,
          height: 680,
          border: '1px solid #385368',
          borderRadius: '50%',
          right: 20,
          top: 205,
          scale: 0.85 + 0.15 * line,
          opacity: 0.7,
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: 24,
          height: 24,
          borderRadius: '50%',
          right: 330,
          top: 195,
          background: peach,
          boxShadow: '0 0 56px #EFC4A677',
          opacity: line,
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: 17,
          height: 17,
          borderRadius: '50%',
          right: 108,
          bottom: 253,
          background: blue,
          boxShadow: '0 0 50px #8FCBEB88',
          opacity: line,
        }}
      />
      <div
        style={{
          position: 'absolute',
          right: 117,
          bottom: 264,
          width: 475 * line,
          height: 2,
          background: `linear-gradient(90deg, ${peach}, ${blue})`,
          rotate: '-35deg',
          transformOrigin: 'right center',
          opacity: 0.7,
        }}
      />
      <div style={{position: 'absolute', left: 122, top: 98}}>
        <Brand size={42} />
      </div>
      <div style={{
        position: 'absolute', right: 170, top: 365,
        width: 360, height: 360, borderRadius: 54, overflow: 'hidden',
        opacity: reveal(frame, 18, 20),
        scale: interpolate(spring({frame: frame - 18, fps, config: {damping: 20}}), [0, 1], [.72, 1]),
        rotate: `${interpolate(frame, [18, 105], [-7, 2], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'})}deg`,
      }}>
        <Img src={staticFile('brand/meowwatch.svg')} style={{width: 360, height: 360}} />
      </div>
      <div style={{position: 'absolute', left: 122, top: 278, width: 1120}}>
        <Interactive.Div
          name="Opening headline"
          style={{
            fontFamily: 'DM Serif Display',
            fontSize: 122,
            lineHeight: 0.98,
            letterSpacing: -3.5,
            color: cream,
            opacity: title,
            translate: `0 ${interpolate(title, [0, 1], [58, 0])}px`,
          }}
        >
          Movie night,
          <br />
          even miles apart.
        </Interactive.Div>
        <div
          style={{
            height: 4,
            width: 238 * reveal(frame, 26, 23),
            background: peach,
            marginTop: 54,
          }}
        />
        <Interactive.Div
          name="Opening subtitle"
          style={{
            fontFamily: 'DM Sans',
            fontSize: 31,
            color: muted,
            letterSpacing: 0.2,
            marginTop: 24,
            opacity: reveal(frame, 31, 21),
          }}
        >
          Watch together. Stay close.
        </Interactive.Div>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 122,
          bottom: 75,
          color: blue,
          fontFamily: 'DM Sans',
          fontSize: 18,
          fontWeight: 700,
          letterSpacing: 4,
          opacity: reveal(frame, 45, 22),
        }}
      >
        MEOWWATCH MOBILE · SHIPATON 2026
      </div>
    </AbsoluteFill>
  );
};
