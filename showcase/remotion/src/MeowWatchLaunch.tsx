import React from 'react';
import {Audio} from '@remotion/media';
import {AbsoluteFill, Sequence, interpolate, staticFile} from 'remotion';
import {Closing} from './Closing';
import {AnimatedJourney} from './AnimatedJourney';
import {Feature, FeatureScene} from './FeatureScene';
import {FreeCard} from './FreeCard';
import {Opening} from './Opening';
import {PhysicalFullscreen} from './PhysicalFullscreen';
import {PremiumScene} from './PremiumScene';

const FPS = 30;
const OPENING_FRAMES = 3 * FPS;
const CLOSING_FRAMES = 4 * FPS;

type FilmSection =
  | Feature
  | {kind: 'fullscreen'; id: 'physical-fullscreen'; duration: 7}
  | {kind: 'free'; id: 'free'; duration: 4};

const sections: FilmSection[] = [
  {
    id: 'start',
    duration: 8,
    kind: 'single',
    number: '01',
    eyebrow: 'Start together',
    title: 'Make room for movie night.',
    caption: 'Start a room on your phone. Invite someone in.',
    disclosure: 'UI animation · based on the app',
  },
  {
    id: 'join',
    duration: 8,
    kind: 'pair',
    number: '02',
    eyebrow: 'Join from anywhere',
    title: 'Two people. One room.',
    caption: 'A tablet joins while the host waits on the phone.',
    disclosure: 'UI animation · based on the app',
  },
  {
    id: 'controls',
    duration: 10,
    kind: 'pair',
    number: '03',
    eyebrow: 'Playback in step',
    title: 'Two screens. Shared controls.',
    caption: 'Play, pause and seek from either device.',
    disclosure: 'UI animation · based on the app',
  },
  {
    id: 'chat',
    duration: 6,
    kind: 'pair',
    number: '04',
    eyebrow: 'Conversation',
    title: 'A message. A shared moment.',
    caption: 'Keep the conversation beside the movie.',
    disclosure: 'UI animation · based on the app',
    accent: 'peach',
  },
  {
    id: 'physical-local',
    duration: 10,
    kind: 'single',
    number: '05',
    eyebrow: 'Local Player Mode',
    title: 'The movie plays here.',
    caption: 'Local playback on a real Android phone.',
    disclosure: 'OnePlus PLK110 · Android 16 · Real device capture · 1×',
    sourceType: 'physical',
    accent: 'peach',
  },
  {kind: 'fullscreen', id: 'physical-fullscreen', duration: 7},
  {
    id: 'continue',
    duration: 10,
    kind: 'single',
    number: '07',
    eyebrow: 'Continue watching',
    title: 'Your place, remembered.',
    caption: 'Return to the saved place, paused. Press Play when you are ready.',
    disclosure: 'Android emulator footage · 1×',
  },
  {kind: 'free', id: 'free', duration: 4},
  {
    id: 'purchase',
    duration: 6,
    kind: 'single',
    number: '08',
    eyebrow: 'MeowWatch Plus',
    title: 'More movie nights, with Plus.',
    caption: 'A RevenueCat Test Store purchase activates Plus.',
    disclosure: 'Android emulator · 1×  /  RevenueCat Test Store · No charge',
    accent: 'peach',
  },
  {
    id: 'restore',
    duration: 4,
    kind: 'single',
    number: '09',
    eyebrow: 'Restore',
    title: 'Your Plus comes back.',
    caption: 'Restore in Settings for the same Test Store customer.',
    disclosure: 'Android emulator · 1×  /  RevenueCat Test Store · No charge',
  },
  {
    id: 'aurora',
    duration: 4,
    kind: 'single',
    number: '10',
    eyebrow: 'Make it yours',
    title: 'Your movie night. Your look.',
    caption: 'Choose Glass Aurora with Plus.',
    disclosure: 'Android emulator · 1×  /  RevenueCat Test Store · No charge',
    accent: 'peach',
  },
  {
    id: 'reaction',
    duration: 5,
    kind: 'single',
    number: '11',
    eyebrow: 'React together',
    title: 'For the moments that matter.',
    caption: 'Send a Movie night reaction with Plus.',
    disclosure: 'Android emulator · 1×  /  RevenueCat Test Store · No charge',
  },
  {
    id: 'another',
    duration: 5,
    kind: 'single',
    number: '12',
    eyebrow: 'Keep watching',
    title: 'Another room. Another movie night.',
    caption: 'A second Plus session, in Cinema Noir.',
    disclosure: 'Android emulator · 1×  /  RevenueCat Test Store · No charge',
    accent: 'peach',
  },
];

let cursor = OPENING_FRAMES;
const timeline = sections.map((section) => {
  const from = cursor;
  const durationInFrames = section.duration * FPS;
  cursor += durationInFrames;
  return {section, from, durationInFrames};
});
const closingFrom = cursor;
export const TOTAL_FRAMES = closingFrom + CLOSING_FRAMES;

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
    <Sequence name="Opening" from={0} durationInFrames={OPENING_FRAMES}>
      <Opening />
    </Sequence>
    {timeline.map(({section, from, durationInFrames}) => (
      <Sequence
        key={section.id}
        name={section.kind === 'free' ? 'Free Together Session' : section.kind === 'fullscreen' ? '06 Physical fullscreen' : `${section.number} ${section.id}`}
        from={from}
        durationInFrames={durationInFrames}
      >
        {section.id === 'start' || section.id === 'join' || section.id === 'controls' || section.id === 'chat' ? (
          <AnimatedJourney kind={section.id} />
        ) : section.id === 'purchase' || section.id === 'restore' || section.id === 'aurora' || section.id === 'reaction' || section.id === 'another' ? (
          <PremiumScene feature={section} />
        ) : section.kind === 'free' ? (
          <FreeCard />
        ) : section.kind === 'fullscreen' ? (
          <PhysicalFullscreen />
        ) : (
          <FeatureScene feature={section} />
        )}
      </Sequence>
    ))}
    <Sequence name="Closing" from={closingFrom} durationInFrames={CLOSING_FRAMES}>
      <Closing />
    </Sequence>
  </AbsoluteFill>
);
