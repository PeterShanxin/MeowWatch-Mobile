import React from 'react';
import {AbsoluteFill, Interactive, interpolate, useCurrentFrame} from 'remotion';
import {Brand} from './Brand';
import {blue, cream, ink, muted, peach, reveal} from './theme';

export const FreeCard: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{background: cream, overflow: 'hidden'}}>
      <div style={{position: 'absolute', left: 111, top: 85}}>
        <Brand light={false} size={34} />
      </div>
      <div
        style={{
          position: 'absolute',
          right: 180,
          top: 94,
          fontFamily: 'DM Sans',
          fontSize: 18,
          fontWeight: 700,
          letterSpacing: 4,
          color: '#4C7085',
        }}
      >
        THE WAY IN
      </div>
      <div
        style={{
          position: 'absolute',
          left: 1060,
          top: 196,
          width: 670,
          height: 670,
          border: `2px solid ${blue}`,
          borderRadius: '50%',
          opacity: 0.85,
          scale: interpolate(frame, [0, 55], [0.84, 1], {
            extrapolateRight: 'clamp',
          }),
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 1250,
          top: 376,
          width: 296,
          height: 296,
          borderRadius: '50%',
          background: ink,
          display: 'grid',
          placeItems: 'center',
          boxShadow: '0 38px 70px #162D4933',
          opacity: reveal(frame, 6, 19),
        }}
      >
        <div style={{fontFamily: 'DM Serif Display', fontSize: 210, color: cream, lineHeight: 1}}>
          1
        </div>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 1255,
          top: 326,
          width: 25,
          height: 25,
          borderRadius: '50%',
          background: peach,
          boxShadow: '0 0 0 17px #EFC4A633',
        }}
      />
      <div style={{position: 'absolute', left: 120, top: 274, width: 950}}>
        <Interactive.Div
          name="Free headline"
          style={{
            fontFamily: 'DM Serif Display',
            fontSize: 118,
            lineHeight: 1.0,
            letterSpacing: -3,
            color: ink,
            opacity: reveal(frame, 4, 22),
            translate: `0 ${interpolate(reveal(frame, 4, 22), [0, 1], [45, 0])}px`,
          }}
        >
          The first movie
          <br />
          night is on us.
        </Interactive.Div>
        <div style={{width: 110, height: 5, background: '#2A7094', marginTop: 45}} />
        <Interactive.Div
          name="Free detail"
          style={{
            fontFamily: 'DM Sans',
            fontSize: 34,
            lineHeight: 1.42,
            color: '#3E5462',
            marginTop: 27,
            opacity: reveal(frame, 22, 23),
          }}
        >
          Host one real Together Session per local day.
          <br />
          Joining someone else is always free.
        </Interactive.Div>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 120,
          bottom: 70,
          fontFamily: 'DM Sans',
          fontSize: 18,
          fontWeight: 700,
          letterSpacing: 3,
          color: muted,
        }}
      >
        WATCH TOGETHER
      </div>
    </AbsoluteFill>
  );
};
