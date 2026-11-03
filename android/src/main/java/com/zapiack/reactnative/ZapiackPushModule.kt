package com.zapiack.reactnative

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import com.zapiack.push.ZapiackPush
import com.zapiack.push.core.Tap

/** Connects the JavaScript API to the Android library. */
class ZapiackPushModule(private val reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext), ActivityEventListener {
    init {
        reactContext.addActivityEventListener(this)
    }

    override fun getName() = "ZapiackPush"

    @ReactMethod
    fun configure(options: ReadableMap, promise: Promise) {
        val key = options.getString("appKey")
        if (key == null || !key.startsWith("pk_")) return promise.reject("invalid_key", "The app key must start with pk_")
        val base = if (options.hasKey("baseUrl")) options.getString("baseUrl") else null
        if (base != null) ZapiackPush.configure(reactContext.applicationContext, key, base) else ZapiackPush.configure(reactContext.applicationContext, key)
        promise.resolve(null)
    }

    @ReactMethod
    fun requestPermission(promise: Promise) {
        val context = reactContext.applicationContext
        if (ZapiackPush.hasPermission(context)) {
            promise.resolve(true)
            return
        }
        val activity = reactContext.currentActivity
        if (Build.VERSION.SDK_INT < 33 || activity !is PermissionAwareActivity) {
            // Before Android 13 there is nothing to ask; without a React activity there is nobody to ask on.
            promise.resolve(false)
            return
        }
        // The answer has to come back through React's own activity, which is why the library's `requestPermission` is not used here.
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE, PermissionListener { code, _, results ->
            if (code != REQUEST_CODE) return@PermissionListener false
            ZapiackPush.onPermissionResult(code)
            promise.resolve(results.isNotEmpty() && results[0] == PackageManager.PERMISSION_GRANTED)
            true
        })
    }

    @ReactMethod fun installationId(promise: Promise) = promise.resolve(ZapiackPush.installationId)

    @ReactMethod fun login(userId: String, promise: Promise) { ZapiackPush.login(userId); promise.resolve(null) }

    @ReactMethod fun logout(promise: Promise) { ZapiackPush.logout(); promise.resolve(null) }

    @ReactMethod fun addTags(tags: ReadableMap, promise: Promise) { ZapiackPush.addTags(tags.toHashMap()); promise.resolve(null) }

    @ReactMethod fun removeTags(keys: ReadableArray, promise: Promise) { ZapiackPush.removeTags(keys.toArrayList().map { it.toString() }); promise.resolve(null) }

    @ReactMethod fun screen(name: String, promise: Promise) { ZapiackPush.screen(name); promise.resolve(null) }

    @ReactMethod
    fun track(name: String, properties: ReadableMap?, promise: Promise) {
        promise.resolve(ZapiackPush.track(name, properties?.toHashMap()))
    }

    @ReactMethod fun flush(promise: Promise) { ZapiackPush.flush(); promise.resolve(null) }

    /** The tap that opened the app. The library takes a tap out of the intent when it handles it, so a second call finds nothing. */
    @ReactMethod
    fun initialTap(promise: Promise) {
        promise.resolve(ZapiackPush.handleIntent(reactContext.currentActivity?.intent)?.toMap())
    }

    // Required by NativeEventEmitter.
    @ReactMethod fun addListener(eventName: String) = Unit
    @ReactMethod fun removeListeners(count: Int) = Unit

    override fun onNewIntent(intent: Intent) {
        val tap = ZapiackPush.handleIntent(intent) ?: return
        reactContext.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java).emit(TAP_EVENT, tap.toMap())
    }

    override fun onActivityResult(activity: android.app.Activity, requestCode: Int, resultCode: Int, data: Intent?) = Unit

    private fun Tap.toMap(): WritableMap = Arguments.createMap().apply {
        putString("messageId", messageId)
        putString("deliveryId", deliveryId)
        putString("sessionId", sessionId)
        putString("actionId", actionId)
        putString("event", event)
        putString("link", link)
    }

    companion object {
        private const val REQUEST_CODE = 7391
        private const val TAP_EVENT = "zapiackTap"
    }
}
