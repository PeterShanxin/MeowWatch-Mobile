import React from 'react';
import {Img, staticFile} from 'remotion';
import {cream} from './theme';

export const Brand: React.FC<{light?: boolean; size?: number}> = ({
  light = true,
  size = 38,
}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 17}}>
    <div
      style={{
        width: size + 12,
        height: size + 12,
        borderRadius: 16,
        background: light ? '#F4F0E8' : '#071522',
        display: 'grid',
        placeItems: 'center',
        overflow: 'hidden',
      }}
    >
      <Img
        src={staticFile('brand/meowwatch.svg')}
        style={{width: size, height: size, objectFit: 'contain'}}
      />
    </div>
    <span
      style={{
        fontFamily: 'DM Sans',
        color: light ? cream : '#071522',
        fontWeight: 700,
        fontSize: size * 0.58,
        letterSpacing: -0.8,
      }}
    >
      MeowWatch
    </span>
  </div>
);
