package com.meowwatch.audio_focus_probe;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Process;
import android.os.SystemClock;
import android.util.Log;
import org.json.JSONException;
import org.json.JSONObject;

/** A bounded, independent focus owner. It never launches or instruments MeowWatch. */
public final class FocusService extends Service {
    private static final String TAG = "MWFocusProbe";
    private static final String WARM_TAG = "MWFocusWarm";
    private static final int WARM_EXPIRY_MS = 15000;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private AudioManager audio;
    private AudioFocusRequest request;
    private String nonce;
    private int sequence;
    private int gain = AudioManager.AUDIOFOCUS_GAIN;
    private long requestStartedElapsed;
    private boolean warmArmed;

    @Override public IBinder onBind(Intent intent) { return null; }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) { stopSelf(); return START_NOT_STICKY; }
        String incoming = intent.getStringExtra("nonce");
        if (incoming == null || !incoming.matches("[a-f0-9]{32}")) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if ("release".equals(intent.getAction())) {
            if (incoming.equals(nonce)) release("released");
            else stopSelf();
            return START_NOT_STICKY;
        }
        if ("warm".equals(intent.getAction())) {
            if (nonce != null || request != null
                    || !"transient".equals(intent.getStringExtra("mode"))
                    || intent.getIntExtra("autoReleaseMs", 0) != 350) {
                stopSelf();
                return START_NOT_STICKY;
            }
            nonce = incoming;
            gain = AudioManager.AUDIOFOCUS_GAIN_TRANSIENT;
            warmArmed = true;
            startFocusNotification(true);
            warmEvent("armed");
            handler.postDelayed(new Runnable() {
                @Override public void run() {
                    warmEvent("expired");
                    release("warm-expired");
                }
            }, WARM_EXPIRY_MS);
            return START_NOT_STICKY;
        }
        if (!"acquire".equals(intent.getAction())) return START_NOT_STICKY;
        boolean requireWarm = intent.getBooleanExtra("requireWarm", false);
        if (requireWarm ? !warmArmed || !incoming.equals(nonce) : nonce != null) {
            stopSelf();
            return START_NOT_STICKY;
        }
        String mode = intent.getStringExtra("mode");
        if (mode != null && !"permanent".equals(mode) && !"transient".equals(mode)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        gain = "transient".equals(mode)
            ? AudioManager.AUDIOFOCUS_GAIN_TRANSIENT : AudioManager.AUDIOFOCUS_GAIN;
        int autoReleaseMs = intent.getIntExtra("autoReleaseMs", 0);
        if (autoReleaseMs != 0 && (gain != AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                || autoReleaseMs < 200 || autoReleaseMs > 500)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if (requireWarm && (gain != AudioManager.AUDIOFOCUS_GAIN_TRANSIENT || autoReleaseMs != 350)) {
            stopSelf();
            return START_NOT_STICKY;
        }
        if (requireWarm) {
            warmArmed = false;
            handler.removeCallbacksAndMessages(null);
        } else {
            nonce = incoming;
            startFocusNotification(false);
        }
        audio = getSystemService(AudioManager.class);
        request = new AudioFocusRequest.Builder(gain)
            .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener(new AudioManager.OnAudioFocusChangeListener() {
                @Override public void onAudioFocusChange(int change) {
                    event("focus-change", change);
                }
            }, handler).build();
        requestStartedElapsed = SystemClock.elapsedRealtime();
        int result = audio.requestAudioFocus(request);
        event("requested", result);
        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) release("not-granted");
        else handler.postDelayed(new Runnable() {
            @Override public void run() { release("watchdog-expired"); }
        }, 120000);
        if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED && autoReleaseMs != 0) {
            handler.postDelayed(new Runnable() {
                @Override public void run() { release("released"); }
            }, autoReleaseMs);
        }
        return START_NOT_STICKY;
    }

    private void startFocusNotification(boolean warming) {
        NotificationManager notifications = getSystemService(NotificationManager.class);
        notifications.createNotificationChannel(new NotificationChannel(
            "focus-proof", "Temporary audio focus acceptance", NotificationManager.IMPORTANCE_MIN));
        Notification notification = new Notification.Builder(this, "focus-proof")
            .setContentTitle(warming ? "Preparing audio focus probe" : "Audio focus acceptance in progress")
            .setContentText(warming ? "Preparing focus probe; automatically ends within 15 seconds."
                                    : "Temporary test service; automatically ends within 120 seconds.")
            .setSmallIcon(android.R.drawable.ic_media_pause).setOngoing(true).build();
        startForeground(71, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
    }

    private void warmEvent(String name) {
        try {
            JSONObject value = new JSONObject();
            value.put("protocol", 1).put("nonce", nonce).put("event", name)
                .put("pid", Process.myPid()).put("uid", Process.myUid())
                .put("gain", gain).put("autoReleaseMs", 350)
                .put("elapsedRealtimeMs", SystemClock.elapsedRealtime());
            Log.i(WARM_TAG, value.toString());
        } catch (JSONException impossible) { throw new IllegalStateException(impossible); }
    }

    private void event(String name, int result) {
        try {
            JSONObject value = new JSONObject();
            value.put("protocol", 2).put("nonce", nonce).put("sequence", ++sequence)
                .put("event", name).put("result", result).put("gain", gain)
                .put("pid", Process.myPid()).put("uid", Process.myUid())
                .put("requestStartedElapsedRealtimeMs", requestStartedElapsed)
                .put("elapsedRealtimeMs", SystemClock.elapsedRealtime());
            Log.i(TAG, value.toString());
        } catch (JSONException impossible) { throw new IllegalStateException(impossible); }
    }

    private void release(String reason) {
        handler.removeCallbacksAndMessages(null);
        warmArmed = false;
        if (request != null) {
            int result = audio.abandonAudioFocusRequest(request);
            request = null;
            event(reason, result);
        }
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    @Override public void onDestroy() {
        if (request != null) release("destroyed");
        handler.removeCallbacksAndMessages(null);
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
}
