import React from 'react';
import {Img, interpolate, staticFile} from 'remotion';

const surface = '#10141F';
const card = '#1A2232';
const line = '#333F52';
const text = '#F5EDE0';
const soft = '#BDBDCA';
const peach = '#EFB38C';
const lavender = '#B9A9D3';
const room = 'lively-mole-rolls-smiley-acorn';

export type RoomView = 'home' | 'finding' | 'room-empty' | 'room-peer' | 'playing' | 'paused' | 'seek' | 'chat';

export const TapPulse: React.FC<{frame: number; at: number; x: number; y: number; color?: string}> = ({frame, at, x, y, color = peach}) => {
  const age = frame - at;
  if (age < 0 || age > 23) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left: x - 24,
        top: y - 24,
        width: 48,
        height: 48,
        border: `3px solid ${color}`,
        boxShadow: '0 0 0 2px #071522, inset 0 0 0 2px #071522',
        borderRadius: '50%',
        scale: interpolate(age, [0, 23], [0.35, 2.55]),
        opacity: interpolate(age, [0, 23], [0.85, 0]),
        pointerEvents: 'none',
        zIndex: 30,
      }}
    />
  );
};

const BeeFrame: React.FC<{width: number; height: number; progress?: number}> = ({width, height, progress = 0.13}) => (
  <div style={{width, height, overflow: 'hidden', borderRadius: 13, background: '#111820'}}>
    <Img
      src={staticFile('media/bee-still.jpg')}
      style={{width, height, objectFit: 'cover', scale: 1.08, translate: `${interpolate(progress, [0.13, 0.64], [8, -8])}px 0`}}
    />
  </div>
);

const playbackProgress = (view: RoomView, frame: number, afterSeek = false) => {
  if (view === 'chat') return 0.59;
  if (view === 'seek') return 0.59;
  if (afterSeek && view === 'playing') return 0.59 + Math.min(0.05, Math.max(0, frame - 240) * 0.0008);
  if (view === 'playing') return 0.13 + Math.min(0.08, Math.max(0, frame - 50) * 0.0012);
  if (view === 'paused' && frame >= 118) return 0.21;
  return 0.13;
};

const playbackTime = (progress: number) => {
  const seconds = Math.round(progress * 90);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
};

const AppMark: React.FC<{size?: number}> = ({size = 22}) => (
  <Img src={staticFile('brand/meowwatch.svg')} style={{width: size, height: size, objectFit: 'contain'}} />
);

const RoundedButton: React.FC<{label: string; fill?: boolean; width?: number}> = ({label, fill = true, width}) => (
  <div
    style={{
      width,
      height: 47,
      borderRadius: 14,
      border: fill ? 'none' : `1px solid ${line}`,
      background: fill ? peach : 'transparent',
      color: fill ? '#332318' : text,
      display: 'grid',
      placeItems: 'center',
      fontFamily: 'DM Sans',
      fontSize: 14,
      fontWeight: 700,
      boxSizing: 'border-box',
    }}
  >
    {label}
  </div>
);

