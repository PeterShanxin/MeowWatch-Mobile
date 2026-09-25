import React from 'react';
import {Video} from '@remotion/media';
import {
  AbsoluteFill,
  Interactive,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {Brand} from './Brand';
import {blue, cream, ink, muted, peach, reveal} from './theme';

export const PhysicalFullscreen: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const entrance = spring({frame: frame - 4, fps, config: {damping: 24, stiffness: 95}});

  return (
    <AbsoluteFill style={{background: ink, overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          width: 1220,
          height: 1220,
          left: 350,
          top: 220,
          border: '1px solid #2D5870',
          borderRadius: '50%',
          opacity: 0.5,
          scale: 0.91 + 0.09 * reveal(frame, 0, 50),
        }}
      />
      <div style={{position: 'absolute', left: 100, top: 76}}>
        <Brand size={31} />
      </div>
      <div
        style={{
          position: 'absolute',
          right: 100,
          top: 86,
          fontFamily: 'DM Sans',
          fontSize: 18,
          color: muted,
          letterSpacing: 3.4,
          fontWeight: 700,
        }}
      >
        06 / 12
      </div>
      <Interactive.Div
        name="Fullscreen eyebrow"
        style={{
          position: 'absolute',
          left: 101,
          top: 168,
          color: peach,
          fontFamily: 'DM Sans',
          fontSize: 18,
          fontWeight: 700,
          letterSpacing: 5.5,
          textTransform: 'uppercase',
          opacity: reveal(frame, 5, 16),
        }}
      >
        Fullscreen on the phone
      </Interactive.Div>
      <Interactive.Div
        name="Fullscreen headline"
        style={{
          position: 'absolute',
          left: 101,
          top: 200,
          color: cream,
          fontFamily: 'DM Serif Display',
          fontSize: 78,
          lineHeight: 1,
          letterSpacing: -2,
          opacity: entrance,
          translate: `0 ${interpolate(entrance, [0, 1], [33, 0])}px`,
        }}
      >
        Give the movie the whole screen.
      </Interactive.Div>
      <Interactive.Div
        name="Fullscreen caption"
        style={{
          position: 'absolute',
          right: 105,
          top: 282,
          color: muted,
          fontFamily: 'DM Sans',
          fontSize: 25,
          textAlign: 'right',
          opacity: reveal(frame, 19, 19),
        }}
      >
        Native fullscreen playback on a real Android phone.
      </Interactive.Div>
      <div
        style={{
          position: 'absolute',
          left: 255,
          top: 329,
          width: 1390,
          height: 637,
          padding: 10,
          border: '1px solid #698CA1',
          borderRadius: 22,
          background: '#0B1520',
          boxShadow: '0 28px 74px #00000080, 0 0 90px #8FCBEB13',
          opacity: entrance,
          scale: 0.95 + 0.05 * entrance,
          transformOrigin: 'center center',
        }}
      >
        <Video
          src={staticFile('media/physical-fullscreen-phone.mp4')}
          muted
          style={{width: 1390, height: 637, objectFit: 'contain', display: 'block'}}
        />
      </div>
      <div
        style={{
          position: 'absolute',
          left: 100,
          bottom: 55,
          color: muted,
          fontFamily: 'DM Sans',
          fontSize: 22,
          opacity: reveal(frame, 14, 18),
        }}
      >
        OnePlus PLK110 · Android 16 · Real device capture · 1×
      </div>
      <div
        style={{
          position: 'absolute',
          bottom: 0,
          left: 0,
          width: `${(frame / (7 * fps)) * 100}%`,
          height: 4,
          background: blue,
          opacity: 0.65,
        }}
      />
    </AbsoluteFill>
  );
};
