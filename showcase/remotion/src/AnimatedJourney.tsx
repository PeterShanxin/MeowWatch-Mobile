import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {AnimatedPhone, AnimatedTablet, RoomView} from './AppRecreation';
import {Brand} from './Brand';
import {blue, cream, ink, muted, peach, reveal} from './theme';

type JourneyKind = 'start' | 'join' | 'controls' | 'chat';

const Device: React.FC<{
  left: number;
  top: number;
  frame: number;
  fps: number;
  tiltFrom: number;
  tiltTo: number;
  scaleFrom?: number;
  scaleTo?: number;
  delay?: number;
  children: React.ReactNode;
}> = ({left, top, frame, fps, tiltFrom, tiltTo, scaleFrom = 0.88, scaleTo = 1, delay = 0, children}) => {
  const settled = spring({frame: frame - delay, fps, config: {damping: 25, stiffness: 95}});
  return (
    <div
      style={{
        position: 'absolute',
        left,
        top,
        padding: 8,
        background: '#192A38',
        border: '1px solid #8DABB9',
        borderRadius: 32,
        boxShadow: '0 37px 78px #00000080, 0 8px 0 #0C1721',
        transform: `perspective(1800px) rotateY(${interpolate(settled, [0, 1], [tiltFrom, tiltTo])}deg) rotateX(${interpolate(settled, [0, 1], [5, 0])}deg) translateY(${interpolate(settled, [0, 1], [90, 0])}px) scale(${interpolate(settled, [0, 1], [scaleFrom, scaleTo])})`,
        transformOrigin: 'center center',
        opacity: settled,
        willChange: 'transform',
      }}
    >
      {children}
    </div>
  );
};

const Connection: React.FC<{
  frame: number;
  from: [number, number];
  to: [number, number];
  start: number;
  color: string;
  height?: number;
}> = ({frame, from, to, start, color, height = -170}) => {
  const progress = reveal(frame, start, 34);
  return (
    <svg width="1920" height="1080" style={{position: 'absolute', inset: 0, overflow: 'visible', pointerEvents: 'none'}}>
      <path
        d={`M ${from[0]} ${from[1]} C ${from[0] + 240} ${from[1] + height}, ${to[0] - 260} ${to[1] + height}, ${to[0]} ${to[1]}`}
        fill="none"
        stroke={color}
        strokeWidth="3"
        strokeLinecap="round"
        strokeDasharray="1300"
        strokeDashoffset={1300 * (1 - progress)}
        opacity="0.8"
      />
      <circle cx={from[0]} cy={from[1]} r={11 * progress} fill={color} />
      <circle cx={to[0]} cy={to[1]} r={9 * reveal(frame, start + 24, 17)} fill={color} />
    </svg>
  );
};

const SceneType: React.FC<{
  frame: number;
  number: string;
  label: string;
  lines: string[];
  dark?: boolean;
  left?: number;
  top?: number;
  size?: number;
}> = ({frame, number, label, lines, dark = true, left = 112, top = 192, size = 100}) => (
  <div style={{position: 'absolute', left, top, color: dark ? cream : ink, zIndex: 3, pointerEvents: 'none'}}>
    <div style={{display: 'flex', alignItems: 'center', gap: 15, color: dark ? blue : '#39789D', fontFamily: 'DM Sans', fontSize: 19, fontWeight: 700, letterSpacing: 4.2, opacity: reveal(frame, 3, 14)}}>
      <span>{number}</span><span style={{width: 57, height: 2, background: dark ? blue : '#39789D'}} /><span>{label}</span>
    </div>
    <div style={{marginTop: 24, fontFamily: 'DM Serif Display', fontSize: size, lineHeight: 0.97, letterSpacing: -3.5}}>
      {lines.map((line, index) => (
        <div
          key={line}
          style={{
            opacity: reveal(frame, 6 + index * 7, 19),
            translate: `0 ${interpolate(reveal(frame, 6 + index * 7, 19), [0, 1], [58, 0])}px`,
          }}
        >
          {line}
        </div>
      ))}
    </div>
  </div>
);