const StatusBar: React.FC<{time?: string}> = ({time = '6:17'}) => (
  <div style={{height: 24, padding: '0 13px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: text, fontSize: 11}}>
    <span>{time} ▣</span><span>◆ ▰ ▣</span>
  </div>
);

const PhoneHome: React.FC<{busy?: boolean}> = ({busy = false}) => (
  <>
    <div style={{display: 'flex', alignItems: 'center', gap: 8, padding: '21px 18px 0'}}>
      <AppMark size={20} />
      <span style={{fontSize: 11, fontWeight: 700, letterSpacing: 2}}>MEOWWATCH</span>
      <span style={{marginLeft: 'auto', color: soft, fontSize: 12}}>Plus　◯</span>
    </div>
    <div style={{padding: '60px 22px 0'}}>
      <div style={{fontFamily: 'DM Serif Display', fontSize: 41, lineHeight: 1.02, letterSpacing: -1.1}}>
        Movie night,<br />even miles apart.
      </div>
      <div style={{fontSize: 15, lineHeight: 1.48, color: soft, marginTop: 20}}>
        Press play together, chat through every scene, and keep the same room on any screen.
      </div>
      <div style={{marginTop: 27}}><RoundedButton label={busy ? '◌  Getting things ready…' : '＋  Start a room'} width={316} /></div>
      <div style={{marginTop: 10}}><RoundedButton label="↪  Join a room" fill={false} width={316} /></div>
      <div style={{marginTop: 17, padding: 15, background: card, borderRadius: 16, fontSize: 14}}>
        <span style={{color: peach}}>▣</span>　Local Player Mode
        <div style={{fontSize: 12, color: soft, marginLeft: 29, marginTop: 5}}>Watch on this device without starting a room.</div>
      </div>
      <div style={{fontFamily: 'DM Serif Display', fontSize: 23, marginTop: 35}}>Continue Watching</div>
      <div style={{fontSize: 12, color: soft, marginTop: 8}}>Your next movie night is waiting.</div>
    </div>
  </>
);

const PhoneRoom: React.FC<{view: RoomView; frame: number; peer?: boolean; message?: boolean; afterSeek?: boolean}> = ({view, frame, peer = false, message = false, afterSeek = false}) => {
  const hasMedia = view === 'playing' || view === 'paused' || view === 'seek' || view === 'chat';
  const playing = view === 'playing';
  const progress = playbackProgress(view, frame, afterSeek);
  return (
    <>
      <div style={{padding: '15px 12px 8px', display: 'flex', alignItems: 'center', gap: 8}}>
        <span style={{fontSize: 23, color: soft}}>‹</span>
        <div style={{minWidth: 0, flex: 1}}>
          <div style={{whiteSpace: 'nowrap', textOverflow: 'ellipsis', overflow: 'hidden', fontSize: 15}}>{room}</div>
          <div style={{fontSize: 11, color: soft, marginTop: 2}}>{peer ? 'Together in this room' : 'Waiting for your people'}</div>
        </div>
        <span style={{fontSize: 17, color: soft}}>▣　↥</span>
      </div>
      <div style={{margin: '9px 17px 0', height: 210, borderRadius: 17, background: '#0B0F16', display: 'grid', placeItems: 'center', overflow: 'hidden'}}>
        {hasMedia ? <BeeFrame width={326} height={210} progress={progress} /> : (
          <div style={{textAlign: 'center'}}>
            <div style={{fontSize: 30, color: peach, marginBottom: 19}}>▣</div>
            <div style={{width: 143, height: 43, borderRadius: 12, background: lavender, display: 'grid', placeItems: 'center', color: '#251E33', fontSize: 12, fontWeight: 700}}>＋ Choose a video</div>
          </div>
        )}
      </div>
      <div style={{padding: '21px 17px 0'}}>
        <div style={{fontFamily: 'DM Serif Display', fontSize: 26, lineHeight: 1.12}}>{hasMedia ? 'Bee.mp4' : 'The best seat is together.'}</div>
        <div style={{fontSize: 12, color: soft, marginTop: 6}}>{hasMedia ? 'Playing on this phone' : 'Choose a video file or open a direct video link.'}</div>
        <div style={{display: 'flex', gap: 12, marginTop: 21, fontSize: 12, alignItems: 'center'}}>
          <span style={{background: '#263045', width: 25, height: 25, borderRadius: 13, display: 'grid', placeItems: 'center'}}>M</span> Mochi a223 (you)
          {peer && <><span style={{background: '#263045', width: 25, height: 25, borderRadius: 13, display: 'grid', placeItems: 'center'}}>B</span> Bean a223</>}
        </div>
        {peer ? <div style={{fontSize: 12, color: soft, marginTop: 16}}>▤　Bean a223 joined.</div> : <div style={{marginTop: 19}}><RoundedButton label="∞  Invite someone" fill={false} width={326} /></div>}
        {message && <div style={{marginTop: 13, color: text, background: card, padding: 11, borderRadius: 10, fontSize: 12}}>Ready here too. Press play when you are comfy.</div>}
      </div>
      <div style={{position: 'absolute', bottom: 64, left: 19, right: 19}}>
        <div style={{height: 4, borderRadius: 3, background: '#333F52', position: 'relative'}}>
          <div style={{height: 4, width: `${progress * 100}%`, background: peach, borderRadius: 3}} />
          <div style={{position: 'absolute', left: `calc(${progress * 100}% - 7px)`, top: -5, width: 14, height: 14, borderRadius: 8, background: peach}} />
        </div>
        <div style={{display: 'flex', justifyContent: 'space-between', fontSize: 10, color: soft, marginTop: 8}}><span>{hasMedia ? playbackTime(progress) : '0:00'}</span><span>{hasMedia ? '1:30' : '0:00'}</span></div>
        <div style={{display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 25, marginTop: 14}}>
          <span style={{fontSize: 21, color: soft}}>↶</span>
          <div style={{width: 62, height: 52, borderRadius: 26, background: hasMedia ? peach : '#303847', color: hasMedia ? '#332318' : soft, display: 'grid', placeItems: 'center', fontSize: 27}}>{playing ? 'Ⅱ' : '▶'}</div>
          <span style={{fontSize: 21, color: soft}}>↷</span>
        </div>
        <div style={{display: 'flex', justifyContent: 'center', gap: 25, color: peach, fontSize: 12, marginTop: 15}}><span>▣ Video</span><span>▤ Chat</span><span>♡</span></div>
      </div>
    </>
  );
};

const PhoneChat: React.FC<{sent: boolean; typing: boolean}> = ({sent, typing}) => (
  <div style={{position: 'absolute', inset: '45px 0 0', borderRadius: '25px 25px 0 0', background: '#141C27', padding: '22px 18px', zIndex: 3}}>
    <div style={{fontSize: 18, display: 'flex', justifyContent: 'space-between'}}>Room chat <span style={{color: soft}}>×</span></div>
    <div style={{fontSize: 11, textAlign: 'center', color: soft, marginTop: 188}}>Bean a223 joined.</div>
    <div style={{marginTop: 14, background: card, borderRadius: 16, padding: 13, fontSize: 13, width: 208}}><span style={{fontSize: 10, color: lavender}}>Bean a223</span><br />Ready for movie night! 🍿</div>
    {sent && <div style={{marginTop: 14, marginLeft: 'auto', background: peach, color: '#332318', borderRadius: 16, padding: 13, fontSize: 13, width: 225}}>Ready here too. Press play when you are comfy.</div>}
    <div style={{position: 'absolute', bottom: 32, left: 15, right: 15, display: 'flex', gap: 8}}>
      <div style={{border: `1px solid ${line}`, borderRadius: 12, height: 49, flex: 1, padding: '13px 12px', boxSizing: 'border-box', fontSize: 11, color: typing ? text : soft}}>{typing ? 'Ready here too. Press play…' : 'Say hello or paste a video link…'}</div>
      <div style={{width: 49, height: 49, borderRadius: 25, background: peach, color: '#332318', display: 'grid', placeItems: 'center', fontSize: 23}}>↑</div>
    </div>
  </div>
);

export const AnimatedPhone: React.FC<{view: RoomView; peer?: boolean; frame: number; taps?: {at: number; x: number; y: number}[]; chatSent?: boolean; typing?: boolean; afterSeek?: boolean}> = ({view, peer, frame, taps = [], chatSent = false, typing = false, afterSeek = false}) => (
  <div style={{width: 360, height: 800, borderRadius: 26, position: 'relative', background: surface, color: text, overflow: 'hidden', fontFamily: 'DM Sans', boxSizing: 'border-box'}}>
    <StatusBar />
    {view === 'home' || view === 'finding' ? <PhoneHome busy={view === 'finding'} /> : <PhoneRoom view={view} frame={frame} peer={peer} message={view === 'chat' && chatSent} afterSeek={afterSeek} />}
    {view === 'chat' && <PhoneChat sent={chatSent} typing={typing} />}
    {taps.map((tap) => <TapPulse key={tap.at} frame={frame} {...tap} />)}
    <div style={{position: 'absolute', bottom: 8, left: 132, width: 96, height: 4, borderRadius: 5, background: '#E9EDF4'}} />
  </div>
);

const TabletHome: React.FC<{sheet: boolean}> = ({sheet}) => (
  <>
    <div style={{display: 'flex', alignItems: 'center', gap: 8, padding: '15px 30px', fontSize: 12, letterSpacing: 2}}><AppMark size={24} /> MEOWWATCH <span style={{marginLeft: 'auto', color: soft}}>Plus　◯</span></div>
    <div style={{display: 'flex', padding: '42px 39px', gap: 72}}>
      <div style={{width: 440}}>
        <div style={{fontFamily: 'DM Serif Display', fontSize: 52, lineHeight: 1.05}}>Movie night,<br />even miles apart.</div>
        <div style={{fontSize: 14, color: soft, marginTop: 17, lineHeight: 1.45}}>Press play together, chat through every scene, and keep the same room on any screen.</div>
        <div style={{marginTop: 22}}><RoundedButton label="＋  Start a room" width={440} /></div>
        <div style={{marginTop: 10}}><RoundedButton label="↪  Join a room" fill={false} width={440} /></div>
        <div style={{background: card, borderRadius: 12, marginTop: 13, padding: 14, fontSize: 14}}>▣　Local Player Mode</div>
      </div>
      <div style={{flex: 1, paddingTop: 7}}><div style={{fontFamily: 'DM Serif Display', fontSize: 28}}>Continue Watching</div><div style={{color: soft, fontSize: 12, marginTop: 6}}>Your next movie night is waiting.</div></div>
    </div>
    {sheet && <div style={{position: 'absolute', inset: 0, background: '#0000009C', display: 'flex', alignItems: 'flex-end', justifyContent: 'center'}}>
      <div style={{width: 550, height: 354, borderRadius: '25px 25px 0 0', background: '#141C27', padding: '21px 25px', boxSizing: 'border-box'}}>
        <div style={{fontSize: 24, fontWeight: 700}}>Join their movie night</div>
        <div style={{fontSize: 12, color: soft, marginTop: 7}}>Paste a MeowWatch invite link or enter the room code they sent you.</div>
        <div style={{border: `1px solid ${line}`, background: card, borderRadius: 13, marginTop: 20, padding: 14, fontSize: 12, color: text}}>Room code or invite link<br /><span style={{fontSize: 15, color: peach}}>{room}</span></div>
        <div style={{fontSize: 12, color: peach, marginTop: 10}}>⌗　Scan invite QR</div>
        <div style={{marginTop: 15}}><RoundedButton label="↪  Join room" width={500} /></div>
      </div>
    </div>}
  </>
);

const TabletRoom: React.FC<{view: RoomView; frame: number; chatSent?: boolean; afterSeek?: boolean}> = ({view, frame, chatSent = false, afterSeek = false}) => {
  const hasMedia = view === 'playing' || view === 'paused' || view === 'seek' || view === 'chat';
  const playing = view === 'playing';
  const progress = playbackProgress(view, frame, afterSeek);
  return (
    <div style={{display: 'flex', height: 576}}>
      <div style={{width: 705, padding: '0 18px', boxSizing: 'border-box'}}>
        <div style={{height: 55, display: 'flex', alignItems: 'center', gap: 8, fontSize: 15}}>‹　<div><div>{room}</div><div style={{fontSize: 10, color: soft}}>Together in this room</div></div><span style={{marginLeft: 'auto', color: soft}}>⛶　▣　↥</span></div>
        <div style={{height: 360, borderRadius: 13, background: '#0B0F16', display: 'grid', placeItems: 'center', overflow: 'hidden'}}>
          {hasMedia ? <BeeFrame width={670} height={360} progress={progress} /> : <div style={{textAlign: 'center'}}><div style={{fontSize: 40, color: peach, marginBottom: 19}}>▣</div><div style={{background: lavender, color: '#251E33', borderRadius: 12, padding: '15px 22px', fontSize: 14, fontWeight: 700}}>＋ Choose a video</div></div>}
        </div>
        <div style={{height: 4, marginTop: 18, borderRadius: 3, background: line}}><div style={{height: 4, width: `${progress * 100}%`, background: peach, borderRadius: 3}} /></div>
        <div style={{fontSize: 10, color: soft, marginTop: 7, display: 'flex', justifyContent: 'space-between'}}><span>{hasMedia ? playbackTime(progress) : '0:00'}</span><span>{hasMedia ? '1:30' : '0:00'}</span></div>
        <div style={{display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 19, marginTop: 11}}><span style={{fontSize: 23, color: soft}}>↶</span><div style={{width: 55, height: 48, borderRadius: 25, background: hasMedia ? peach : '#303847', color: hasMedia ? '#332318' : soft, display: 'grid', placeItems: 'center', fontSize: 25}}>{playing ? 'Ⅱ' : '▶'}</div><span style={{fontSize: 23, color: soft}}>↷</span></div>
        <div style={{textAlign: 'center', fontSize: 12, color: peach, marginTop: 9}}>▣ Video　　 ▤ Chat　　 ♡</div>
      </div>
      <div style={{borderLeft: `1px solid ${line}`, flex: 1, padding: '17px 13px', position: 'relative', boxSizing: 'border-box'}}>
        <div style={{fontSize: 17}}>Room chat</div>
        {view === 'chat' && <div style={{marginTop: 208}}><div style={{background: peach, color: '#332318', borderRadius: 13, padding: 10, fontSize: 11, width: 145, marginLeft: 'auto'}}>Ready for movie night! 🍿</div>{chatSent && <div style={{background: card, borderRadius: 13, padding: 10, fontSize: 11, marginTop: 10}}><span style={{color: lavender}}>Mochi a223</span><br />Ready here too. Press play when you are comfy.</div>}</div>}
        <div style={{position: 'absolute', bottom: 17, left: 12, right: 12, display: 'flex', gap: 7}}><div style={{flex: 1, border: `1px solid ${line}`, borderRadius: 11, padding: 10, color: soft, fontSize: 10}}>Say hello or paste a video link…</div><div style={{background: peach, color: '#332318', borderRadius: 22, width: 40, display: 'grid', placeItems: 'center'}}>↑</div></div>
      </div>
    </div>
  );
};

export const AnimatedTablet: React.FC<{view: RoomView; joinSheet?: boolean; chatSent?: boolean; frame: number; taps?: {at: number; x: number; y: number}[]; afterSeek?: boolean}> = ({view, joinSheet = false, chatSent, frame, taps = [], afterSeek = false}) => (
  <div style={{width: 960, height: 600, position: 'relative', overflow: 'hidden', background: surface, color: text, fontFamily: 'DM Sans', borderRadius: 16}}>
    <StatusBar />
    {view === 'home' || view === 'finding' ? <TabletHome sheet={joinSheet} /> : <TabletRoom view={view} frame={frame} chatSent={chatSent} afterSeek={afterSeek} />}
    {taps.map((tap) => <TapPulse key={tap.at} frame={frame} {...tap} />)}
    <div style={{position: 'absolute', bottom: 8, left: 433, width: 94, height: 3, borderRadius: 5, background: '#E9EDF4'}} />
  </div>
);
