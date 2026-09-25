import React from 'react';
import {Audio} from '@remotion/media';
import {AbsoluteFill, Sequence, interpolate, staticFile} from 'remotion';
import {Closing} from './Closing';
import {Feature, FeatureScene} from './FeatureScene';
import {FreeCard} from './FreeCard';
import {Opening} from './Opening';

const features: Feature[] = [
  {
    id: 'start',
    duration: 8,
    kind: 'single',
    number: '01',
    eyebrow: 'Start together',
    title: 'Make room for movie night.',
    caption: 'Start a room on your phone. Invite someone in.',
    disclosure: 'Android emulator footage · 1×',
  },
  {
    id: 'join',
    duration: 8,
    kind: 'pair',
    number: '02',
    eyebrow: 'Join from anywhere',
    title: 'Two people. One room.',
    caption: 'A tablet joins while the host waits on the phone.',
    disclosure: 'Separate recordings · Approximate alignment',
  },
  {
    id: 'controls',
    duration: 25,
    kind: 'pair',
    number: '03',
    eyebrow: 'Playback in step',
    title: 'Two screens. Shared controls.',
    caption: 'Play, pause and seek from either device.',
    disclosure: 'Separate recordings · Approximate alignment',
  },
  {
    id: 'chat',
    duration: 6,
    kind: 'pair',
    number: '04',
    eyebrow: 'Conversation',
    title: 'A message. A shared moment.',
    caption: 'Keep the conversation beside the movie.',
    disclosure: 'Separate recordings · Approximate alignment',
    accent: 'peach',
  },
  {
    id: 'continue',
    duration: 10,
    kind: 'single',
    number: '05',
    eyebrow: 'Continue watching',
    title: 'Your place, remembered.',
    caption: 'Return to the saved place, paused. Press Play when you are ready.',
    disclosure: 'Android emulator footage · 1×',
  },
  {
    id: 'purchase',
    duration: 6,
    kind: 'single',
    number: '06',
    eyebrow: 'MeowWatch Plus',
    title: 'More movie nights, with Plus.',
    caption: 'A RevenueCat Test Store purchase activates Plus.',
    disclosure: 'RevenueCat Test Store · No charge',
    accent: 'peach',
  },
  {
    id: 'restore',
    duration: 4,
    kind: 'single',
    number: '07',
    eyebrow: 'Restore',
    title: 'Your Plus comes back.',
    caption: 'Restore in Settings for the same Test Store customer.',
    disclosure: 'RevenueCat Test Store · No charge',
  },
  {
    id: 'aurora',
    duration: 4,
    kind: 'single',
    number: '08',
    eyebrow: 'Make it yours',
    title: 'Your movie night. Your look.',
    caption: 'Choose Glass Aurora with Plus.',
    disclosure: 'RevenueCat Test Store · No charge',
    accent: 'peach',
  },
  {
    id: 'reaction',
    duration: 5,
    kind: 'single',
    number: '09',
    eyebrow: 'React together',
    title: 'For the moments that matter.',
    caption: 'Send a Movie night reaction with Plus.',
    disclosure: 'RevenueCat Test Store · No charge',
  },
  {
    id: 'another',
    duration: 5,
    kind: 'single',
    number: '10',
    eyebrow: 'Keep watching',
    title: 'Another room. Another movie night.',
    caption: 'A second Plus session, in Cinema Noir.',
    disclosure: 'RevenueCat Test Store · No charge',
    accent: 'peach',
  },
];

export const MeowWatchLaunch: React.FC = () => {
  let start = 4 * 30;
  const sequences = features.map((feature) => {
    if (feature.id === 'purchase') {
      start += 4 * 30;
    }
    const from = start;
    start += feature.duration * 30;
    return (
      <Sequence
        key={feature.id}
        name={`${feature.number} ${feature.id}`}
        from={from}
        durationInFrames={feature.duration * 30}
      >
        <FeatureScene feature={feature} />
      </Sequence>
    );
  });

  return (
    <AbsoluteFill style={{backgroundColor: '#071522'}}>
      <Audio
        src={staticFile('music/soundtrack.wav')}
        volume={(frame) =>
          interpolate(frame, [0, 24, 2715, 2820], [0, 0.58, 0.58, 0], {
            extrapolateLeft: 'clamp',
            extrapolateRight: 'clamp',
          })
        }
      />
      <Sequence name="Opening" from={0} durationInFrames={4 * 30}>
        <Opening />
      </Sequence>
      {sequences}
      <Sequence name="Free Together Session" from={61 * 30} durationInFrames={4 * 30}>
        <FreeCard />
      </Sequence>
      <Sequence name="Closing" from={89 * 30} durationInFrames={5 * 30}>
        <Closing />
      </Sequence>
    </AbsoluteFill>
  );
};
