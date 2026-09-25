import React from 'react';
import {Video} from '@remotion/media';
import {AbsoluteFill, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {Brand} from './Brand';
import {Feature} from './FeatureScene';
import {blue, cream, ink, muted, peach, reveal} from './theme';

const copy: Record<string, {lines: [string, string]; tag: string; light: boolean; phoneLeft: boolean; mark: string}> = {
  purchase: {lines: ['More movie', 'nights.'], tag: 'PLUS UNLOCKED', light: true, phoneLeft: false, mark: 'PLUS'},
  restore: {lines: ['Your Plus', 'comes back.'], tag: 'SAME CUSTOMER RESTORE', light: false, phoneLeft: true, mark: '↶'},
  aurora: {lines: ['Set the', 'scene.'], tag: 'GLASS AURORA', light: true, phoneLeft: false, mark: '◌'},
  reaction: {lines: ['React in', 'the moment.'], tag: 'MOVIE NIGHT REACTION', light: false, phoneLeft: true, mark: '♡'},
  another: {lines: ['And then,', 'another.'], tag: 'SECOND PLUS SESSION', light: true, phoneLeft: false, mark: '02'},
};

export const PremiumScene: React.FC<{feature: Feature}> = ({feature}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const config = copy[feature.id];
  const dark = !config.light;
  const headline = dark ? cream : ink;
  const sub = dark ? muted : '#526A78';
  const entrance = spring({frame: frame - 5, fps, config: {damping: 24, stiffness: 98}});
  const phoneX = config.phoneLeft ? 204 : 1305;
  const textX = config.phoneLeft ? 789 : 112;

  return (
    <AbsoluteFill style={{background: dark ? ink : cream, overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          top: -120,
          right: config.phoneLeft ? -810 : -400,
          width: 1190,
          height: 1190,
          borderRadius: '50%',
          border: `2px solid ${dark ? '#2B5265' : '#B1D0DE'}`,
          opacity: 0.65,
          scale: 0.86 + 0.14 * reveal(frame, 0, 48),
        }}
      />
      <div
        style={{
          position: 'absolute',
          top: 78,
          left: 110,
        }}
      >
        <Brand light={dark} size={34} />
      </div>
      <div style={{position: 'absolute', top: 88, right: 108, fontFamily: 'DM Sans', fontSize: 18, fontWeight: 700, letterSpacing: 3.2, color: dark ? blue : '#39789D'}}>{feature.number} / 12</div>

      <div
        style={{
          position: 'absolute',
          left: textX,
          top: 280,
          width: config.phoneLeft ? 925 : 1020,
          zIndex: 2,
        }}
      >
        <div style={{fontFamily: 'DM Sans', fontSize: 19, color: dark ? blue : '#39789D', letterSpacing: 4.5, fontWeight: 700, opacity: reveal(frame, 2, 15)}}>{config.tag}</div>
        <div style={{fontFamily: 'DM Serif Display', fontSize: feature.id === 'restore' ? 94 : 112, color: headline, lineHeight: 0.98, letterSpacing: -3.5, marginTop: 23}}>
          {config.lines.map((line, index) => (
            <div key={line} style={{opacity: reveal(frame, 8 + index * 8, 21), translate: `0 ${interpolate(reveal(frame, 8 + index * 8, 21), [0, 1], [53, 0])}px`}}>{line}</div>
          ))}
        </div>
        <div style={{height: 4, background: peach, width: 180 * reveal(frame, 29, 25), marginTop: 35}} />
        <div style={{fontFamily: 'DM Sans', fontSize: 28, color: sub, lineHeight: 1.35, maxWidth: 690, marginTop: 24, opacity: reveal(frame, 31, 20)}}>{feature.caption}</div>
      </div>

      <div
        style={{
          position: 'absolute',
          left: phoneX,
          top: 145,
          padding: 8,
          background: '#172735',
          border: '1px solid #68869A',
          borderRadius: 31,
          boxShadow: '0 40px 80px #00000070, 0 9px 0 #101F2B',
          opacity: entrance,
          transform: `perspective(1500px) rotateY(${interpolate(entrance, [0, 1], [config.phoneLeft ? -14 : 14, config.phoneLeft ? -4 : 4])}deg) translateY(${interpolate(entrance, [0, 1], [88, 0])}px) scale(${interpolate(entrance, [0, 1], [0.87, 1])})`,
          transformOrigin: 'center center',
          zIndex: 2,
        }}
      >
        <Video
          src={staticFile(`media/${feature.id}-phone.mp4`)}
          muted
          style={{display: 'block', width: 342, height: 760, objectFit: 'contain', background: '#05080D'}}
        />
      </div>

      <div
        style={{
          position: 'absolute',
          left: config.phoneLeft ? 643 : 1165,
          top: 178,
          fontFamily: 'DM Serif Display',
          fontSize: feature.id === 'purchase' ? 188 : 150,
          lineHeight: 1,
          color: dark ? '#597A8A' : '#80AFC4',
          opacity: 0.17 * reveal(frame, 8, 30),
          rotate: config.phoneLeft ? '-13deg' : '11deg',
          pointerEvents: 'none',
          zIndex: 1,
        }}
      >
        {config.mark}
      </div>
      {feature.id === 'aurora' && (
        <div style={{position: 'absolute', right: 90, top: 200, display: 'flex', gap: 10, opacity: reveal(frame, 18, 22)}}>
          {[peach, blue, '#B9A9D3'].map((color, i) => <div key={color} style={{width: 12, height: 90 + i * 35, background: color, borderRadius: 8}} />)}
        </div>
      )}
      <div style={{position: 'absolute', bottom: 54, left: 111, fontFamily: 'DM Sans', fontSize: 22, color: sub, opacity: reveal(frame, 16, 20)}}>{feature.disclosure}</div>
      <div style={{position: 'absolute', bottom: 0, left: 0, width: `${(frame / (feature.duration * fps)) * 100}%`, height: 4, background: dark ? blue : '#39789D'}} />
    </AbsoluteFill>
  );
};
