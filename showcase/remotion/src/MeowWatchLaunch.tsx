import React from 'react';
import {Audio} from '@remotion/media';
import {AbsoluteFill, interpolate, staticFile} from 'remotion';
import {OneTakeStage} from './OneTakeStage';

export const TOTAL_FRAMES = 94 * 30;

export const MeowWatchLaunch: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: '#071522'}}>
    <Audio
      src={staticFile('music/soundtrack.wav')}
      volume={(frame) =>
        interpolate(frame, [0, 24, TOTAL_FRAMES - 105, TOTAL_FRAMES], [0, 0.58, 0.58, 0], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        })
      }
    />
    <OneTakeStage />
  </AbsoluteFill>
);
