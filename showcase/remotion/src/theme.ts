import {Easing, interpolate} from 'remotion';

export const ink = '#071522';
export const cream = '#F4F0E8';
export const blue = '#8FCBEB';
export const peach = '#EFC4A6';
export const muted = '#9DADBA';
export const ease = Easing.bezier(0.16, 1, 0.3, 1);

export const reveal = (frame: number, delay = 0, length = 22) =>
  interpolate(frame, [delay, delay + length], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: ease,
  });

export const fadeEdge = (frame: number, duration: number) =>
  interpolate(frame, [0, 7, duration - 9, duration], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
