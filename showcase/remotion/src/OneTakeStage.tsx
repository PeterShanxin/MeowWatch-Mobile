import React from 'react';
import {Video} from '@remotion/media';
import {AbsoluteFill, Easing, Sequence, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {AnimatedPhone, AnimatedTablet, RoomView} from './AppRecreation';
import {Brand} from './Brand';
import {blue, cream, ink, muted, peach, reveal} from './theme';

type Chapter = {
  id: string;
  start: number;
  duration: number;
  label: string;
  title: string[];
  note?: string;
  disclosure: string;
  accent?: string;
  titleSize?: number;
};

const chapters: Chapter[] = [
  {id: 'start', start: 90, duration: 240, label: '01 / START A ROOM', title: ['Make room for', 'movie night.'], note: 'One tap opens a room you can share.', disclosure: 'UI animation · based on the app', titleSize: 84},
  {id: 'join', start: 330, duration: 240, label: '02 / JOIN', title: ['One invitation.', 'The same room.'], disclosure: 'UI animation · based on the app', accent: peach, titleSize: 72},
  {id: 'controls', start: 570, duration: 300, label: '03 / SHARED CONTROLS', title: ['A single touch.', 'Both screens.'], note: 'Play → pause → seek, from either screen.', disclosure: 'UI animation · based on the app', titleSize: 69},
  {id: 'chat', start: 870, duration: 180, label: '04 / CONVERSATION', title: ['The little', 'things matter.'], disclosure: 'UI animation · based on the app', accent: peach, titleSize: 73},
  {id: 'physical-local', start: 1050, duration: 300, label: '05 / LOCAL PLAYER MODE', title: ['The movie', 'plays here.'], note: 'Local playback on a real Android phone.', disclosure: 'OnePlus PLK110 · Android 16 · Real device capture · 1×', accent: peach, titleSize: 92},
  {id: 'physical-fullscreen', start: 1350, duration: 210, label: '06 / FULLSCREEN', title: ['The whole screen.'], disclosure: 'OnePlus PLK110 · Android 16 · Real device capture · 1×', titleSize: 82},
  {id: 'continue', start: 1560, duration: 300, label: '07 / CONTINUE WATCHING', title: ['Your place,', 'remembered.'], note: 'Return to the saved place, paused.', disclosure: 'Android emulator footage · 1×', titleSize: 88},
  {id: 'free', start: 1860, duration: 120, label: '08 / THE FREE SESSION', title: ['ONE.'], note: 'One real free hosted Together Session per local day. Joining and reconnecting keep the same session.', disclosure: 'UI animation · based on the app', accent: peach, titleSize: 210},
  {id: 'purchase', start: 1980, duration: 180, label: '09 / MEOWWATCH PLUS', title: ['More movie', 'nights.'], note: 'A Test Store purchase activates Plus.', disclosure: 'Android emulator · 1× / RevenueCat Test Store · No charge', accent: peach, titleSize: 99},
  {id: 'restore', start: 2160, duration: 120, label: '10 / RESTORE', title: ['Your Plus', 'comes back.'], note: 'Restore for the same Test Store customer.', disclosure: 'Android emulator · 1× / RevenueCat Test Store · No charge', titleSize: 90},
  {id: 'aurora', start: 2280, duration: 120, label: '11 / GLASS AURORA', title: ['Set the', 'scene.'], note: 'Choose Glass Aurora with Plus.', disclosure: 'Android emulator · 1× / RevenueCat Test Store · No charge', accent: peach, titleSize: 106},
  {id: 'reaction', start: 2400, duration: 150, label: '12 / REACTION', title: ['React in', 'the moment.'], note: 'Send a Movie night reaction with Plus.', disclosure: 'Android emulator · 1× / RevenueCat Test Store · No charge', titleSize: 91},
  {id: 'another', start: 2550, duration: 150, label: '13 / ANOTHER SESSION', title: ['And then,', 'another.'], note: 'A second Plus session, in Cinema Noir.', disclosure: 'Android emulator · 1× / RevenueCat Test Store · No charge', accent: peach, titleSize: 98},
];

const cameraFrames = [0, 90, 330, 570, 870, 1050, 1350, 1410, 1530, 1560, 1860, 1980, 2160, 2280, 2400, 2550, 2700, 2819];
const cameraX = [180, 80, -250, -330, -280, 40, 40, -695, -695, 40, -90, 25, -40, 10, -50, 25, 50, 80];
const cameraY = [80, 0, 60, 0, 45, -30, -30, 130, 130, -30, 30, -30, -35, -25, -35, -30, 90, 100];
const cameraScale = [0.71, 1, 0.84, 0.9, 0.86, 1.05, 1.05, 0.89, 0.89, 1.05, 0.88, 1.03, 1.06, 1.04, 1.06, 1.05, 0.72, 0.68];
const drift = Easing.inOut(Easing.cubic);

const cameraValue = (frame: number, values: number[]) =>
  interpolate(frame, cameraFrames, values, {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: drift,
  });

const chapterAt = (frame: number) => chapters.find((chapter) => frame >= chapter.start && frame < chapter.start + chapter.duration);

const phoneAnimation = (frame: number) => {
  if (frame < 330) {
    const local = Math.max(0, frame - 90);
    const view: RoomView = local < 57 ? 'home' : local < 102 ? 'finding' : 'room-empty';
    return <AnimatedPhone view={view} frame={local} taps={[{at: 45, x: 180, y: 348}]} />;
  }
  if (frame < 570) {
    const local = frame - 330;
    return <AnimatedPhone view={local < 143 ? 'room-empty' : 'room-peer'} peer={local >= 143} frame={local} />;
  }
  if (frame < 870) {
    const local = frame - 570;
    const view: RoomView = local < 50 ? 'paused' : local < 118 ? 'playing' : local < 185 ? 'paused' : local < 240 ? 'seek' : 'playing';
    return <AnimatedPhone view={view} peer frame={local} afterSeek={local >= 240} taps={[{at: 34, x: 180, y: 687}, {at: 171, x: 230, y: 623}, {at: 231, x: 180, y: 687}]} />;
  }
  if (frame < 1050) {
    const local = frame - 870;
    return <AnimatedPhone view="chat" peer frame={local} typing={local >= 62 && local < 113} chatSent={local >= 117} taps={[{at: 107, x: 319, y: 742}]} />;
  }
  if (frame < 1860) return null;
  if (frame < 1980) return <AnimatedPhone view="home" frame={frame - 1860} />;
  if (frame >= 2700) return <AnimatedPhone view="home" frame={0} />;
  return null;
};

const tabletAnimation = (frame: number) => {
  if (frame < 330) return <AnimatedTablet view="home" frame={0} />;
  if (frame < 570) {
    const local = frame - 330;
    return <AnimatedTablet view={local < 119 ? 'home' : 'room-peer'} frame={local} joinSheet={local >= 40 && local < 119} taps={[{at: 33, x: 260, y: 394}, {at: 95, x: 480, y: 460}]} />;
  }
  if (frame < 870) {
    const local = frame - 570;
    const view: RoomView = local < 50 ? 'paused' : local < 118 ? 'playing' : local < 185 ? 'paused' : local < 240 ? 'seek' : 'playing';
    return <AnimatedTablet view={view} frame={local} afterSeek={local >= 240} taps={[{at: 103, x: 350, y: 515}]} />;
  }
  const local = Math.min(179, frame - 870);
  return <AnimatedTablet view="chat" frame={local} chatSent={local >= 143} />;
};

const Footage: React.FC<{id: string; start: number; duration: number}> = ({id, start, duration}) => (
  <Sequence from={start} durationInFrames={duration} layout="none">
    <Video src={staticFile(`media/${id}-phone.mp4`)} muted style={{display: 'block', width: '100%', height: '100%', objectFit: 'contain', background: '#05080D'}} />
  </Sequence>
);

const ChapterText: React.FC<{chapter: Chapter; frame: number}> = ({chapter, frame}) => {
  const local = frame - chapter.start;
  const visible = interpolate(local, [0, 16, chapter.duration - 15, chapter.duration], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const accent = chapter.accent ?? blue;
  const fullscreen = chapter.id === 'physical-fullscreen';
  const free = chapter.id === 'free';
  return (
    <div style={{position: 'absolute', left: 104, top: fullscreen ? 115 : chapter.id === 'join' || chapter.id === 'controls' || chapter.id === 'chat' ? 170 : free ? 257 : 260, width: fullscreen ? 1510 : free ? 850 : chapter.id === 'join' ? 550 : chapter.id === 'controls' || chapter.id === 'chat' ? 610 : 900, color: cream, opacity: visible, pointerEvents: 'none', zIndex: 5}}>
      <div style={{display: 'flex', alignItems: 'center', gap: 17, fontFamily: 'DM Sans', fontSize: 21, color: accent, letterSpacing: 4.2, fontWeight: 700}}>
        <span style={{width: 50, height: 2, background: accent}} />{chapter.label}
      </div>
      <div style={{fontFamily: 'DM Serif Display', fontSize: chapter.titleSize ?? 95, lineHeight: 0.98, letterSpacing: -3.8, marginTop: 27}}>
        {chapter.title.map((line, index) => (
          <div key={line} style={{opacity: reveal(local, 5 + index * 8, 20), translate: `0 ${interpolate(reveal(local, 5 + index * 8, 20), [0, 1], [39, 0])}px`}}>{line}</div>
        ))}
      </div>
      {chapter.note && <div style={{fontFamily: 'DM Sans', fontSize: 30, lineHeight: 1.35, color: muted, maxWidth: free ? 725 : chapter.id === 'controls' ? 390 : 690, marginTop: free ? 6 : 33, opacity: reveal(local, 27, 18)}}>{chapter.note}</div>}
    </div>
  );
};

const OpeningType: React.FC<{frame: number}> = ({frame}) => {
  const exit = interpolate(frame, [69, 90], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div style={{position: 'absolute', inset: 0, opacity: exit, pointerEvents: 'none', zIndex: 7}}>
      <div style={{position: 'absolute', left: 101, top: 240, fontFamily: 'DM Sans', color: cream, fontSize: 162, fontWeight: 800, letterSpacing: -8, lineHeight: 1, opacity: reveal(frame, 5, 17), translate: `${interpolate(reveal(frame, 5, 17), [0, 1], [-140, 0])}px 0`}}>MOVIE NIGHT.</div>
      <div style={{position: 'absolute', left: 113, top: 430, fontFamily: 'DM Serif Display', fontSize: 68, color: peach, opacity: reveal(frame, 20, 17), rotate: '-7deg'}}>even</div>
      <div style={{position: 'absolute', left: 100, top: 523, fontFamily: 'DM Serif Display', color: 'transparent', WebkitTextStroke: `2px ${blue}`, fontSize: 137, letterSpacing: -4, opacity: reveal(frame, 27, 19), translate: `${interpolate(reveal(frame, 27, 19), [0, 1], [-130, 0])}px 0`}}>MILES APART.</div>
      <div style={{position: 'absolute', left: 106, top: 748, width: 1650 * reveal(frame, 46, 26), height: 3, background: `linear-gradient(90deg, ${peach}, ${blue})`}} />
      <div style={{position: 'absolute', left: 109, top: 805, fontFamily: 'DM Serif Display', color: cream, fontSize: 68, opacity: reveal(frame, 52, 17)}}>Watch together. Stay close.</div>
    </div>
  );
};

const ClosingType: React.FC<{frame: number}> = ({frame}) => {
  const local = frame - 2700;
  if (local < 0) return null;
  return (
    <div style={{position: 'absolute', inset: 0, zIndex: 8, pointerEvents: 'none'}}>
      <div style={{position: 'absolute', inset: 0, background: ink, opacity: 0.54 * reveal(local, 0, 28)}} />
      <div style={{position: 'absolute', left: 95, right: 95, top: 320, textAlign: 'center', fontFamily: 'DM Sans', color: cream, fontSize: 169, fontWeight: 800, letterSpacing: -9, opacity: reveal(local, 26, 27), translate: `0 ${interpolate(reveal(local, 26, 27), [0, 1], [80, 0])}px`}}>TOGETHER.</div>
      <div style={{position: 'absolute', left: 465, top: 582, width: 990 * reveal(local, 49, 31), height: 3, background: `linear-gradient(90deg, ${peach}, ${blue})`}} />
      <div style={{position: 'absolute', left: 0, right: 0, top: 642, textAlign: 'center', fontFamily: 'DM Serif Display', color: cream, fontSize: 68, opacity: reveal(local, 59, 21)}}>Watch together, wherever you are.</div>
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 112, textAlign: 'center', fontFamily: 'DM Sans', color: muted, fontSize: 25, opacity: reveal(local, 77, 17)}}>An Android counterpart to open-source MeowWatch.</div>
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 63, textAlign: 'center', fontFamily: 'DM Sans', color: blue, fontSize: 18, fontWeight: 700, letterSpacing: 3, opacity: reveal(local, 86, 17)}}>ANDROID · OPEN SOURCE · AGPL-3.0-ONLY</div>
    </div>
  );
};

