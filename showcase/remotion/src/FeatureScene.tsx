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

export type Feature = {
  id: string;
  duration: number;
  kind: 'single' | 'pair';
  number: string;
  eyebrow: string;
  title: string;
  caption: string;
  disclosure: string;
  accent?: 'blue' | 'peach';
};

const Screen: React.FC<{
  id: string;
  device: 'phone' | 'tablet';
  width: number;
  height: number;
  label?: string;
}> = ({id, device, width, height, label}) => (
  <div style={{position: 'relative', width: width + 18, flexShrink: 0}}>
    <div
      style={{
        width,
        height,
        boxSizing: 'content-box',
        padding: 8,
        background: '#172735',
        border: '1px solid #668297',
        borderRadius: device === 'phone' ? 29 : 20,
        boxShadow: '0 32px 60px #0000006B, 0 0 0 1px #FFFFFF12 inset',
      }}
    >
      <Video
        src={staticFile(`media/${id}-${device}.mp4`)}
        muted
        style={{width, height, display: 'block', objectFit: 'contain', background: '#05080D'}}
      />
    </div>
    {label && (
      <div
        style={{
          marginTop: 19,
          fontFamily: 'DM Sans',
          fontSize: 18,
          letterSpacing: 2.5,
          color: muted,
          textTransform: 'uppercase',
        }}
      >
        {label}
      </div>
    )}
  </div>
);