const Footer: React.FC<{frame: number; dark: boolean; wording?: string}> = ({frame, dark, wording = 'UI animation · based on the app'}) => (
  <div
    style={{
      position: 'absolute',
      left: 110,
      bottom: 54,
      fontFamily: 'DM Sans',
      fontSize: 22,
      color: dark ? muted : '#4B6979',
      opacity: reveal(frame, 18, 18),
      zIndex: 6,
    }}
  >
    {wording}
  </div>
);

const Curtain: React.FC<{frame: number; color: string}> = ({frame, color}) => (
  <div
    style={{
      position: 'absolute',
      zIndex: 10,
      inset: 0,
      background: color,
      translate: `${interpolate(frame, [0, 17], [0, -1990], {extrapolateRight: 'clamp'})}px 0`,
      pointerEvents: 'none',
    }}
  />
);

export const AnimatedJourney: React.FC<{kind: JourneyKind}> = ({kind}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const isStart = kind === 'start';
  const isControls = kind === 'controls';
  const isChat = kind === 'chat';
  const dark = kind === 'join' || isChat;
  const phoneView: RoomView = isStart
    ? frame < 57 ? 'home' : frame < 102 ? 'finding' : 'room-empty'
    : kind === 'join'
      ? frame < 143 ? 'room-empty' : 'room-peer'
      : isControls
        ? frame < 50 ? 'paused' : frame < 118 ? 'playing' : frame < 185 ? 'paused' : frame < 240 ? 'seek' : 'playing'
        : 'chat';
  const tabletView: RoomView = kind === 'join'
    ? frame < 119 ? 'home' : 'room-peer'
    : isControls
      ? frame < 50 ? 'paused' : frame < 118 ? 'playing' : frame < 185 ? 'paused' : frame < 240 ? 'seek' : 'playing'
      : 'chat';
  const action = isControls ? frame < 82 ? 'PLAY' : frame < 166 ? 'PAUSE' : 'SEEK' : '';
  const actionFrame = isControls ? frame < 82 ? frame : frame < 166 ? frame - 82 : frame - 166 : 0;

  return (
    <AbsoluteFill style={{background: dark ? ink : cream, overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          width: 1300,
          height: 1300,
          left: isStart ? 1040 : isChat ? 800 : 350,
          top: isStart ? -190 : 170,
          border: `1px solid ${dark ? '#456578' : '#A2C5D5'}`,
          borderRadius: '50%',
          opacity: 0.65,
          scale: 0.88 + 0.12 * reveal(frame, 0, 60),
        }}
      />
      <div style={{position: 'absolute', left: 110, top: 78, zIndex: 3}}><Brand light={dark} size={34} /></div>
      <div style={{position: 'absolute', right: 106, top: 85, color: dark ? blue : '#39789D', fontFamily: 'DM Sans', fontSize: 18, fontWeight: 700, letterSpacing: 3, zIndex: 3}}>MEOWWATCH / TOGETHER</div>

      {isStart && <>
        <SceneType frame={frame} number="01" label="START A ROOM" lines={['Make room', 'for movie night.']} dark={false} left={110} top={268} size={112} />
        <div style={{position: 'absolute', left: 113, top: 615, fontFamily: 'DM Sans', color: '#476677', fontSize: 30, width: 660, lineHeight: 1.35, opacity: reveal(frame, 37, 20)}}>One tap opens a room you can share.</div>
        <Connection frame={frame} from={[150, 846]} to={[1180, 648]} start={95} color="#2B79A2" height={-260} />
        <Device left={1250} top={128} frame={frame} fps={fps} tiltFrom={-23} tiltTo={-8} scaleFrom={0.8}>
          <AnimatedPhone view={phoneView} frame={frame} taps={[{at: 45, x: 180, y: 348}]} />
        </Device>
        <div style={{position: 'absolute', left: 112, top: 822, color: '#2C6F91', fontFamily: 'DM Sans', fontSize: 20, letterSpacing: 3, fontWeight: 700, opacity: reveal(frame, 114, 20)}}>START → ROOM READY → INVITE</div>
      </>}

      {kind === 'join' && <>
        <SceneType frame={frame} number="02" label="JOIN THE ROOM" lines={['One invitation.', 'The same room.']} left={820} top={112} size={82} />
        <Device left={150} top={196} frame={frame} fps={fps} tiltFrom={-19} tiltTo={-6} scaleFrom={0.83}>
          <AnimatedPhone view={phoneView} peer={frame >= 143} frame={frame} />
        </Device>
        <Connection frame={frame} from={[535, 672]} to={[765, 672]} start={136} color={peach} height={-100} />
        <Device left={757} top={337} frame={frame} fps={fps} tiltFrom={18} tiltTo={5} scaleFrom={0.81} delay={8}>
          <AnimatedTablet view={tabletView} frame={frame} joinSheet={frame >= 40 && frame < 119} taps={[{at: 33, x: 260, y: 394}, {at: 95, x: 480, y: 460}]} />
        </Device>
        <div style={{position: 'absolute', left: 562, top: 616, padding: '11px 18px', color: peach, fontFamily: 'DM Sans', fontSize: 17, fontWeight: 700, letterSpacing: 2, background: '#1A2A37', borderRadius: 18, opacity: reveal(frame, 139, 20), zIndex: 4}}>JOINED</div>
      </>}

      {isControls && <>
        <SceneType frame={frame} number="03" label="SHARED CONTROLS" lines={['A single touch.', 'Both screens.']} dark={false} left={103} top={124} size={72} />
        <div style={{position: 'absolute', left: 110, top: 515, color: '#205D7D', fontFamily: 'DM Sans', fontSize: 91, fontWeight: 700, letterSpacing: -2, opacity: 0.15 * reveal(actionFrame, 0, 18), zIndex: 1}}>{action}</div>
        <Connection frame={frame} from={[820, 685]} to={[975, 685]} start={47} color="#2B79A2" height={-120} />
        <Device left={535} top={174} frame={frame} fps={fps} tiltFrom={-14} tiltTo={-3} scaleFrom={0.84}>
          <AnimatedPhone view={phoneView} peer frame={frame} afterSeek={frame >= 240} taps={[{at: 34, x: 180, y: 687}, {at: 171, x: 230, y: 623}, {at: 231, x: 180, y: 687}]} />
        </Device>
        <Device left={900} top={332} frame={frame} fps={fps} tiltFrom={14} tiltTo={3} scaleFrom={0.81} delay={5}>
          <AnimatedTablet view={tabletView} frame={frame} afterSeek={frame >= 240} taps={[{at: 103, x: 350, y: 515}]} />
        </Device>
        <div style={{position: 'absolute', left: 109, bottom: 111, width: 380, fontFamily: 'DM Sans', fontSize: 26, lineHeight: 1.3, color: '#526F7E', opacity: reveal(frame, 28, 20)}}>Play → pause → seek,<br />from either screen.</div>
      </>}

      {isChat && <>
        <SceneType frame={frame} number="04" label="STAY CLOSE" lines={['The little', 'things matter.']} left={800} top={98} size={74} />
        <Device left={144} top={146} frame={frame} fps={fps} tiltFrom={-15} tiltTo={-3} scaleFrom={0.82}>
          <AnimatedPhone view="chat" peer frame={frame} typing={frame >= 62 && frame < 113} chatSent={frame >= 117} taps={[{at: 107, x: 319, y: 742}]} />
        </Device>
        <Connection frame={frame} from={[500, 628]} to={[785, 628]} start={119} color={peach} height={-100} />
        <Device left={756} top={326} frame={frame} fps={fps} tiltFrom={15} tiltTo={3} scaleFrom={0.81} delay={5}>
          <AnimatedTablet view="chat" frame={frame} chatSent={frame >= 143} />
        </Device>
      </>}

      <Footer frame={frame} dark={dark} />
      <Curtain frame={frame} color={kind === 'join' || kind === 'chat' ? '#2B779F' : ink} />
    </AbsoluteFill>
  );
};
