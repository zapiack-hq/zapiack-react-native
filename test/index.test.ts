import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NativeModules, Platform } from 'react-native';
import { emitFromNative, listenerCount } from './react-native-mock';
import { ZapiackError, ZapiackPush } from '../src';

const calls: Array<[string, unknown[]]> = [];
let answers: Record<string, unknown> = {};

const method = (name: string) => (...args: unknown[]) => {
  calls.push([name, args]);
  return Promise.resolve(answers[name]);
};

beforeEach(() => {
  calls.length = 0;
  answers = {};
  Platform.OS = 'android';
  NativeModules.ZapiackPush = Object.fromEntries(
    ['configure', 'requestPermission', 'installationId', 'login', 'logout', 'addTags', 'removeTags', 'screen', 'track', 'flush', 'initialTap'].map((n) => [n, method(n)]),
  );
});

describe('configure', () => {
  it('passes the key, address and group on', async () => {
    await ZapiackPush.configure({ appKey: 'pk_abc', appGroup: 'group.example' });
    expect(calls).toEqual([['configure', [{ appKey: 'pk_abc', baseUrl: null, appGroup: 'group.example' }]]]);
  });

  it('refuses a secret key before it goes anywhere', () => {
    expect(() => ZapiackPush.configure({ appKey: 'sk_secret' })).toThrow(ZapiackError);
    expect(calls).toEqual([]);
  });

  it('needs an App Group on iOS but not on Android', async () => {
    Platform.OS = 'ios';
    expect(() => ZapiackPush.configure({ appKey: 'pk_abc' })).toThrow(/appGroup/);
    Platform.OS = 'android';
    await expect(ZapiackPush.configure({ appKey: 'pk_abc' })).resolves.toBeUndefined();
  });
});

describe('the rest of the API', () => {
  it('requestPermission is true only when the platform says so', async () => {
    answers.requestPermission = true;
    expect(await ZapiackPush.requestPermission()).toBe(true);
    answers.requestPermission = undefined;
    expect(await ZapiackPush.requestPermission()).toBe(false);
  });

  it('users and tags go across as they are', async () => {
    await ZapiackPush.login('user_1');
    await ZapiackPush.logout();
    await ZapiackPush.addTags({ plan: 'pro', age: 3, beta: true });
    await ZapiackPush.removeTags(['age']);
    expect(calls).toEqual([
      ['login', ['user_1']],
      ['logout', []],
      ['addTags', [{ plan: 'pro', age: 3, beta: true }]],
      ['removeTags', [['age']]],
    ]);
  });

  it('track says whether anything was credited, and sends null for no properties', async () => {
    answers.track = true;
    expect(await ZapiackPush.track('purchase', { total: 49 })).toBe(true);
    answers.track = undefined;
    expect(await ZapiackPush.track('late')).toBe(false);
    expect(calls.map((c) => c[1])).toEqual([['purchase', { total: 49 }], ['late', null]]);
  });

  it('the push that opened the app is null when there was none', async () => {
    answers.initialTap = { messageId: 'm', deliveryId: 'd', sessionId: 's' };
    expect((await ZapiackPush.initialTap())?.deliveryId).toBe('d');
    answers.initialTap = null;
    expect(await ZapiackPush.initialTap()).toBeNull();
  });
});

describe('taps while the app is open', () => {
  it('reach the listener, and stop reaching it once removed', () => {
    const seen = vi.fn();
    const stop = ZapiackPush.onTap(seen);
    emitFromNative('zapiackTap', { messageId: 'm', deliveryId: 'd', sessionId: 's', link: 'myshop://orders/1' });
    expect(seen).toHaveBeenCalledWith({ messageId: 'm', deliveryId: 'd', sessionId: 's', link: 'myshop://orders/1' });
    stop();
    expect(listenerCount('zapiackTap')).toBe(0);
    emitFromNative('zapiackTap', { messageId: 'm2' });
    expect(seen).toHaveBeenCalledTimes(1);
  });
});

describe('when the native part is missing', () => {
  it('says how to fix it instead of failing on undefined', () => {
    delete NativeModules.ZapiackPush;
    expect(() => ZapiackPush.login('u')).toThrow(/not linked/);
  });
});
