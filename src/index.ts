import { NativeEventEmitter, NativeModules, Platform } from 'react-native';

/** What was tapped, handed to the app so it can route. */
export interface ZapiackTap {
  messageId: string;
  deliveryId: string;
  sessionId: string;
  /** The button that was tapped, when it was a button. */
  actionId?: string | null;
  /** The event name set on the notification or the button. */
  event?: string | null;
  /** Where the notification or the button asked to go. Only links an app can route are given. */
  link?: string | null;
}

export interface ConfigureOptions {
  /** The public app key, which starts with `pk_`. */
  appKey: string;
  /** Defaults to https://api.zapiack.com/v1 */
  baseUrl?: string;
  /** iOS only: the App Group shared with the notification extension, for example `group.com.example.app`. */
  appGroup?: string;
}

export type TagValue = string | number | boolean | null;

/** Thrown when the SDK is used wrongly, for example with a secret key. */
export class ZapiackError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ZapiackError';
  }
}

interface NativeZapiack {
  configure(options: { appKey: string; baseUrl: string | null; appGroup: string | null }): Promise<void>;
  requestPermission(): Promise<boolean>;
  installationId(): Promise<string | null>;
  login(userId: string): Promise<void>;
  logout(): Promise<void>;
  addTags(tags: Record<string, TagValue>): Promise<void>;
  removeTags(keys: string[]): Promise<void>;
  screen(name: string): Promise<void>;
  track(name: string, properties: Record<string, unknown> | null): Promise<boolean>;
  flush(): Promise<void>;
  initialTap(): Promise<ZapiackTap | null>;
  addListener(event: string): void;
  removeListeners(count: number): void;
}

const TAP_EVENT = 'zapiackTap';

function native(): NativeZapiack {
  const module = NativeModules.ZapiackPush as NativeZapiack | undefined;
  if (!module) {
    throw new ZapiackError(
      'The native part of @zapiack/react-native is not linked. Rebuild the app (pod install on iOS, a clean Gradle build on Android), and note that Expo Go cannot run it: use a development build.',
    );
  }
  return module;
}

let emitter: NativeEventEmitter | undefined;

export const ZapiackPush = {
  /** Call once at start-up, before anything else. */
  configure(options: ConfigureOptions): Promise<void> {
    if (!options.appKey.startsWith('pk_')) throw new ZapiackError('ZapiackPush needs the public app key, which starts with pk_');
    if (Platform.OS === 'ios' && !options.appGroup) {
      throw new ZapiackError('On iOS, appGroup is required: it is how the app and its notification extension share what they need');
    }
    return native().configure({ appKey: options.appKey, baseUrl: options.baseUrl ?? null, appGroup: options.appGroup ?? null });
  },

  /** Shows the system permission prompt where there is one, registers for push, and says whether notifications are allowed. */
  async requestPermission(): Promise<boolean> {
    return (await native().requestPermission()) === true;
  },

  /** The identifier that ties this install to the service, once `configure` has run. */
  installationId(): Promise<string | null> {
    return native().installationId();
  },

  /** Link this install to the user your server knows. Send to `externalUserIds` from your server to reach them. */
  login(userId: string): Promise<void> {
    return native().login(userId);
  },

  /** Unlink this install from the user, on sign-out. */
  logout(): Promise<void> {
    return native().logout();
  },

  /** Add or change tags; send to `tags` from your server to reach everyone who has them. */
  addTags(tags: Record<string, TagValue>): Promise<void> {
    return native().addTags(tags);
  },

  removeTags(keys: string[]): Promise<void> {
    return native().removeTags(keys);
  },

  /** A screen the user reached, credited to the push they tapped while its window is open. */
  screen(name: string): Promise<void> {
    return native().screen(name);
  },

  /** A named goal or event, credited to the push they tapped while its window is open. Resolves false when there is nothing to credit. */
  async track(name: string, properties?: Record<string, unknown>): Promise<boolean> {
    return (await native().track(name, properties ?? null)) === true;
  },

  /** Sends anything waiting. Call when the app comes to the foreground. */
  flush(): Promise<void> {
    return native().flush();
  },

  /** Notifications tapped while the app is running. Returns a function that stops listening. */
  onTap(listener: (tap: ZapiackTap) => void): () => void {
    const module = native();
    emitter ??= new NativeEventEmitter(module as never);
    const subscription = emitter.addListener(TAP_EVENT, listener);
    return () => subscription.remove();
  },

  /** The notification that opened the app, if it was opened by tapping one. Resolves it once. */
  initialTap(): Promise<ZapiackTap | null> {
    return native().initialTap();
  },
};

export default ZapiackPush;