export const OneTakeStage: React.FC = () => {
  const frame = useCurrentFrame();
  const chapter = chapterAt(frame);
  const camX = cameraValue(frame, cameraX);
  const camY = cameraValue(frame, cameraY);
  const camScale = cameraValue(frame, cameraScale);
  const wide = interpolate(frame, [1350, 1390, 1530, 1560], [0, 1, 1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: drift});
  const phoneWidth = interpolate(wide, [0, 1], [360, 1390]);
  const phoneHeight = interpolate(wide, [0, 1], [800, 637]);
  const phoneTilt = interpolate(wide, [0, 1], [-5, 0]);
  const isCapture = (frame >= 1050 && frame < 1860) || (frame >= 1980 && frame < 2700);
  const phoneBadge = frame < 1050 || (frame >= 1860 && frame < 1980) || frame >= 2700 ? 'UI ANIMATION' : frame < 1560 ? 'PHYSICAL ONEPLUS' : frame < 1860 ? 'ANDROID EMULATOR' : 'REVENUECAT TEST STORE';
  const tabletOpacity = interpolate(frame, [1015, 1080, 2670, 2735], [1, 0, 0, 0.65], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});

  return (
    <AbsoluteFill style={{background: ink, overflow: 'hidden'}}>
      <div style={{position: 'absolute', inset: 0, background: 'radial-gradient(circle at 71% 61%, #123B52 0%, transparent 53%)', opacity: 0.65}} />
      <div style={{position: 'absolute', left: -300, top: 108, width: 1800, height: 3, background: '#244A60', rotate: '-16deg', opacity: 0.6}} />

      <div style={{position: 'absolute', left: 0, top: 0, width: 3000, height: 1280, transform: `translate3d(${camX}px, ${camY}px, 0) scale(${camScale})`, transformOrigin: 'top left', willChange: 'transform', opacity: interpolate(frame, [0, 55, 90], [0.12, 0.22, 1], {extrapolateRight: 'clamp'})}}>
        <svg width="3000" height="1180" style={{position: 'absolute', inset: 0, pointerEvents: 'none'}}>
          <path d="M 1230 150 C 1010 570, 1440 1090, 1850 650 S 2440 320, 2650 780" fill="none" stroke="#3B748F" strokeWidth="3" strokeDasharray="14 22" opacity="0.6" />
          <path d="M 1280 580 C 1430 388, 1695 413, 1980 630" fill="none" stroke={peach} strokeWidth="4" strokeDasharray="840" strokeDashoffset={840 * (1 - reveal(frame, 373, 89))} opacity="0.75" />
          <circle cx="1280" cy="580" r={12 * reveal(frame, 360, 24)} fill={peach} />
          <circle cx="1980" cy="630" r={12 * reveal(frame, 429, 24)} fill={blue} />
        </svg>

        <div style={{position: 'absolute', left: 1500, top: 330, padding: 9, background: '#182935', border: '1px solid #7996A7', borderRadius: 25, boxShadow: '0 42px 90px #00000091', opacity: tabletOpacity, transform: `perspective(1800px) rotateY(${interpolate(frame, [0, 1050], [12, 3], {extrapolateRight: 'clamp'})}deg)`, transformOrigin: 'center center'}}>
          {tabletAnimation(frame)}
          <div style={{position: 'absolute', bottom: -38, left: 4, color: muted, fontFamily: 'DM Sans', fontSize: 20, fontWeight: 700, letterSpacing: 1.6}}>ILLUSTRATED TABLET</div>
        </div>

        <div style={{position: 'absolute', left: 1100, top: 160, padding: 9, width: phoneWidth + 18, height: phoneHeight + 18, boxSizing: 'border-box', background: '#182935', border: '1px solid #7996A7', borderRadius: interpolate(wide, [0, 1], [30, 21]), boxShadow: '0 42px 90px #00000099, 0 0 0 1px #FFFFFF12 inset', transform: `perspective(1800px) rotateY(${phoneTilt}deg) rotateZ(${interpolate(wide, [0, 1], [-1, 0])}deg)`, transformOrigin: 'center center', willChange: 'width, height, transform'}}>
          <div style={{width: phoneWidth, height: phoneHeight, overflow: 'hidden', borderRadius: interpolate(wide, [0, 1], [23, 12]), background: '#05080D', position: 'relative'}}>
            {!isCapture && phoneAnimation(frame)}
            {frame >= 1050 && frame < 1350 && <Footage id="physical-local" start={1050} duration={300} />}
            {frame >= 1350 && frame < 1560 && <Footage id="physical-fullscreen" start={1350} duration={210} />}
            {frame >= 1560 && frame < 1860 && <Footage id="continue" start={1560} duration={300} />}
            {chapters.filter((item) => ['purchase', 'restore', 'aurora', 'reaction', 'another'].includes(item.id)).map((item) => frame >= item.start && frame < item.start + item.duration ? <Footage key={item.id} id={item.id} start={item.start} duration={item.duration} /> : null)}
          </div>
          <div style={{position: 'absolute', bottom: -40, left: 3, whiteSpace: 'nowrap', color: muted, fontFamily: 'DM Sans', fontSize: 20, fontWeight: 700, letterSpacing: 1.5}}>{phoneBadge}</div>
        </div>
      </div>

      <div style={{position: 'absolute', left: 102, top: 70, zIndex: 9}}><Brand size={34} /></div>
      <div style={{position: 'absolute', right: 100, top: 83, zIndex: 9, fontFamily: 'DM Sans', color: blue, fontSize: 19, fontWeight: 700, letterSpacing: 3.3}}>MEOWWATCH / MOBILE</div>
      {chapter && <ChapterText chapter={chapter} frame={frame} />}
      {chapter?.id === 'controls' && <div style={{position: 'absolute', left: 105, top: 589, color: blue, fontFamily: 'DM Sans', fontSize: 80, fontWeight: 800, letterSpacing: -2}}>{frame - 570 < 82 ? 'PLAY' : frame - 570 < 166 ? 'PAUSE' : 'SEEK'}</div>}
      <OpeningType frame={frame} />
      <ClosingType frame={frame} />
      <div style={{position: 'absolute', left: 105, bottom: 58, zIndex: 9, fontFamily: 'DM Sans', fontSize: 24, color: muted, opacity: chapter ? reveal(frame - chapter.start, 11, 19) : 0}}>{chapter?.disclosure}</div>
      <div style={{position: 'absolute', left: 0, bottom: 0, width: `${(frame / 2820) * 100}%`, height: 4, zIndex: 9, background: `linear-gradient(90deg, ${peach}, ${blue})`}} />
    </AbsoluteFill>
  );
};
