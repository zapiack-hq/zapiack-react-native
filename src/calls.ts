/**
 * Zapiack Voice & Video for React Native: join a room and send and receive audio and video.
 *
 * Your server creates the room and mints a token for each person (`POST /v1/calls/rooms`, `POST /v1/calls/tokens`) and hands it to
 * the app, so the API key never reaches the phone. The app joins with the token:
 *
 *     const call = new ZapiackCall({ getToken: () => fetch('https://my-server/call-token').then((r) => r.text()) });
 *     call.on('track', ({ identity, source, stream }) => show(identity, source, stream.toURL()));   // <RTCView streamURL=... />
 *     await call.join();
 *     await call.enableMicrophone();
 *     await call.enableCamera();
 *
 * What a person may send comes from their token: a listener can only receive. Needs `react-native-webrtc` and `mediasoup-client`
 * (both peer dependencies of this entry only; push and messaging do not need them).
 */
import { Device, types } from 'mediasoup-client';
import { MediaStream, mediaDevices, registerGlobals } from 'react-native-webrtc';
import type { MediaStreamTrack } from 'react-native-webrtc';
import { ZapiackRealtime, ZapiackRealtimeError } from './realtime';
import type { RealtimeEnv, RealtimeMessage } from './realtime';

/** Where sound plays. Wire it to `react-native-incall-manager` (see the README) so the earpiece, speaker and the phone's call mode work. */
export interface AudioSession {
  start(options: { media: 'audio' | 'video' }): void;
  stop(): void;
  setSpeaker(on: boolean): void;
}

type IceServer = { urls: string | string[]; username?: string; credential?: string };

export type CallRole = 'host' | 'speaker' | 'listener';
/** What a track is: a microphone, a camera, or a shared screen. */
export type TrackSource = 'audio' | 'video' | 'screen';

export interface CallOptions {
  /** Returns a call token from your server (`POST /v1/calls/tokens`). Called on every connect, so an expired one is replaced. */
  getToken: () => Promise<string>;
  /** Default `wss://rt.zapiack.com`. */
  url?: string;
  /** Send and receive over TCP only. For networks that block UDP. Default false. */
  forceTcp?: boolean;
  /** How often, in milliseconds, the client asks the server who is in the room and catches up on anything it missed. Default 30000. 0 turns it off. */
  resyncMs?: number;
  /** Sound routing and the phone's call mode. Started when the call is joined and stopped when it ends. */
  audioSession?: AudioSession;
  /** Which camera `enableCamera` opens first. Default `user` (the front one). */
  camera?: 'user' | 'environment';
}

export interface Peer {
  identity: string;
  role: CallRole;
}

/** Someone else's audio, video or screen. Give `stream.toURL()` to an `<RTCView streamURL={...} />`; audio plays by itself. */
export interface RemoteTrack {
  identity: string;
  source: TrackSource;
  track: MediaStreamTrack;
  stream: MediaStream;
  /** The sender's track id: the same one `trackEnded` and `paused` carry. */
  producerId: string;
}

export interface CallEvents {
  /** Someone's track arrived. */
  track: RemoteTrack;
  /** Someone stopped sending a track, or left. */
  trackEnded: { identity: string; source: TrackSource; producerId: string };
  /** Someone muted or unmuted a track. The track stays; what it carries is silence or a frozen picture. */
  paused: { identity: string; source: TrackSource; producerId: string; paused: boolean };
  peerJoined: Peer;
  peerLeft: { identity: string };
  /** The room was ended by your server. The call is already closed when this fires. */
  ended: { reason: string };
  /** A problem worth showing: a track that could not be played, or a refused request. */
  error: ZapiackRealtimeError;
}
export type CallState = 'idle' | 'joining' | 'joined' | 'reconnecting' | 'closed';

interface PeerInfo {
  identity: string;
  role: CallRole;
  producers: Array<{ id: string; kind: TrackSource; paused: boolean }>;
}
interface JoinReply {
  roomId: string;
  identity: string;
  routerRtpCapabilities: types.RtpCapabilities;
  iceServers: IceServer[];
  role: CallRole;
  peers: PeerInfo[];
}
interface TransportReply {
  id: string;
  iceParameters: types.IceParameters;
  iceCandidates: types.IceCandidate[];
  dtlsParameters: types.DtlsParameters;
}
interface ConsumeReply {
  id: string;
  producerId: string;
  kind: 'audio' | 'video';
  source: TrackSource;
  identity: string;
  rtpParameters: types.RtpParameters;
}

