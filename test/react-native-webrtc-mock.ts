// Stands in for react-native-webrtc in tests, which have no phone: the calls client is given its own media in each test.
export class MediaStream {
  constructor(readonly tracks: unknown[] = []) {}
  toURL() {
    return 'stream-url';
  }
}
export const mediaDevices = {
  getUserMedia: async () => {
    throw new Error('a test must pass its own getUserMedia');
  },
  getDisplayMedia: async () => {
    throw new Error('a test must pass its own getDisplayMedia');
  },
};
export const registerGlobals = () => undefined;
