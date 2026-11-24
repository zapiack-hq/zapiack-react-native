# Changelog

All notable changes to @zapiack/react-native are listed here. Versions follow [semantic versioning](https://semver.org).

## 0.2.0

- Realtime: `ZapiackRealtime` for live messages over one WebSocket (pure JavaScript): channels, presence, signals, resume after a dropped connection.
- Calls: `ZapiackCall` from `@zapiack/react-native/calls`, voice and video for one-to-one and group calls over the same connection, with camera switching, speaker routing and recovery when the phone changes network. Needs `react-native-webrtc` and `mediasoup-client`.

## 0.1.0

First release.

Push for React Native on iOS and Android, as a thin bridge over the native libraries.