type Listener<K extends keyof CallEvents> = (e: CallEvents[K]) => void;

/** What can be swapped in a test. */
export interface CallEnv {
  realtime?: ZapiackRealtime;
  realtimeEnv?: RealtimeEnv;
  device?: () => Device;
  getUserMedia?: (c: Record<string, unknown>) => Promise<MediaStream>;
  getDisplayMedia?: () => Promise<MediaStream>;
  newStream?: (tracks: MediaStreamTrack[]) => MediaStream;
  setTimeout?: (fn: () => void, ms: number) => unknown;
  clearTimeout?: (id: unknown) => void;
}

export class ZapiackCall {
  private readonly rt: ZapiackRealtime;
  private readonly device: Device;
  private readonly listeners = new Map<keyof CallEvents, Set<Listener<keyof CallEvents>>>();
  private sendT: types.Transport | null = null;
  private recvT: types.Transport | null = null;
  private readonly producers = new Map<TrackSource, types.Producer>();
  /** Everything being received, by the sender's track id. */
  private readonly consumers = new Map<string, { consumer: types.Consumer; identity: string; source: TrackSource }>();
  private readonly peers = new Map<string, Peer>();
  private joinedReply: JoinReply | null = null;
  private roomChannel: string | null = null;
  private stopRoom: (() => void) | null = null;
  private stopState: (() => void) | null = null;
  private _state: CallState = 'idle';
  /** Tracks being fetched right now, so two events for the same track do not make two consumers. */
  private readonly fetching = new Set<string>();
  private wasConnected = false;
  private resyncing = false;
  private resyncTimer: ReturnType<typeof setInterval> | null = null;
  private facing: 'user' | 'environment';
  private speaker = false;
  /** A transport that went `disconnected` gets a few seconds to recover by itself before its path is restarted. */
  private readonly lapse = new Map<string, unknown>();

  constructor(
    private readonly options: CallOptions,
    private readonly env: CallEnv = {},
  ) {
    this.facing = options?.camera ?? 'user';
    if (typeof options?.getToken !== 'function') throw new ZapiackRealtimeError('getToken is required: a function that asks your server for a call token.');
    this.rt = env.realtime ?? new ZapiackRealtime({ getToken: options.getToken, url: options.url }, env.realtimeEnv);
    if (!env.device && typeof (globalThis as { RTCPeerConnection?: unknown }).RTCPeerConnection === 'undefined') registerGlobals();
    this.device = env.device ? env.device() : new Device({ handlerName: 'ReactNative106' });
  }

  get state(): CallState {
    return this._state;
  }
  /** What this person may do in the room: `listener` can only receive. */
  get role(): CallRole | null {
    return this.joinedReply?.role ?? null;
  }
  get roomId(): string | null {
    return this.joinedReply?.roomId ?? null;
  }
  /** Who else is in the room now. */
  get members(): Peer[] {
    return [...this.peers.values()];
  }
  /** The tracks this person is sending now. */
  get sending(): TrackSource[] {
    return [...this.producers.keys()];
  }

  on<K extends keyof CallEvents>(event: K, fn: Listener<K>): () => void {
    let set = this.listeners.get(event);
    if (!set) this.listeners.set(event, (set = new Set()));
    set.add(fn as Listener<keyof CallEvents>);
    return () => set!.delete(fn as Listener<keyof CallEvents>);
  }

  private emit<K extends keyof CallEvents>(event: K, data: CallEvents[K]) {
    for (const fn of [...(this.listeners.get(event) ?? [])]) {
      try {
        (fn as Listener<K>)(data);
      } catch {
        /* a handler's bug must not stop the call */
      }
    }
  }

