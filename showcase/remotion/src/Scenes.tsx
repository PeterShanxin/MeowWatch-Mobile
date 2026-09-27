import React from 'react';
import {Video} from '@remotion/media';
import {AbsoluteFill, Sequence, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {Kicker, Mark, Paper, PhoneCuts, Pill, SourceLabel, Statement} from './Parts';
import {FPS, clamp, ink, night, paper, peach, pop, ramp, sans, serif, soft} from './theme';

const PHONE_LABEL = 'Real recording · MeowWatch on an Android phone (OnePlus, Android 16) · 1×';

const Bubble: React.FC<{text: string; mine: boolean; at: number}> = ({text, mine, at}) => {
  const frame = useCurrentFrame();
  const scale = pop(frame, at, 12);
  return (
    <div style={{display: 'flex', justifyContent: mine ? 'flex-end' : 'flex-start', height: frame < at ? 0 : 'auto'}}>
      <div
        style={{
          transform: `scale(${scale})`,
          transformOrigin: mine ? 'right bottom' : 'left bottom',
          margin: '7px 0',
          padding: '18px 34px',
          borderRadius: 40,
          background: mine ? ink : '#E2DBCF',
          color: mine ? paper : ink,
          fontFamily: sans,
          fontSize: 54,
          fontWeight: 500,
        }}
      >
        {text}
      </div>
    </div>
  );
};

const COUNTDOWN: [string, boolean, number][] = [
  ['ready?', false, 30],
  ['3', true, 70],
  ['2', true, 88],
  ['1', true, 106],
  ['play!', true, 124],
  ['wait', false, 164],
  ['I paused for snacks', false, 182],
  ['ok… again. 3…', true, 214],
];

export const Hook: React.FC = () => (
  <Paper>
    <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
      <div style={{width: 780}}>
        {COUNTDOWN.map(([text, mine, at]) => (
          <Bubble key={text} text={text} mine={mine} at={at} />
        ))}
      </div>
    </AbsoluteFill>
  </Paper>
);

export const Title: React.FC = () => {
  const frame = useCurrentFrame();
  const mark = pop(frame, 4, 15);
  const wordmark = pop(frame, 70);
  return (
    <Paper>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <div style={{transform: `scale(${mark}) translateY(${(1 - mark) * 30}px)`, marginBottom: 44}}>
          <Mark size={120} />
        </div>
        <Sequence from={14} layout="none">
          <Statement lines={['Movie night,', 'even miles apart.']} size={140} align="center" />
        </Sequence>
        <div style={{fontFamily: sans, fontSize: 30, fontWeight: 700, color: soft, letterSpacing: 6, marginTop: 30, opacity: wordmark, transform: `translateY(${(1 - wordmark) * 16}px)`}}>
          MEOWWATCH
        </div>
      </AbsoluteFill>
    </Paper>
  );
};

/** Phone on one side, one statement on the other. */
const PhoneBeat: React.FC<{
  cuts: {src: string; at: number; frames: number}[];
  lines: string[];
  kicker?: string;
  phoneLeft?: boolean;
  label?: string;
  size?: number;
}> = ({cuts, lines, kicker, phoneLeft = true, label = PHONE_LABEL, size = 124}) => {
  const frame = useCurrentFrame();
  const enter = pop(frame, 0, 16);
  const bob = Math.sin(frame / 38) * 9;
  const turn = Math.sin(frame / 55) * 5 * (phoneLeft ? 1 : -1);
  const phone = (
    <div
      style={{
        transform: `translateY(${(1 - enter) * 140 + bob}px) rotateX(${(1 - enter) * 18}deg) rotateY(${turn}deg)`,
        opacity: enter,
      }}
    >
      <PhoneCuts cuts={cuts} height={920} />
    </div>
  );
  const text = (
    <div style={{width: 860, transform: `translateY(${-bob * 0.5}px)`}}>
      <Statement lines={lines} size={size} delay={6} />
      {kicker ? <Kicker text={kicker} delay={18} /> : null}
    </div>
  );
  return (
    <Paper>
      <AbsoluteFill style={{flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 120, perspective: 1600}}>
        {phoneLeft ? phone : text}
        {phoneLeft ? text : phone}
      </AbsoluteFill>
      <SourceLabel text={label} />
    </Paper>
  );
};

export const StartRoom: React.FC = () => {
  const frame = useCurrentFrame();
  const second = frame >= 135;
  return (
    <PhoneBeat
      cuts={[
        {src: 'phone-start', at: 0.4, frames: 40},
        {src: 'phone-start', at: 4.6, frames: 42},
        {src: 'phone-start', at: 11.4, frames: 58},
        {src: 'phone-invite', at: 1, frames: 100},
      ]}
      lines={second ? ['Send the invite.'] : ['Start a room.']}
      kicker={second ? 'Link, code or QR. Joining is always free.' : 'No account needed.'}
    />
  );
};

export const InviteVideo: React.FC = () => (
  <PhoneBeat
    phoneLeft={false}
    cuts={[
      {src: 'phone-invite-video', at: 0.2, frames: 80},
      {src: 'phone-invite-video', at: 22.4, frames: 100},
    ]}
    lines={['The movie', 'comes along.']}
    kicker="Invites carry the host's video link, so you land on the same film."
    label="Real recording · a MeowWatch invite link opened on the phone"
  />
);

// The together-* clips are single screen recordings holding both apps side by
// side: the desktop window at x 0–1274 and the mirrored phone at x 1351–1728.
const CAPTURE_W = 1728;
const CAPTURE_H = 810;
const DESKTOP = {x: 0, w: 1274};
const PHONE = {x: 1351, w: 377};
const GAP = 60;
const SCALE = 0.9;
const PAIR_W = (DESKTOP.w + GAP + PHONE.w) * SCALE;
const PAIR_LEFT = (1920 - PAIR_W) / 2;

const CapturePanel: React.FC<{src: string; cuts: {at: number; frames: number}[]; region: {x: number; w: number}; style: React.CSSProperties}> = ({
  src,
  cuts,
  region,
  style,
}) => {
  let from = 0;
  return (
    <div
      style={{
        position: 'absolute',
        width: region.w * SCALE,
        height: CAPTURE_H * SCALE,
        overflow: 'hidden',
        borderRadius: 22,
        background: night,
        boxShadow: '0 60px 100px -40px rgba(22,24,29,0.55)',
        ...style,
      }}
    >
      {cuts.map((cut) => {
        const start = from;
        from += cut.frames;
        return (
          <Sequence key={cut.at} from={start} durationInFrames={cut.frames}>
            <Video
              src={staticFile(`media/${src}.mp4`)}
              trimBefore={Math.round(cut.at * FPS)}
              muted
              style={{
                position: 'absolute',
                width: CAPTURE_W * SCALE,
                height: CAPTURE_H * SCALE,
                left: -region.x * SCALE,
                top: 0,
                maxWidth: 'none',
              }}
            />
          </Sequence>
        );
      })}
    </div>
  );
};

/** Both apps from one recording, flying in from apart and meeting side by side. */
const CapturePair: React.FC<{src: string; cuts: {at: number; frames: number}[]; top: number; meetAt: number; enterAt?: number}> = ({
  src,
  cuts,
  top,
  meetAt,
  enterAt = 0,
}) => {
  const frame = useCurrentFrame();
  const apart = 1 - pop(frame, meetAt, 18);
  const float = Math.sin(frame / 45) * 5;
  const fadeIn = interpolate(frame, [enterAt, enterAt + 12], [0, 1], clamp);
  return (
    <AbsoluteFill style={{perspective: 1800}}>
      <CapturePanel
        src={src}
        cuts={cuts}
        region={DESKTOP}
        style={{
          left: PAIR_LEFT,
          top,
          opacity: fadeIn,
          transform: `translateX(${-apart * 520}px) translateY(${float}px) translateZ(${-apart * 900}px) rotateY(${apart * 42}deg)`,
        }}
      />
      <CapturePanel
        src={src}
        cuts={cuts}
        region={PHONE}
        style={{
          left: PAIR_LEFT + (DESKTOP.w + GAP) * SCALE,
          top,
          opacity: fadeIn,
          transform: `translateX(${apart * 620}px) translateY(${float}px) translateZ(${-apart * 900}px) rotateY(${-apart * 42}deg)`,
        }}
      />
    </AbsoluteFill>
  );
};

const PAIR_LABEL = 'Real-time screen recording · MeowWatch for Windows + Android phone (mirrored) · same room · 1×';
const DESKTOP_MID = PAIR_LEFT + (DESKTOP.w * SCALE) / 2;
const PHONE_MID = PAIR_LEFT + (DESKTOP.w + GAP + PHONE.w / 2) * SCALE;

export const Together: React.FC = () => {
  const frame = useCurrentFrame();
  const titleOut = ramp(frame, 60, 72);
  const pillY = 150 + CAPTURE_H * SCALE + 56;
  return (
    <Paper>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', opacity: 1 - titleOut}}>
        <Statement lines={['Two screens.', 'One movie night.']} size={120} align="center" delay={0} />
      </AbsoluteFill>
      <CapturePair
        src="together-sync"
        cuts={[
          {at: 0, frames: 345},
          {at: 20.3, frames: 105},
        ]}
        top={150}
        meetAt={68}
        enterAt={62}
      />
      <Pill text="Play on the phone…" from={99} to={180} x={PHONE_MID} y={pillY} />
      <Pill text="…the laptop plays too." from={143} to={230} x={DESKTOP_MID} y={pillY} />
      <Pill text="Pause on the laptop. Both pause." from={297} to={345} x={DESKTOP_MID} y={pillY} />
      <Pill text="Skip ahead, together." from={361} to={445} x={960} y={pillY} />
      <SourceLabel text={PAIR_LABEL} />
    </Paper>
  );
};

export const React_: React.FC = () => (
  <Paper>
    <div style={{position: 'absolute', top: 64, width: '100%'}}>
      <Statement lines={['React together.']} size={84} align="center" delay={4} />
    </div>
    <CapturePair src="together-react" cuts={[{at: 1.3, frames: 240}]} top={190} meetAt={-30} />
    <div style={{position: 'absolute', top: 190 + CAPTURE_H * SCALE + 26, width: '100%', textAlign: 'center'}}>
      <Kicker text="A heart on the phone floats up on the laptop, the same moment." delay={20} />
    </div>
    <SourceLabel text={PAIR_LABEL} />
  </Paper>
);

export const ContinueWatching: React.FC = () => (
  <PhoneBeat cuts={[{src: 'phone-continue', at: 0.3, frames: 120}]} lines={['Pick up where', 'you left off.']} />
);

export const Plus: React.FC = () => {
  const frame = useCurrentFrame();
  if (frame < 170) {
    const second = frame >= 85;
    return (
      <Paper>
        <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
          {second ? (
            <Statement key="host" lines={['Hosts get one free', 'movie night a day.']} size={120} align="center" />
          ) : (
            <Statement key="guest" lines={['Guests always', 'join free.']} size={132} align="center" />
          )}
        </AbsoluteFill>
      </Paper>
    );
  }
  return (
    <Sequence from={170} layout="none">
      <PhoneBeat
        cuts={[
          {src: 'phone-paywall', at: 1.2, frames: 70},
          {src: 'phone-paywall', at: 21.8, frames: 58},
          {src: 'phone-paywall', at: 30.6, frames: 40},
          {src: 'phone-themes', at: 6, frames: 52},
        ]}
        lines={['More nights?', 'Go Plus.']}
        kicker="Unlimited rooms · themes · premium reactions"
        label="Real recording · RevenueCat Test Store purchase · no real charge"
      />
    </Sequence>
  );
};

export const Ending: React.FC = () => {
  const frame = useCurrentFrame();
  const mark = pop(frame, 0, 16);
  return (
    <Paper>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <div style={{transform: `scale(${mark})`}}>
          <Mark size={150} />
        </div>
        <div style={{fontFamily: serif, fontSize: 96, color: ink, marginTop: 34, opacity: ramp(frame, 8, 22)}}>MeowWatch</div>
        <div style={{fontFamily: sans, fontSize: 34, color: soft, marginTop: 8, opacity: ramp(frame, 16, 30)}}>
          Movie night, even miles apart.
        </div>
        <div
          style={{
            marginTop: 60,
            padding: '12px 26px',
            borderRadius: 999,
            border: `2px solid ${peach}`,
            fontFamily: sans,
            fontSize: 24,
            fontWeight: 600,
            color: ink,
            opacity: ramp(frame, 30, 44),
          }}
        >
          Android · Open source (AGPL-3.0) · RevenueCat Shipaton 2026 · Next Gen
        </div>
      </AbsoluteFill>
      <div style={{position: 'absolute', bottom: 70, width: '100%', textAlign: 'center', fontFamily: sans, fontSize: 18, color: soft}}>
        Sintel trailer © Blender Foundation · sintel.org · CC BY 3.0 · Original score · Synthesized narration
      </div>
    </Paper>
  );
};

export const SCENES: [React.FC, number][] = [
  [Hook, 255],
  [Title, 150],
  [StartRoom, 240],
  [InviteVideo, 180],
  [Together, 450],
  [React_, 240],
  [ContinueWatching, 120],
  [Plus, 390],
  [Ending, 210],
];

