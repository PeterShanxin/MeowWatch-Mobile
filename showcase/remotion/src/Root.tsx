import React from 'react';
import {Composition} from 'remotion';
import {MeowWatchLaunch, TOTAL_FRAMES} from './MeowWatchLaunch';

export const Root: React.FC = () => (
  <Composition
    id="MeowWatchLaunch"
    component={MeowWatchLaunch}
    durationInFrames={TOTAL_FRAMES}
    fps={30}
    width={1920}
    height={1080}
  />
);