  /** Connects, joins the room the token is for, and starts receiving what the others are sending. */
  async join(): Promise<{ role: CallRole; roomId: string; members: Peer[] }> {
    if (this._state === 'joined') return { role: this.joinedReply!.role, roomId: this.joinedReply!.roomId, members: this.members };
    this._state = 'joining';
    try {
      await this.rt.connect();
      const reply = await this.rt.request<JoinReply>('media.join', {});
      this.joinedReply = reply;
      if (!this.device.loaded) await this.device.load({ routerRtpCapabilities: reply.routerRtpCapabilities });
      this.roomChannel = `call:${reply.roomId}`;
      this.stopRoom = this.rt.subscribe(this.roomChannel, (m) => this.onRoomEvent(m));
      this.stopState = this.rt.onState((s) => void this.onLine(s));
      this.wasConnected = true;
      this.options.audioSession?.start({ media: 'video' });
      if (this.speaker) this.options.audioSession?.setSpeaker(true);
      // Someone may have started sending between the answer and the subscribe. Joining again is harmless and returns who is here now.
      const fresh = await this.rt.request<JoinReply>('media.join', {});
      await this.reconcile(fresh.peers);
      this._state = 'joined';
      this.startResync();
      return { role: reply.role, roomId: reply.roomId, members: this.members };
    } catch (e) {
      await this.teardown();
      this._state = 'closed';
      throw e;
    }
  }

