import {loadFont} from '@remotion/fonts';
import {registerRoot} from 'remotion';
import {staticFile} from 'remotion';
import {Root} from './Root';

void Promise.all([
  loadFont({
    family: 'DM Sans',
    url: staticFile('fonts/DMSans.ttf'),
    weight: '100 900',
    display: 'block',
  }),
  loadFont({
    family: 'DM Serif Display',
    url: staticFile('fonts/DMSerifDisplay.ttf'),
    weight: '400',
    display: 'block',
  }),
]);

registerRoot(Root);
