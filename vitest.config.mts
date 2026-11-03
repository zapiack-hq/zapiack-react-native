import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: { include: ['test/**/*.test.ts'], environment: 'node' },
  resolve: { alias: { 'react-native': fileURLToPath(new URL('./test/react-native-mock.ts', import.meta.url)) } },
});
