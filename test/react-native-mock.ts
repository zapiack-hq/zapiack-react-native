// Stands in for react-native in tests: the native module is whatever a test puts on `NativeModules`.
export const NativeModules: Record<string, unknown> = {};
export const Platform = { OS: 'android' as 'android' | 'ios' };

type Listener = (payload: unknown) => void;
const listeners = new Map<string, Set<Listener>>();

export class NativeEventEmitter {
  addListener(event: string, listener: Listener) {
    if (!listeners.has(event)) listeners.set(event, new Set());
    listeners.get(event)!.add(listener);
    return { remove: () => void listeners.get(event)!.delete(listener) };
  }
}

/** For tests: what the native side does to raise an event. */
export const emitFromNative = (event: string, payload: unknown) => listeners.get(event)?.forEach((l) => l(payload));
export const listenerCount = (event: string) => listeners.get(event)?.size ?? 0;
