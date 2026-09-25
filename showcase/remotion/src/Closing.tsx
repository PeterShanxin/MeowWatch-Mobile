import React from 'react';
import {AbsoluteFill, Interactive, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Brand} from './Brand';
import {blue, cream, ink, muted, peach, reveal} from './theme';

export const Closing: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const title = spring({frame: frame - 7, fps, config: {damping: 22, stiffness: 80}});
  return (
    <AbsoluteFill style={{background: ink, overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          left: 305,
          top: -490,
          width: 1300,
          height: 1300,
          border: '1px solid #416277',
          borderRadius: '50%',
          opacity: 0.5,
          scale: 0.88 + 0.12 * reveal(frame, 0, 65),
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 515,
          top: -290,
          width: 900,
          height: 900,
          border: '1px solid #5D7990',
          borderRadius: '50%',
          opacity: 0.44,
          scale: 0.83 + 0.17 * reveal(frame, 0, 65),
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 556,
          top: 116,
          width: 17,
          height: 17,
          background: peach,
          borderRadius: '50%',
          boxShadow: '0 0 45px #EFC4A6AA',
        }}
      />
      <div
        style={{
          position: 'absolute',
          right: 554,
          top: 266,
          width: 17,
          height: 17,
          background: blue,
          borderRadius: '50%',
          boxShadow: '0 0 45px #8FCBEBAA',
        }}
      />
      <div
        style={{
          position: 'absolute',
          top: 205,
          left: 765,
          opacity: reveal(frame, 8, 20),
        }}
      >
        <Brand size={57} />
      </div>
      <Interactive.Div
        name="Closing statement"
        style={{
          position: 'absolute',
          left: 230,
          right: 230,
          top: 360,
          color: cream,
          fontFamily: 'DM Serif Display',
          fontSize: 120,
          letterSpacing: -3,
          lineHeight: 1.02,
          textAlign: 'center',
          opacity: title,
          translate: `0 ${interpolate(title, [0, 1], [48, 0])}px`,
        }}
      >
        Watch together,
        <br />
        wherever you are.
      </Interactive.Div>
      <div
        style={{
          position: 'absolute',
          left: 720,
          top: 722,
          width: 480 * reveal(frame, 38, 26),
          height: 3,
          background: `linear-gradient(90deg, ${peach}, ${blue})`,
        }}
      />
      <Interactive.Div
        name="Closing descriptor"
        style={{
          position: 'absolute',
          left: 300,
          right: 300,
          bottom: 218,
          color: muted,
          fontFamily: 'DM Sans',
          fontSize: 29,
          textAlign: 'center',
          opacity: reveal(frame, 49, 22),
        }}
      >
        A new Android counterpart to open-source MeowWatch.
      </Interactive.Div>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          bottom: 76,
          color: blue,
          fontFamily: 'DM Sans',
          fontSize: 18,
          fontWeight: 700,
          letterSpacing: 3.5,
          textAlign: 'center',
          opacity: reveal(frame, 67, 20),
        }}
      >
        ANDROID  ·  OPEN SOURCE  ·  AGPL-3.0-ONLY
      </div>
    </AbsoluteFill>
  );
};
