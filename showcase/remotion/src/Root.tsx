import React from 'react';
import {Composition} from 'remotion';
import {MeowWatchLaunch} from './MeowWatchLaunch';

export const Root: React.FC = () => (
  <Composition
    id="MeowWatchLaunch"
    component={MeowWatchLaunch}
    durationInFrames={2820}
    fps={30}
    width={1920}
    height={1080}
  />
);
