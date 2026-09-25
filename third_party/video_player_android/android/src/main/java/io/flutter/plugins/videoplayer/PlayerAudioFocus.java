// MeowWatch extension. SPDX-License-Identifier: AGPL-3.0-only

package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.os.Looper;
import androidx.annotation.NonNull;
import androidx.annotation.VisibleForTesting;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.Player;
import androidx.media3.common.audio.AudioFocusManager;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.ExoPlayer;

/** Owns one player's audio focus independently of ExoPlayer's queued playback-info events. */
@UnstableApi
final class PlayerAudioFocus implements AudioFocusManager.PlayerControl {
  private final ExoPlayer player;
  private final AudioFocusManager focusManager;
  private final VideoPlayerCallbacks events;
  private final boolean mixWithOthers;
  private boolean requireExplicitResume;
  private boolean resumeOnGain;
  private boolean disposed;
  private float userVolume = 1f;
  private float volumeMultiplier = 1f;
  private int interruptionVersion;

  interface FocusManagerFactory {
    AudioFocusManager create(AudioFocusManager.PlayerControl control);
  }

  PlayerAudioFocus(
      @NonNull Context context,
      @NonNull ExoPlayer player,
      @NonNull AudioAttributes attributes,
      boolean mixWithOthers,
      @NonNull VideoPlayerCallbacks events) {
    // Flutter's player is created and controlled on main; focus callbacks must use the same
    // looper because they call ExoPlayer's public API directly.
    this(
        player,
        attributes,
        mixWithOthers,
        events,
        control -> new AudioFocusManager(context, Looper.getMainLooper(), control));
  }

  @VisibleForTesting
  PlayerAudioFocus(
      @NonNull ExoPlayer player,
      @NonNull AudioAttributes attributes,
      boolean mixWithOthers,
      @NonNull VideoPlayerCallbacks events,
      @NonNull FocusManagerFactory focusManagerFactory) {
    this.player = player;
    this.events = events;
    this.mixWithOthers = mixWithOthers;
    focusManager = focusManagerFactory.create(this);
    focusManager.setAudioAttributes(mixWithOthers ? null : attributes);
  }

  void play() {
    if (disposed) {
      return;
    }
    // Request focus before allowing ExoPlayer to start. BUFFERING also covers an early Play
    // while prepare() still reports IDLE.
    int command = focusManager.updateAudioFocus(true, Player.STATE_BUFFERING);
    if (command == AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY) {
      resumeOnGain = false;
      player.play();
    } else if (command == AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK) {
      resumeOnGain = true;
      pauseAndReport();
    } else if (command == AudioFocusManager.PLAYER_COMMAND_DO_NOT_PLAY) {
      resumeOnGain = false;
      pauseAndReport();
    } else {
      resumeOnGain = false;
      pauseAndReport();
      throw new IllegalArgumentException("Unknown audio focus command: " + command);
    }
  }

  void pause() {
    if (disposed) {
      return;
    }
    interruptionVersion++;
    resumeOnGain = false;
    player.pause();
    focusManager.updateAudioFocus(false, Player.STATE_IDLE);
  }

  private void pauseAndReport() {
    player.pause();
    // While buffering, isPlaying may already be false and ExoPlayer emits no state-change event.
    events.onIsPlayingStateUpdate(false);
  }

  void setRequireExplicitResume(boolean required) {
    requireExplicitResume = required;
    if (required) {
      resumeOnGain = false;
    }
  }

  void setUserVolume(float volume) {
    userVolume = volume;
    player.setVolume(userVolume * volumeMultiplier);
  }

  int getInterruptionVersion() {
    return interruptionVersion;
  }

  void onPlaybackStopped() {
    if (!disposed) {
      interruptionVersion++;
      resumeOnGain = false;
      focusManager.updateAudioFocus(false, Player.STATE_IDLE);
    }
  }

  void release() {
    if (disposed) {
      return;
    }
    disposed = true;
    resumeOnGain = false;
    focusManager.release();
  }

  @Override
  public void setVolumeMultiplier(float multiplier) {
    if (!disposed) {
      volumeMultiplier = multiplier;
      player.setVolume(userVolume * multiplier);
    }
  }

  @Override
  public void executePlayerCommand(int command) {
    if (disposed || mixWithOthers) {
      return;
    }
    switch (command) {
      case AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK:
        interruptionVersion++;
        resumeOnGain = !requireExplicitResume && (player.getPlayWhenReady() || resumeOnGain);
        pauseAndReport();
        break;
      case AudioFocusManager.PLAYER_COMMAND_DO_NOT_PLAY:
        interruptionVersion++;
        resumeOnGain = false;
        pauseAndReport();
        break;
      case AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY:
        if (resumeOnGain) {
          resumeOnGain = false;
          player.play();
        }
        break;
      default:
        interruptionVersion++;
        resumeOnGain = false;
        pauseAndReport();
        throw new IllegalArgumentException("Unknown audio focus command: " + command);
    }
  }
}
