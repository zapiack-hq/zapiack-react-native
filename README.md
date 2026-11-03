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

## Maintaining

The iOS code in this package is copied from the iOS library: run `npm run sync-ios` after changing it (it also runs before publishing).

## Tests

```
npm test
```