  /** Turns the microphone on and sends it. Pass your own track to send something else. */
  async enableMicrophone(track?: MediaStreamTrack): Promise<MediaStreamTrack> {
    const t = track ?? (await this.userMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } })).getAudioTracks()[0];
    if (!t) throw new ZapiackRealtimeError('No microphone was found.');
    await this.send('audio', t);
    return t;
  }

  /** Turns the camera on and sends it. Opens the camera set by the `camera` option, front by default. */
  async enableCamera(track?: MediaStreamTrack): Promise<MediaStreamTrack> {
    const t = track ?? (await this.userMedia({ video: { facingMode: this.facing, width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } } })).getVideoTracks()[0];
    if (!t) throw new ZapiackRealtimeError('No camera was found.');
    await this.send('video', t);
    return t;
  }

  /**
   * Shares the phone's screen. Android needs a foreground service for screen capture and iOS needs a broadcast extension: see
   * react-native-webrtc's screen sharing guide. Stops by itself when the person stops sharing.
   */
  async shareScreen(track?: MediaStreamTrack): Promise<MediaStreamTrack> {
    const t = track ?? (await this.displayMedia()).getVideoTracks()[0];
    if (!t) throw new ZapiackRealtimeError('No screen was chosen.');
    (t as unknown as { addEventListener(e: 'ended', fn: () => void): void }).addEventListener('ended', () => void this.stop('screen'));
    await this.send('screen', t);
    return t;
  }

  /** Mutes or unmutes what is being sent. Nothing is sent while muted, and the others are told. */
  async setMuted(source: TrackSource, muted: boolean): Promise<void> {
    const p = this.producers.get(source);
    if (!p) return;
    if (muted) p.pause();
    else p.resume();
    await this.rt.request(muted ? 'media.pauseProducer' : 'media.resumeProducer', { producerId: p.id });
  }

  /** Flips between the front and back camera while the camera is on, without interrupting what is being sent. */
  switchCamera(): void {
    const p = this.producers.get('video');
    if (!p?.track) throw new ZapiackRealtimeError('The camera is not on.');
    (p.track as unknown as { _switchCamera(): void })._switchCamera();
    this.facing = this.facing === 'user' ? 'environment' : 'user';
  }

  /** Plays sound through the loudspeaker (true) or the earpiece (false). Needs an `audioSession` option; remembered across a reconnect. */
  setSpeaker(on: boolean): void {
    this.speaker = on;
    this.options.audioSession?.setSpeaker(on);
  }

  isMuted(source: TrackSource): boolean {
    return this.producers.get(source)?.paused ?? false;
  }

  /** Stops sending a track and lets go of the device (the camera light goes off). */
  async stop(source: TrackSource): Promise<void> {
    const p = this.producers.get(source);
    if (!p) return;
    this.producers.delete(source);
    const track = p.track;
    p.close();
    track?.stop();
    await this.rt.request('media.closeProducer', { producerId: p.id }).catch(() => undefined);
  }

  /**
   * What is arriving now, one entry per track being received: how many bytes and packets, how many were lost, and the jitter in
   * seconds. For a quality indicator, or to see that media is really flowing.
   */
  async stats(): Promise<Array<{ identity: string; source: TrackSource; bytesReceived: number; packetsReceived: number; packetsLost: number; jitter: number }>> {
    const out = [];
    for (const [, c] of this.consumers) {
      const report = await c.consumer.getStats();
      let bytes = 0, packets = 0, lost = 0, jitter = 0;
      report.forEach((r: Record<string, unknown>) => {
        if (r['type'] !== 'inbound-rtp') return;
        bytes += Number(r['bytesReceived'] ?? 0);
        packets += Number(r['packetsReceived'] ?? 0);
        lost += Number(r['packetsLost'] ?? 0);
        jitter = Math.max(jitter, Number(r['jitter'] ?? 0));
      });
      out.push({ identity: c.identity, source: c.source, bytesReceived: bytes, packetsReceived: packets, packetsLost: lost, jitter });
    }
    return out;
  }

  /** Leaves the room and lets go of the camera, the microphone and the connection. */
  async leave(): Promise<void> {
    if (this._state === 'closed' || this._state === 'idle') return;
    await this.rt.request('media.leave', {}).catch(() => undefined);
    await this.teardown();
    this._state = 'closed';
  }

  // ───────────────────────────── sending

  private userMedia(c: Record<string, unknown>) {
    const fn = this.env.getUserMedia ?? ((x: Record<string, unknown>) => mediaDevices.getUserMedia(x as never));
    return fn(c);
  }
  private displayMedia() {
    const fn = this.env.getDisplayMedia ?? (() => mediaDevices.getDisplayMedia({}));
    return fn();
  }

  private async transport(direction: 'send' | 'recv'): Promise<types.Transport> {
    const held = direction === 'send' ? this.sendT : this.recvT;
    if (held && !held.closed) return held;
    const info = await this.rt.request<TransportReply>('media.createTransport', { direction });
    const opts = { ...info, iceServers: this.joinedReply?.iceServers ?? [], iceTransportPolicy: (this.options.forceTcp ? 'relay' : 'all') as 'relay' | 'all' };
    const t = direction === 'send' ? this.device.createSendTransport(opts) : this.device.createRecvTransport(opts);
    t.on('connect', ({ dtlsParameters }, ok, fail) => {
      this.rt.request('media.connectTransport', { transportId: t.id, dtlsParameters }).then(() => ok(), fail);
    });
    if (direction === 'send') {
      t.on('produce', ({ kind, rtpParameters, appData }, ok, fail) => {
        const source = ((appData as { source?: TrackSource }).source ?? kind) as TrackSource;
        this.rt.request<{ id: string }>('media.produce', { transportId: t.id, kind: source, rtpParameters }).then((r) => ok({ id: r.id }), fail);
      });
    }
    t.on('connectionstatechange', (s) => {
      // A phone moving from Wi-Fi to mobile data goes `disconnected` first. Most of the time it recovers by itself; when it has
      // not in a few seconds, or has failed outright, the path is restarted with fresh ICE parameters from the server.
      const timers = { set: this.env.setTimeout ?? ((fn: () => void, ms: number) => setTimeout(fn, ms)), clear: this.env.clearTimeout ?? ((id: unknown) => clearTimeout(id as ReturnType<typeof setTimeout>)) };
      const pending = this.lapse.get(t.id);
      if (pending !== undefined) {
        timers.clear(pending);
        this.lapse.delete(t.id);
      }
      if (s === 'failed') void this.restartIce(t);
      else if (s === 'disconnected') {
        this.lapse.set(t.id, timers.set(() => {
          this.lapse.delete(t.id);
          if (!t.closed) void this.restartIce(t);
        }, 4000));
      }
    });
    if (direction === 'send') this.sendT = t;
    else this.recvT = t;
    return t;
  }

  private async restartIce(t: types.Transport) {
    try {
      const { iceParameters } = await this.rt.request<{ iceParameters: types.IceParameters }>('media.restartIce', { transportId: t.id });
      await t.restartIce({ iceParameters });
    } catch (e) {
      this.emit('error', e instanceof ZapiackRealtimeError ? e : new ZapiackRealtimeError(String(e)));
    }
  }

  private async send(source: TrackSource, track: MediaStreamTrack) {
    if (this._state !== 'joined') throw new ZapiackRealtimeError('Join the call first.');
    if (this.joinedReply?.role === 'listener') throw new ZapiackRealtimeError('Your role in this call can only listen.', 0, 'forbidden');
    // Sending the same thing again replaces it: the old track is closed first.
    if (this.producers.has(source)) await this.stop(source);
    const t = await this.transport('send');
    const encodings: types.RtpEncodingParameters[] = source === 'audio' ? [{ maxBitrate: 64_000 }] : source === 'screen' ? [{ maxBitrate: 2_500_000 }] : [{ maxBitrate: 1_200_000 }];
    const producer = await t.produce({ track: track as unknown as types.Producer['track'], encodings, appData: { source }, ...(source === 'audio' ? { codecOptions: { opusDtx: true, opusFec: true } } : {}) });
    producer.on('trackended', () => void this.stop(source));
    this.producers.set(source, producer);
  }

  // ───────────────────────────── receiving

  private async reconcile(peers: PeerInfo[]) {
    const here = new Set(peers.map((p) => p.identity));
    for (const p of peers) {
      if (!this.peers.has(p.identity)) {
        this.peers.set(p.identity, { identity: p.identity, role: p.role });
        this.emit('peerJoined', { identity: p.identity, role: p.role });
      }
    }
    for (const id of [...this.peers.keys()]) {
      if (!here.has(id)) {
        this.peers.delete(id);
        this.dropFrom(id);
        this.emit('peerLeft', { identity: id });
      }
    }
    const live = new Set(peers.flatMap((p) => p.producers.map((x) => x.id)));
    for (const [producerId, c] of [...this.consumers]) {
      if (!live.has(producerId)) this.endTrack(producerId, c.identity, c.source);
    }
    for (const p of peers) for (const pr of p.producers) await this.consume(pr.id, p.identity, pr.kind, pr.paused);
  }

  private async consume(producerId: string, identity: string, kind: TrackSource, paused = false) {
    if (this.consumers.has(producerId) || this.fetching.has(producerId)) return;
    this.fetching.add(producerId);
    try {
      const t = await this.transport('recv');
      const r = await this.rt.request<ConsumeReply>('media.consume', { producerId, rtpCapabilities: this.device.rtpCapabilities });
      const consumer = await t.consume({ id: r.id, producerId: r.producerId, kind: r.kind, rtpParameters: r.rtpParameters, appData: { source: r.source } });
      this.consumers.set(producerId, { consumer, identity: r.identity, source: r.source });
      // The server made it paused so nothing is lost before the player is ready; it starts now.
      await this.rt.request('media.resumeConsumer', { consumerId: consumer.id });
      const stream = this.env.newStream ? this.env.newStream([consumer.track as unknown as MediaStreamTrack]) : new MediaStream([consumer.track as unknown as MediaStreamTrack]);
      this.emit('track', { identity: r.identity, source: r.source, track: consumer.track as unknown as MediaStreamTrack, stream, producerId });
      if (paused) this.emit('paused', { identity: r.identity, source: r.source, producerId, paused: true });
      consumer.on('transportclose', () => this.endTrack(producerId, r.identity, r.source));
    } catch (e) {
      this.emit('error', e instanceof ZapiackRealtimeError ? e : new ZapiackRealtimeError(`Could not play ${identity}'s ${kind}: ${e instanceof Error ? e.message : String(e)}`));
    } finally {
      this.fetching.delete(producerId);
    }
  }

  private endTrack(producerId: string, identity: string, source: TrackSource) {
    const c = this.consumers.get(producerId);
    if (!c) return;
    this.consumers.delete(producerId);
    c.consumer.close();
    this.emit('trackEnded', { identity, source, producerId });
  }

  private dropFrom(identity: string) {
    for (const [producerId, c] of [...this.consumers]) if (c.identity === identity) this.endTrack(producerId, c.identity, c.source);
  }

  private onRoomEvent(m: RealtimeMessage) {
    const d = (m.data ?? {}) as Record<string, any>;
    switch (m.event) {
      case 'peerJoined':
        if (d['identity'] && d['identity'] !== this.identity() && !this.peers.has(d['identity'])) {
          this.peers.set(d['identity'], { identity: d['identity'], role: d['role'] });
          this.emit('peerJoined', { identity: d['identity'], role: d['role'] });
        }
        return;
      case 'peerLeft':
        if (this.peers.delete(d['identity'])) {
          this.dropFrom(d['identity']);
          this.emit('peerLeft', { identity: d['identity'] });
        }
        return;
      case 'newProducer':
        if (d['identity'] !== this.identity()) void this.consume(d['producerId'], d['identity'], d['kind']);
        return;
      case 'producerClosed': {
        const c = this.consumers.get(d['producerId']);
        if (c) this.endTrack(d['producerId'], c.identity, c.source);
        return;
      }
      case 'producerPaused': {
        const c = this.consumers.get(d['producerId']);
        if (c) this.emit('paused', { identity: c.identity, source: c.source, producerId: d['producerId'], paused: d['paused'] === true });
        return;
      }
      case 'roomEnded':
      case 'roomEnding':
        void this.teardown().then(() => {
          this._state = 'closed';
          this.emit('ended', { reason: String(d['reason'] ?? 'ended') });
        });
        return;
    }
  }

  /** Who this person is in the room, as the server knows them: events about this name are about us. */
  private identity(): string | null {
    return this.joinedReply?.identity ?? null;
  }

  // ───────────────────────────── the line coming and going

  /**
   * Room events travel over best-effort publish and subscribe, so a client does not rely on every one arriving: now and then it asks the
   * server who is in the room and what they are sending, and catches up on anything it missed.
   */
  private startResync() {
    const every = this.options.resyncMs ?? 30_000;
    if (this.resyncTimer || every <= 0) return;
    this.resyncTimer = setInterval(() => void this.resync(), every);
  }

  private async resync() {
    if (this._state !== 'joined' || this.resyncing) return;
    this.resyncing = true;
    try {
      const fresh = await this.rt.request<JoinReply>('media.join', {});
      if (this._state === 'joined') await this.reconcile(fresh.peers);
    } catch {
      /* a failed question is asked again next time; a line that is really gone is handled by onLine */
    } finally {
      this.resyncing = false;
    }
  }

  /** The socket dropped and came back: take the place in the room again and see what changed while away. */
  private async onLine(s: string) {
    if (s === 'reconnecting' && this._state === 'joined') this._state = 'reconnecting';
    if (s === 'closed' && this._state !== 'closed' && this._state !== 'idle') {
      await this.teardown();
      this._state = 'closed';
      this.emit('ended', { reason: 'disconnected' });
      return;
    }
    if (s !== 'connected' || !this.wasConnected || this._state !== 'reconnecting' || this.resyncing) return;
    this.resyncing = true;
    try {
      const fresh = await this.rt.request<JoinReply>('media.join', {});
      this._state = 'joined';
      for (const t of [this.sendT, this.recvT]) if (t && !t.closed) await this.restartIce(t);
      await this.reconcile(fresh.peers);
    } catch (e) {
      // The server no longer has this person (they were away too long): the call is over for them.
      await this.teardown();
      this._state = 'closed';
      this.emit('ended', { reason: e instanceof ZapiackRealtimeError && e.reason ? e.reason : 'rejoin_failed' });
    } finally {
      this.resyncing = false;
    }
  }

  private async teardown() {
    if (this.resyncTimer) clearInterval(this.resyncTimer);
    this.resyncTimer = null;
    const clear = this.env.clearTimeout ?? ((id: unknown) => clearTimeout(id as ReturnType<typeof setTimeout>));
    for (const id of this.lapse.values()) clear(id);
    this.lapse.clear();
    this.options.audioSession?.stop();
    this.stopState?.();
    this.stopRoom?.();
    this.stopState = this.stopRoom = null;
    for (const p of this.producers.values()) {
      p.track?.stop();
      p.close();
    }
    this.producers.clear();
    for (const c of this.consumers.values()) c.consumer.close();
    this.consumers.clear();
    this.sendT?.close();
    this.recvT?.close();
    this.sendT = this.recvT = null;
    this.peers.clear();
    this.rt.disconnect();
  }
}
