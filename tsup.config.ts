import { defineConfig } from 'tsup';

export default defineConfig({
  entry: { index: 'src/index.ts', calls: 'src/calls.ts' },
  format: ['cjs', 'esm'],
  dts: true,
  clean: true,
  external: ['react-native', 'react-native-webrtc', 'mediasoup-client'],
});
