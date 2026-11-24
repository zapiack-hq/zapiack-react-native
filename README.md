# @zapiack/react-native

The one Zapiack package for React Native apps. Push notifications are in it today, and new Zapiack products arrive in the same package.

## Push

Registers the device, shows pushes with pictures and buttons, reports taps, and
follows what the person does next, so you can see which pushes bring people back.

Android 5.0+ and iOS 13+, React Native 0.71+. It has native code, so it does not run in Expo Go: use a development build.

```bash
npm install @zapiack/react-native
cd ios && pod install
```

## Use it

```ts
import { ZapiackPush } from '@zapiack/react-native';

await ZapiackPush.configure({
  appKey: 'pk_…',
  appGroup: 'group.com.example.app', // iOS only: see below
});

// Ask when it makes sense for your users, for example after a tap on a button.
const allowed = await ZapiackPush.requestPermission();

const stop = ZapiackPush.onTap((tap) => {
  // tap.link, tap.actionId (the button), tap.event
});
const opened = await ZapiackPush.initialTap(); // the push that started the app, if any
```

Link a device to your user and group devices with tags:

```ts
await ZapiackPush.login('user_123');
await ZapiackPush.logout();
await ZapiackPush.addTags({ plan: 'pro' });
```

Follow what happens after a tap. Both are credited to the push only for a short window after it was tapped:

```ts
await ZapiackPush.screen('OrderDetails');
await ZapiackPush.track('purchase', { total: 49 });
```

## Android

Firebase Cloud Messaging has to be set up as in any Android app (`google-services.json` and the Google services plugin). The
package adds its own Firebase service. If another library also registers one, such as `@react-native-firebase/messaging`, only one
of them receives a push: call `ZapiackMessagingService.handle` from yours, as described in the Android library's README.

## iOS

1. In Xcode, turn on **Push Notifications** and **Background Modes → Remote notifications** for the app target.
2. Add an **App Group** to the app target, and use its name as `appGroup`.
3. Add a **Notification Service Extension** target with the same App Group, and make its class a subclass of
   `ZapiackNotificationService` from the Zapiack iOS package (`ZapiackNotificationExtension`). The extension reports that a push
   arrived and shows its picture and buttons. Without it, pushes still show, with no arrival report, picture or buttons.
4. React Native does not pass the push address on, so forward it from `AppDelegate`:

```objc
#import <zapiack_react_native/zapiack_react_native-Swift.h>

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
  [ZapiackPushModule didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}
```

## Realtime

Live messages over one WebSocket: chat, live updates, presence, and signalling for calls. It is separate from push; use either or both.

Your app never holds an API key. Your **server** asks Zapiack for a short-lived token for the signed-in user (the key needs the **Realtime** scope, or no scope limits), and hands it to the app:

```bash
curl -X POST https://api.zapiack.com/v1/realtime/tokens \
  -H "Authorization: Bearer $ZAPIACK_API_KEY" -H "Content-Type: application/json" \
  -d '{"userId":"user_42","capabilities":{"chat:*":["subscribe","publish","presence"]}}'
# → { "token": "eyJ…", "expiresAt": "…", "url": "wss://rt.zapiack.com/?token=eyJ…" }
```

`capabilities` says what that user may do on which channels (`*` matches anything): `subscribe`, `publish`, `presence`, `history`, `signal`. Tokens last an hour unless you ask for less (`ttlSeconds`, at most a day).

In your app (plain JavaScript, no native setup):

```ts
import { ZapiackRealtime } from '@zapiack/react-native';

const rt = new ZapiackRealtime({
  // Ask YOUR server for a token. Called on every connect, so an expired token is replaced.
  getToken: () => fetch('https://your.server/realtime-token').then((r) => r.text()),
});
await rt.connect();

const stop = rt.subscribe('chat:room-1', (m) => console.log(m.from, m.data));
await rt.publish('chat:room-1', { text: 'hi' }, { persist: true }); // resolves when the server confirms

const here = rt.presence('chat:room-1');
here.enter({ name: 'Ann' });
here.onChange(({ action, member }) => console.log(action, member.user));
rt.signal('call-7', otherConnectionId, 'offer', { sdp }); // to one connection
rt.onError((e) => console.warn(e.code, e.message));
```

- **Reconnects by itself** with a growing, jittered pause, fetches a fresh token each time, re-joins every channel and replays what it missed since the last message it saw (publish with `persist` to make a message replayable). Messages already seen are not repeated.
- **Sends made while offline** wait (up to 100) and go out in order once the line is back.
- A message that cannot be replayed because the client was away longer than the project's retention is reported as an error with code 410: reload that channel's history over REST.
- The project can refuse a client for good (Realtime switched off, or the connection was removed in the dashboard). Then `connect` fails with code 403 and it does not retry.

## Voice and video calls

Calls are a separate entry, so apps that only use push or messaging never load WebRTC.

```
npm install react-native-webrtc mediasoup-client react-native-incall-manager
```

Follow `react-native-webrtc`'s setup for your React Native version (camera and microphone permissions in `Info.plist` and `AndroidManifest.xml`, and the iOS pod install). Then:

```tsx
import { ZapiackCall } from '@zapiack/react-native/calls';
import InCallManager from 'react-native-incall-manager';
import { RTCView } from 'react-native-webrtc';

const call = new ZapiackCall({
  // Your server asks Zapiack for a token with POST /v1/calls/tokens (or starts the call with POST /v1/calls) and returns it here.
  getToken: () => fetch('https://my-server.example/call-token').then((r) => r.text()),
  // Earpiece, speaker and the phone's call mode.
  audioSession: {
    start: ({ media }) => InCallManager.start({ media }),
    stop: () => InCallManager.stop(),
    setSpeaker: (on) => InCallManager.setForceSpeakerphoneOn(on),
  },
});

call.on('track', ({ identity, source, stream }) => setStreams((s) => ({ ...s, [`${identity}:${source}`]: stream.toURL() })));
call.on('trackEnded', ({ identity, source }) => setStreams(({ [`${identity}:${source}`]: _gone, ...rest }) => rest));
call.on('ended', ({ reason }) => navigation.goBack());

await call.join();
await call.enableMicrophone();
await call.enableCamera();      // front camera; pass { camera: 'environment' } in the options for the back one
call.setSpeaker(true);
call.switchCamera();            // front <-> back, without interrupting the video
await call.setMuted('audio', true);
await call.leave();

// <RTCView streamURL={streams['ada:video']} style={{ flex: 1 }} objectFit="cover" />
```

A person who is a `listener` in the token can receive but never send. Audio from other people plays by itself; only video needs an `RTCView`.

A call also re-asks the server who is in the room every 30 seconds (`resyncMs` in the options, 0 turns it off), so an event that was missed costs seconds, not the rest of the call.

On a phone the network changes under a call (Wi-Fi to mobile data, a lift, a tunnel). The client waits a few seconds for the connection to recover, then restarts it with fresh parameters from the server, and if the socket itself dropped it rejoins the room and picks up who is there now.

**Not covered yet:** keeping a call alive in the background (iOS needs the `voip` background mode and CallKit; Android needs a foreground service) and screen sharing (`shareScreen` works once the Android foreground service and the iOS broadcast extension from `react-native-webrtc`'s guide are in place). Ringing a phone that is closed is done with push: see `POST /v1/calls`.

## Maintaining

The iOS code in this package is copied from the iOS library: run `npm run sync-ios` after changing it (it also runs before publishing).

## Tests

```
npm test
```