export const FeatureScene: React.FC<{feature: Feature}> = ({feature}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const duration = feature.duration * fps;
  const entrance = spring({frame: frame - 4, fps, config: {damping: 22, stiffness: 85}});
  const accent = feature.accent === 'peach' ? peach : blue;
  const controls = feature.id === 'controls';
  const reverse = ['continue', 'restore', 'reaction'].includes(feature.id);
  const displayWord = controls
    ? frame < 8 * fps
      ? 'PLAY'
      : frame < 16 * fps
        ? 'PAUSE'
        : 'SEEK'
    : null;
  const displayWordFrame = controls
    ? frame < 8 * fps
      ? frame
      : frame < 16 * fps
        ? frame - 8 * fps
        : frame - 16 * fps
    : 0;

  return (
    <AbsoluteFill style={{background: ink, overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background:
            feature.accent === 'peach'
              ? 'radial-gradient(circle at 82% 72%, #503D3890 0%, transparent 36%)'
              : 'radial-gradient(circle at 80% 58%, #153B5399 0%, transparent 40%)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          top: 0,
          bottom: 0,
          left: interpolate(frame, [0, 15], [-380, 1920], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          }),
          width: 380,
          background: `linear-gradient(90deg, transparent, ${accent}37, transparent)`,
          zIndex: 1,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 100,
          top: 76,
          opacity: reveal(frame, 4, 14),
        }}
      >
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
        {feature.number} / 10
      </div>
      <div
        style={{
          position: 'absolute',
          left: feature.kind === 'pair' ? 101 : reverse ? 821 : 101,
          top: feature.kind === 'pair' ? 170 : 275,
          width: feature.kind === 'pair' ? 1220 : 850,
          zIndex: 2,
        }}
      >
        <Interactive.Div
          name={`${feature.id} eyebrow`}
          style={{
            color: accent,
            fontFamily: 'DM Sans',
            fontSize: 18,
            fontWeight: 700,
            letterSpacing: 5.5,
            textTransform: 'uppercase',
            marginBottom: 20,
            opacity: reveal(frame, 5, 17),
          }}
        >
          {feature.eyebrow}
        </Interactive.Div>
        <Interactive.Div
          name={`${feature.id} headline`}
          style={{
            fontFamily: 'DM Serif Display',
            fontSize: feature.kind === 'pair' ? 82 : 100,
            lineHeight: 1.04,
            letterSpacing: -2.5,
            color: cream,
            maxWidth: feature.kind === 'pair' ? 1220 : 850,
            opacity: entrance,
            translate: `0 ${interpolate(entrance, [0, 1], [40, 0])}px`,
          }}
        >
          {feature.title}
        </Interactive.Div>
        {feature.kind === 'single' && (
          <Interactive.Div
            name={`${feature.id} caption`}
            style={{
              fontFamily: 'DM Sans',
              fontSize: 30,
              lineHeight: 1.35,
              color: muted,
              marginTop: 34,
              maxWidth: 720,
              opacity: reveal(frame, 20, 22),
            }}
          >
            {feature.caption}
          </Interactive.Div>
        )}
      </div>

      {feature.kind === 'single' ? (
        <>
          <div
            style={{
              position: 'absolute',
              left: reverse ? 234 : 1315,
              top: 144,
              opacity: entrance,
              translate: `${interpolate(entrance, [0, 1], [reverse ? -82 : 82, 0])}px 0`,
            }}
          >
            <Screen
              id={feature.id}
              device="phone"
              width={342}
              height={760}
              label="Android phone / actual capture"
            />
          </div>
          <div
            style={{
              position: 'absolute',
              left: reverse ? 821 : 102,
              bottom: 151,
              width: 76,
              height: 3,
              background: accent,
            }}
          />
        </>
      ) : (
        <>
          <div
            style={{
              position: 'absolute',
              left: 134,
              top: 316,
              opacity: entrance,
              translate: `${controls ? interpolate(frame, [0, 8 * fps, 16 * fps, 25 * fps], [0, 15, -6, 0], {extrapolateRight: 'clamp'}) : 0}px ${interpolate(entrance, [0, 1], [72, 0])}px`,
              scale: controls
                ? interpolate(frame, [0, 8 * fps, 16 * fps, 25 * fps], [1.035, 1, 0.98, 1], {
                    extrapolateLeft: 'clamp',
                    extrapolateRight: 'clamp',
                  })
                : 1,
              zIndex: 2,
              transformOrigin: 'top left',
            }}
          >
            <Screen
              id={feature.id}
              device="phone"
              width={288}
              height={640}
            />
          </div>
          <div
            style={{
              position: 'absolute',
              left: 728,
              top: 380,
              opacity: entrance,
              translate: `${interpolate(entrance, [0, 1], [90, 0]) + (controls ? interpolate(frame, [0, 8 * fps, 16 * fps, 25 * fps], [0, -22, 15, 0], {extrapolateRight: 'clamp'}) : 0)}px 0`,
              scale: controls
                ? interpolate(frame, [0, 8 * fps, 16 * fps, 25 * fps], [0.98, 1, 1.035, 1], {
                    extrapolateLeft: 'clamp',
                    extrapolateRight: 'clamp',
                  })
                : 1,
              zIndex: 2,
              transformOrigin: 'top left',
            }}
          >
            <Screen
              id={feature.id}
              device="tablet"
              width={895}
              height={560}
            />
          </div>
          <div
            style={{
              position: 'absolute',
              left: 453,
              top: 690,
              width: 255 * reveal(frame, 13, 27),
              height: 2,
              background: `linear-gradient(90deg, ${peach}, ${blue})`,
              opacity: 0.82,
            }}
          />
          <div
            style={{
              position: 'absolute',
              left: 582,
              top: 673,
              width: 36,
              height: 36,
              borderRadius: '50%',
              background: ink,
              border: `2px solid ${accent}`,
              opacity: reveal(frame, 13, 27),
            }}
          />
          <div
            style={{
              position: 'absolute',
              left: 622,
              top: 316,
              color: muted,
              fontFamily: 'DM Sans',
              fontSize: 23,
              width: 700,
              opacity: reveal(frame, 24, 24),
            }}
          >
            {feature.caption}
          </div>
          {controls && (
            <div
              style={{
                position: 'absolute',
                left: 620,
                top: 776,
                fontFamily: 'DM Sans',
                fontWeight: 700,
                fontSize: 19,
                letterSpacing: 4,
                color: blue,
                opacity: reveal(displayWordFrame, 0, 15),
              }}
            >
              {displayWord}
            </div>
          )}
        </>
      )}

      <div
        style={{
          position: 'absolute',
          left: 101,
          bottom: 55,
          color: muted,
          fontFamily: 'DM Sans',
          fontSize: 22,
          letterSpacing: 0.3,
          opacity: interpolate(frame, [0, 12, duration - 10, duration], [0, 1, 1, 0], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          }),
        }}
      >
        Android emulator footage · 1×
        {feature.kind === 'pair' && '   /   Separate recordings · Approximate alignment'}
        {(feature.id === 'purchase' || feature.id === 'restore' || feature.id === 'aurora' || feature.id === 'reaction' || feature.id === 'another') &&
          '   /   RevenueCat Test Store · No charge'}
      </div>
      <div
        style={{
          position: 'absolute',
          left: 0,
          bottom: 0,
          width: `${(frame / duration) * 100}%`,
          height: 4,
          background: accent,
          opacity: 0.65,
        }}
      />
    </AbsoluteFill>
  );
};
