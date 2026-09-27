import React from 'react';
import {Audio} from '@remotion/media';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import type {TransitionPresentation, TransitionPresentationComponentProps} from '@remotion/transitions';
import {AbsoluteFill, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {Hud} from './Motion';
import {SCENES} from './Scenes';
import {FPS, clamp, ease, paper} from './theme';
import voiceover from './voiceover.json';

// One beat at 120 BPM: every scene change overlaps by exactly one beat, so the
// cuts stay on the score's grid.
const TRANSITION = 15;

export const TOTAL_FRAMES = SCENES.reduce((sum, [, frames]) => sum + frames, 0) - TRANSITION * (SCENES.length - 1);

/** The outgoing scene drifts up and softens while the next one rises into place. */
const Drift: React.FC<TransitionPresentationComponentProps<Record<string, never>>> = ({
  children,
  presentationDirection,
  presentationProgress,
}) => {
  const entering = presentationDirection === 'entering';
  const t = entering ? 1 - presentationProgress : presentationProgress;
  return (
    <AbsoluteFill
      style={{
        opacity: 1 - t,
        filter: `blur(${t * 14}px)`,
        transform: `translateY(${(entering ? 1 : -1) * t * 140}px) scale(${1 - t * 0.04})`,
      }}
    >
      {children}
    </AbsoluteFill>
  );
};

const drift: TransitionPresentation<Record<string, never>> = {component: Drift, props: {}};

/** The score dips under each spoken line of the narration. */
const duck = (frame: number) => {
  const t = frame / FPS;
  const speaking = Math.max(...voiceover.map(([start, end]) => interpolate(t, [start - 0.3, start, end, end + 0.5], [0, 1, 1, 0], clamp)));
  return 1 - 0.55 * speaking;
};

/** A slow push-in so no shot is ever completely still. */
const PushIn: React.FC<{frames: number; children: React.ReactNode}> = ({frames, children}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{transform: `scale(${interpolate(frame, [0, frames], [1, 1.045], clamp)})`}}>{children}</AbsoluteFill>
  );
};

export const MeowWatchLaunch: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: paper}}>
    <Audio
      src={staticFile('music/soundtrack.wav')}
      volume={(frame) => interpolate(frame, [0, 20, TOTAL_FRAMES - 90, TOTAL_FRAMES], [0, 1, 1, 0], clamp) * duck(frame)}
    />
    <Audio src={staticFile('music/voiceover.mp3')} />
    <TransitionSeries>
      {SCENES.map(([Scene, frames], index) => (
        <React.Fragment key={index}>
          {index > 0 ? (
            <TransitionSeries.Transition presentation={drift} timing={linearTiming({durationInFrames: TRANSITION, easing: ease})} />
          ) : null}
          <TransitionSeries.Sequence durationInFrames={frames}>
            <PushIn frames={frames}>
              <Scene />
            </PushIn>
          </TransitionSeries.Sequence>
        </React.Fragment>
      ))}
    </TransitionSeries>
    <Hud totalFrames={TOTAL_FRAMES} />
  </AbsoluteFill>
);
