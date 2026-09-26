import React from 'react';
import {Audio} from '@remotion/media';
import {AbsoluteFill, Sequence, interpolate, staticFile} from 'remotion';
import {SCENES, TOTAL_FRAMES} from './Scenes';
import {clamp, paper} from './theme';

export {TOTAL_FRAMES};

export const MeowWatchLaunch: React.FC = () => {
  let from = 0;
  return (
    <AbsoluteFill style={{backgroundColor: paper}}>
      <Audio
        src={staticFile('music/soundtrack.wav')}
        volume={(frame) => interpolate(frame, [0, 20, TOTAL_FRAMES - 90, TOTAL_FRAMES], [0, 0.6, 0.6, 0], clamp)}
      />
      {SCENES.map(([Scene, frames]) => {
        const start = from;
        from += frames;
        return (
          <Sequence key={start} from={start} durationInFrames={frames}>
            <Scene />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
