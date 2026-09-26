import {Easing, interpolate, spring} from 'remotion';

export const FPS = 30;
export const paper = '#F1ECE3';
export const ink = '#16181D';
export const soft = '#6E6A63';
export const peach = '#E9A273';
export const night = '#0C0F14';
export const serif = 'DM Serif Display';
export const sans = 'DM Sans';

export const ease = Easing.bezier(0.16, 1, 0.3, 1);

export const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

export const ramp = (frame: number, from: number, to: number) =>
  interpolate(frame, [from, to], [0, 1], {...clamp, easing: ease});

export const pop = (frame: number, delay = 0, damping = 14) =>
  spring({frame: frame - delay, fps: FPS, config: {damping, stiffness: 170, mass: 0.7}});
