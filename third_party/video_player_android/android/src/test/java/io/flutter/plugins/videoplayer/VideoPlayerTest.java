// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.*;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.Tracks;
import androidx.media3.common.audio.AudioFocusManager;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import com.google.common.collect.ImmutableList;
import io.flutter.plugins.videoplayer.platformview.PlatformViewExoPlayerEventListener;
import io.flutter.view.TextureRegistry.SurfaceProducer;
import java.lang.reflect.Field;
import java.util.List;
import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnit;
import org.mockito.junit.MockitoRule;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.shadows.ShadowLooper;

/**
 * Unit tests for {@link VideoPlayer}.
 *
 * <p>This test suite <em>narrowly verifies</em> that {@link VideoPlayer} interfaces with the {@link
 * ExoPlayer} interface <em>exactly</em> as it did when the test suite was created. That is, if the
 * behavior changes, this test will need to change. However, this suite should catch bugs related to
 * <em>"this is a safe refactor with no behavior changes"</em>.
 *
 * <p>It's hypothetically possible to write better tests using {@link
 * androidx.media3.test.utils.FakeMediaSource}, but you really need a PhD in the Android media APIs
 * in order to figure out how to set everything up so the player "works".
 */
@RunWith(RobolectricTestRunner.class)
public final class VideoPlayerTest {
  private static final String FAKE_ASSET_URL = "https://flutter.dev/movie.mp4";
  private FakeVideoAsset fakeVideoAsset;

  @Mock private VideoPlayerCallbacks mockEvents;
  @Mock private ExoPlayer mockExoPlayer;
  @Captor private ArgumentCaptor<AudioAttributes> attributesCaptor;
  @Captor private ArgumentCaptor<Player.Listener> listenerCaptor;

  @Rule public MockitoRule initRule = MockitoJUnit.rule();

  /** A test subclass of {@link VideoPlayer} that exposes the abstract class for testing. */
  private final class TestVideoPlayer extends VideoPlayer {
    private TestVideoPlayer(
        @NonNull VideoPlayerCallbacks events,
        @NonNull MediaItem mediaItem,
        @NonNull VideoPlayerOptions options,
        @Nullable SurfaceProducer surfaceProducer,
        @NonNull ExoPlayerProvider exoPlayerProvider) {
      super(
          RuntimeEnvironment.getApplication(),
          events,
          mediaItem,
          options,
          surfaceProducer,
          exoPlayerProvider);
    }

    @NonNull
    @Override
    protected ExoPlayerEventListener createExoPlayerEventListener(
        @NonNull ExoPlayer exoPlayer, @Nullable SurfaceProducer surfaceProducer) {
      // Use platform view implementation for testing.
      return new PlatformViewExoPlayerEventListener(exoPlayer, mockEvents);
    }
  }

  @Before
  public void setUp() {
    fakeVideoAsset = new FakeVideoAsset(FAKE_ASSET_URL);
  }

  private VideoPlayer createVideoPlayer() {
    return createVideoPlayer(new VideoPlayerOptions());
  }

  private VideoPlayer createVideoPlayer(VideoPlayerOptions options) {
    return new TestVideoPlayer(
        mockEvents, fakeVideoAsset.getMediaItem(), options, null, () -> mockExoPlayer);
  }

  @Test
  public void transientFocusLossResumesLocalWithoutSuppressionEvent() {
    VideoPlayer videoPlayer = createVideoPlayer();
    when(mockExoPlayer.getPlayWhenReady()).thenReturn(true);
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    verify(mockExoPlayer).pause();
    verify(mockEvents).onIsPlayingStateUpdate(false);
    verify(mockExoPlayer).play();
    videoPlayer.dispose();
  }

  @Test
  public void togetherShortLossAndGainDoNotResumeWithoutSuppressionEvent() {
    VideoPlayer videoPlayer = createVideoPlayer();
    when(mockExoPlayer.getPlayWhenReady()).thenReturn(true);
    videoPlayer.setRequireExplicitResume(true);
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    assertFalse(mockExoPlayer.isPlaying());
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    verify(mockExoPlayer).pause();
    verify(mockEvents).onIsPlayingStateUpdate(false);
    verify(mockEvents, never()).onIsPlayingStateUpdate(true);
    verify(mockExoPlayer, never()).play();
    videoPlayer.setRequireExplicitResume(false);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    verify(mockExoPlayer, never()).play();
    videoPlayer.dispose();
  }

  @Test
  public void focusLossReportsExplicitInterruptionEvenWhenAlreadyNotPlaying() {
    VideoPlayer videoPlayer = createVideoPlayer();
    VideoPlayer.FocusInterruptionHandler handler = mock(VideoPlayer.FocusInterruptionHandler.class);
    videoPlayer.setFocusInterruptionHandler(handler);
    videoPlayer.setRequireExplicitResume(true);
    assertFalse(mockExoPlayer.isPlaying());
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();

    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_DO_NOT_PLAY);

    InOrder order = inOrder(mockExoPlayer, handler, mockEvents);
    order.verify(mockExoPlayer).pause();
    order.verify(handler).onInterrupted(1);
    order.verify(mockEvents).onIsPlayingStateUpdate(false);
    order.verify(mockExoPlayer).pause();
    order.verify(handler).onInterrupted(2);
    order.verify(mockEvents).onIsPlayingStateUpdate(false);
    verify(mockExoPlayer, never()).play();
    videoPlayer.dispose();
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    verifyNoMoreInteractions(handler);
  }

  @Test
  public void decoderBufferingManualPauseAndStopDoNotReportFocusInterruption() {
    VideoPlayer videoPlayer = createVideoPlayer();
    VideoPlayer.FocusInterruptionHandler handler = mock(VideoPlayer.FocusInterruptionHandler.class);
    videoPlayer.setFocusInterruptionHandler(handler);
    verify(mockExoPlayer, times(2)).addListener(listenerCaptor.capture());
    for (Player.Listener listener : listenerCaptor.getAllValues()) {
      listener.onPlaybackStateChanged(Player.STATE_BUFFERING);
      listener.onIsPlayingChanged(false);
    }
    videoPlayer.pause();
    videoPlayer.getAudioFocusForTesting().onPlaybackStopped();
    videoPlayer.getAudioFocusForTesting()
        .executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    verifyNoInteractions(handler);
    videoPlayer.dispose();
  }

  @Test
  public void delayedPlayFocusRequiresFreshPlayInTogetherButResumesLocal() {
    for (boolean together : new boolean[] {false, true}) {
      ExoPlayer player = mock(ExoPlayer.class);
      VideoPlayerCallbacks events = mock(VideoPlayerCallbacks.class);
      VideoPlayer.FocusInterruptionHandler handler = mock(VideoPlayer.FocusInterruptionHandler.class);
      AudioFocusManager manager = mock(AudioFocusManager.class);
      when(manager.updateAudioFocus(true, Player.STATE_BUFFERING))
          .thenReturn(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
      PlayerAudioFocus focus =
          new PlayerAudioFocus(
              player,
              new AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
              false,
              events,
              control -> manager);
      focus.setInterruptionHandler(handler);
      focus.setRequireExplicitResume(together);
      focus.play();
      focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);

      verify(handler).onInterrupted(1);
      verify(player).pause();
      verify(player, times(together ? 0 : 1)).play();
      focus.release();
    }
  }

  @Test
  public void enablingTogetherDuringLocalTransientCancelsDeferredResume() {
    VideoPlayer videoPlayer = createVideoPlayer();
    when(mockExoPlayer.getPlayWhenReady()).thenReturn(true);
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    videoPlayer.setRequireExplicitResume(true);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    verify(mockExoPlayer).pause();
    verify(mockExoPlayer, never()).play();
    videoPlayer.dispose();
  }

  @Test
  public void explicitPauseCancelsLocalResumeAndPermanentLossNeverResumes() {
    VideoPlayer videoPlayer = createVideoPlayer();
    when(mockExoPlayer.getPlayWhenReady()).thenReturn(true);
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    videoPlayer.pause();
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_DO_NOT_PLAY);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    verify(mockExoPlayer, never()).play();
    videoPlayer.dispose();
  }

  @Test
  public void permanentLossClearsPendingLocalResume() {
    VideoPlayer videoPlayer = createVideoPlayer();
    when(mockExoPlayer.getPlayWhenReady()).thenReturn(true);
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_DO_NOT_PLAY);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    verify(mockEvents, times(2)).onIsPlayingStateUpdate(false);
    verify(mockExoPlayer, never()).play();
    videoPlayer.dispose();
  }

  @Test
  public void duckRestoresUserVolumeWithoutPausing() {
    VideoPlayer videoPlayer = createVideoPlayer();
    videoPlayer.setVolume(0.5);
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    focus.setVolumeMultiplier(0.2f);
    focus.setVolumeMultiplier(1f);
    verify(mockExoPlayer).setVolume(0.1f);
    verify(mockExoPlayer, times(2)).setVolume(0.5f);
    verify(mockExoPlayer, never()).pause();
    videoPlayer.dispose();
  }

  @Test
  public void mixWithOthersIgnoresFocusCommands() {
    VideoPlayerOptions options = new VideoPlayerOptions();
    options.mixWithOthers = true;
    VideoPlayer videoPlayer = createVideoPlayer(options);
    VideoPlayer.FocusInterruptionHandler handler = mock(VideoPlayer.FocusInterruptionHandler.class);
    videoPlayer.setFocusInterruptionHandler(handler);
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_DO_NOT_PLAY);
    verify(mockExoPlayer, never()).pause();
    verifyNoInteractions(handler);
    videoPlayer.dispose();
  }

  @Test
  public void unknownFocusCommandPausesBeforeReportingError() {
    VideoPlayer videoPlayer = createVideoPlayer();
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    assertThrows(IllegalArgumentException.class, () -> focus.executePlayerCommand(99));
    verify(mockExoPlayer).pause();
    verify(mockEvents).onIsPlayingStateUpdate(false);
    videoPlayer.dispose();
  }

  @Test
  public void deniedFocusReportsPauseBeforePlayWithoutListenerEvent() {
    AudioFocusManager focusManager = mock(AudioFocusManager.class);
    when(focusManager.updateAudioFocus(true, Player.STATE_BUFFERING))
        .thenReturn(AudioFocusManager.PLAYER_COMMAND_DO_NOT_PLAY);
    PlayerAudioFocus focus =
        new PlayerAudioFocus(
            mockExoPlayer,
            new AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),
            false,
            mockEvents,
            control -> focusManager);
    VideoPlayer.FocusInterruptionHandler handler = mock(VideoPlayer.FocusInterruptionHandler.class);
    focus.setInterruptionHandler(handler);
    assertFalse(mockExoPlayer.isPlaying());
    focus.play();
    InOrder order = inOrder(focusManager, mockExoPlayer, handler, mockEvents);
    order.verify(focusManager).updateAudioFocus(true, Player.STATE_BUFFERING);
    order.verify(mockExoPlayer).pause();
    order.verify(handler).onInterrupted(1);
    order.verify(mockEvents).onIsPlayingStateUpdate(false);
    verify(mockExoPlayer, never()).play();
    verify(mockEvents).onIsPlayingStateUpdate(false);
    focus.release();
  }

  @Test
  public void explicitResumePolicyIsPerPlayerAndReleasedOnDispose() {
    ExoPlayer otherExoPlayer = mock(ExoPlayer.class);
    VideoPlayer togetherPlayer = createVideoPlayer();
    VideoPlayer localPlayer =
        new TestVideoPlayer(
            mockEvents,
            fakeVideoAsset.getMediaItem(),
            new VideoPlayerOptions(),
            null,
            () -> otherExoPlayer);
    when(mockExoPlayer.getPlayWhenReady()).thenReturn(true);
    when(otherExoPlayer.getPlayWhenReady()).thenReturn(true);
    PlayerAudioFocus togetherFocus = togetherPlayer.getAudioFocusForTesting();
    PlayerAudioFocus localFocus = localPlayer.getAudioFocusForTesting();
    togetherPlayer.setRequireExplicitResume(true);
    togetherFocus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    localFocus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    togetherFocus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    localFocus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    verify(mockExoPlayer).pause();
    verify(mockExoPlayer, never()).play();
    verify(otherExoPlayer).play();

    togetherPlayer.dispose();
    togetherFocus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    verify(mockExoPlayer, times(1)).pause();
    localPlayer.dispose();
  }

  @Test
  public void loadsAndPreparesProvidedMediaWithExternalFocusOwner() {
    VideoPlayer videoPlayer = createVideoPlayer();

    verify(mockExoPlayer).setMediaItem(fakeVideoAsset.getMediaItem());
    verify(mockExoPlayer).prepare();

    verify(mockExoPlayer).setAudioAttributes(attributesCaptor.capture(), eq(false));
    assertEquals(C.AUDIO_CONTENT_TYPE_MOVIE, attributesCaptor.getValue().contentType);

    videoPlayer.dispose();
  }

  @Test
  public void mixModeAlsoDisablesExoPlayerFocusOwner() {
    VideoPlayerOptions options = new VideoPlayerOptions();
    options.mixWithOthers = true;

    VideoPlayer videoPlayer = createVideoPlayer(options);

    verify(mockExoPlayer).setAudioAttributes(attributesCaptor.capture(), eq(false));
    assertEquals(C.AUDIO_CONTENT_TYPE_MOVIE, attributesCaptor.getValue().contentType);

    videoPlayer.dispose();
  }

  @Test
  public void playsAndPausesProvidedMedia() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.play();
    verify(mockExoPlayer).play();

    videoPlayer.pause();
    verify(mockExoPlayer).pause();

    videoPlayer.dispose();
  }

  @Test
  public void togglesLoopingEnablesAndDisablesRepeatMode() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.setLooping(true);
    verify(mockExoPlayer).setRepeatMode(Player.REPEAT_MODE_ALL);

    videoPlayer.setLooping(false);
    verify(mockExoPlayer).setRepeatMode(Player.REPEAT_MODE_OFF);

    videoPlayer.dispose();
  }

  @Test
  public void setVolumeIsClampedBetween0and1() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.setVolume(-1.0);
    verify(mockExoPlayer).setVolume(0f);

    videoPlayer.setVolume(2.0);
    verify(mockExoPlayer).setVolume(1f);

    videoPlayer.setVolume(0.5);
    verify(mockExoPlayer).setVolume(0.5f);

    videoPlayer.dispose();
  }

  @Test
  public void setPlaybackSpeedSetsPlaybackParametersWithValue() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.setPlaybackSpeed(2.5);
    verify(mockExoPlayer).setPlaybackParameters(new PlaybackParameters(2.5f));

    videoPlayer.dispose();
  }

  @Test
  public void seekTo() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.seekTo(10L);
    verify(mockExoPlayer).seekTo(10);

    videoPlayer.dispose();
  }

  @Test
  public void getCurrentPosition() {
    VideoPlayer videoPlayer = createVideoPlayer();

    final long playbackPosition = 20L;
    when(mockExoPlayer.getCurrentPosition()).thenReturn(playbackPosition);

    final Long position = videoPlayer.getCurrentPosition();
    assertEquals(playbackPosition, position.longValue());

    videoPlayer.dispose();
  }

  @Test
  public void getBufferedPosition() {
    VideoPlayer videoPlayer = createVideoPlayer();

    final long bufferedPosition = 10L;
    when(mockExoPlayer.getBufferedPosition()).thenReturn(bufferedPosition);

    final Long position = videoPlayer.getBufferedPosition();
    assertEquals(bufferedPosition, position.longValue());

    videoPlayer.dispose();
  }

  @Test
  public void onInitializedCalledWhenVideoPlayerInitiallyAvailable() {
    VideoPlayer videoPlayer = createVideoPlayer();

    // Pretend we have a video, and capture the registered event listener.
    when(mockExoPlayer.getVideoFormat())
        .thenReturn(
            new Format.Builder().setWidth(300).setHeight(200).setRotationDegrees(0).build());
    verify(mockExoPlayer, atLeast(2)).addListener(listenerCaptor.capture());
    Player.Listener listener = listenerCaptor.getAllValues().get(0);

    // Trigger an event that would trigger onInitialized.
    listener.onPlaybackStateChanged(Player.STATE_READY);
    verify(mockEvents).onInitialized(anyInt(), anyInt(), anyLong(), anyInt());

    videoPlayer.dispose();
  }

  @Test
  public void disposeReleasesExoPlayer() {
    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.dispose();

    verify(mockExoPlayer).release();
  }

  // Helper method to set the length field on a mocked Tracks.Group
  private void setGroupLength(Tracks.Group group, int length) {
    try {
      Field lengthField = group.getClass().getDeclaredField("length");
      lengthField.setAccessible(true);
      lengthField.setInt(group, length);
    } catch (Exception e) {
      throw new RuntimeException("Failed to set length field", e);
    }
  }

  @Test
  public void testGetAudioTracks_withMultipleAudioTracks() {
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockAudioGroup1 = mock(Tracks.Group.class);
    Tracks.Group mockAudioGroup2 = mock(Tracks.Group.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    // Create mock formats for audio tracks
    Format audioFormat1 =
        new Format.Builder()
            .setId("audio_track_1")
            .setLabel("English")
            .setLanguage("en")
            .setAverageBitrate(128000)
            .setSampleRate(48000)
            .setChannelCount(2)
            .setCodecs("mp4a.40.2")
            .build();

    Format audioFormat2 =
        new Format.Builder()
            .setId("audio_track_2")
            .setLabel("Español")
            .setLanguage("es")
            .setAverageBitrate(96000)
            .setSampleRate(44100)
            .setChannelCount(2)
            .setCodecs("mp4a.40.2")
            .build();

    // Mock audio groups and set length field
    setGroupLength(mockAudioGroup1, 1);
    setGroupLength(mockAudioGroup2, 1);

    when(mockAudioGroup1.getType()).thenReturn(C.TRACK_TYPE_AUDIO);
    when(mockAudioGroup1.getTrackFormat(0)).thenReturn(audioFormat1);
    when(mockAudioGroup1.isTrackSelected(0)).thenReturn(true);

    when(mockAudioGroup2.getType()).thenReturn(C.TRACK_TYPE_AUDIO);
    when(mockAudioGroup2.getTrackFormat(0)).thenReturn(audioFormat2);
    when(mockAudioGroup2.isTrackSelected(0)).thenReturn(false);

    when(mockVideoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);

    // Mock tracks
    ImmutableList<Tracks.Group> groups =
        ImmutableList.of(mockAudioGroup1, mockAudioGroup2, mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test the method
    NativeAudioTrackData nativeData = videoPlayer.getAudioTracks();
    List<ExoPlayerAudioTrackData> result = nativeData.getExoPlayerTracks();

    // Verify results
    assertNotNull(result);
    assertEquals(2, result.size());

    // Verify first track
    ExoPlayerAudioTrackData track1 = result.get(0);
    assertEquals(0L, track1.getGroupIndex());
    assertEquals(0L, track1.getTrackIndex());
    assertEquals("English", track1.getLabel());
    assertEquals("en", track1.getLanguage());
    assertTrue(track1.isSelected());
    assertEquals(Long.valueOf(128000), track1.getBitrate());
    assertEquals(Long.valueOf(48000), track1.getSampleRate());
    assertEquals(Long.valueOf(2), track1.getChannelCount());
    assertEquals("mp4a.40.2", track1.getCodec());

    // Verify second track
    ExoPlayerAudioTrackData track2 = result.get(1);
    assertEquals(1L, track2.getGroupIndex());
    assertEquals(0L, track2.getTrackIndex());
    assertEquals("Español", track2.getLabel());
    assertEquals("es", track2.getLanguage());
    assertFalse(track2.isSelected());
    assertEquals(Long.valueOf(96000), track2.getBitrate());
    assertEquals(Long.valueOf(44100), track2.getSampleRate());
    assertEquals(Long.valueOf(2), track2.getChannelCount());
    assertEquals("mp4a.40.2", track2.getCodec());

    videoPlayer.dispose();
  }

  @Test
  public void testGetAudioTracks_withNoAudioTracks() {
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    // Mock video group only (no audio tracks)
    when(mockVideoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test the method
    NativeAudioTrackData nativeData = videoPlayer.getAudioTracks();
    List<ExoPlayerAudioTrackData> result = nativeData.getExoPlayerTracks();

    // Verify results
    assertNotNull(result);
    assertEquals(0, result.size());

    videoPlayer.dispose();
  }

  @Test
  public void testGetAudioTracks_withNullValues() {
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockAudioGroup1 = mock(Tracks.Group.class);

    // Create format with null/missing values
    Format audioFormat =
        new Format.Builder()
            .setId("audio_track_null")
            .setLabel(null) // Null label
            .setLanguage(null) // Null language
            .setAverageBitrate(Format.NO_VALUE) // No bitrate
            .setSampleRate(Format.NO_VALUE) // No sample rate
            .setChannelCount(Format.NO_VALUE) // No channel count
            .setCodecs(null) // Null codec
            .build();

    // Mock audio group and set length field
    setGroupLength(mockAudioGroup1, 1);
    when(mockAudioGroup1.getType()).thenReturn(C.TRACK_TYPE_AUDIO);
    when(mockAudioGroup1.getTrackFormat(0)).thenReturn(audioFormat);
    when(mockAudioGroup1.isTrackSelected(0)).thenReturn(false);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockAudioGroup1);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test the method
    NativeAudioTrackData nativeData = videoPlayer.getAudioTracks();
    List<ExoPlayerAudioTrackData> result = nativeData.getExoPlayerTracks();

    // Verify results
    assertNotNull(result);
    assertEquals(1, result.size());

    ExoPlayerAudioTrackData track = result.get(0);
    assertEquals(0L, track.getGroupIndex());
    assertEquals(0L, track.getTrackIndex());
    assertNull(track.getLabel()); // Null values should be preserved
    assertNull(track.getLanguage()); // Null values should be preserved
    assertFalse(track.isSelected());
    assertNull(track.getBitrate());
    assertNull(track.getSampleRate());
    assertNull(track.getChannelCount());
    assertNull(track.getCodec());

    videoPlayer.dispose();
  }

  @Test
  public void testGetAudioTracks_withMultipleTracksInSameGroup() {
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockAudioGroup1 = mock(Tracks.Group.class);

    // Create format for group with multiple tracks
    Format audioFormat1 =
        new Format.Builder()
            .setId("audio_track_1")
            .setLabel("Track 1")
            .setLanguage("en")
            .setAverageBitrate(128000)
            .build();

    Format audioFormat2 =
        new Format.Builder()
            .setId("audio_track_2")
            .setLabel("Track 2")
            .setLanguage("en")
            .setAverageBitrate(192000)
            .build();

    // Mock audio group with multiple tracks
    setGroupLength(mockAudioGroup1, 2);
    when(mockAudioGroup1.getType()).thenReturn(C.TRACK_TYPE_AUDIO);
    when(mockAudioGroup1.getTrackFormat(0)).thenReturn(audioFormat1);
    when(mockAudioGroup1.getTrackFormat(1)).thenReturn(audioFormat2);
    when(mockAudioGroup1.isTrackSelected(0)).thenReturn(true);
    when(mockAudioGroup1.isTrackSelected(1)).thenReturn(false);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockAudioGroup1);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test the method
    NativeAudioTrackData nativeData = videoPlayer.getAudioTracks();
    List<ExoPlayerAudioTrackData> result = nativeData.getExoPlayerTracks();

    // Verify results
    assertNotNull(result);
    assertEquals(2, result.size());

    // Verify track indices are correct
    ExoPlayerAudioTrackData track1 = result.get(0);
    ExoPlayerAudioTrackData track2 = result.get(1);
    assertEquals(0L, track1.getGroupIndex());
    assertEquals(0L, track1.getTrackIndex());
    assertEquals(0L, track2.getGroupIndex());
    assertEquals(1L, track2.getTrackIndex());
    // Tracks have same group but different track indices
    assertEquals(track1.getGroupIndex(), track2.getGroupIndex());
    assertNotEquals(track1.getTrackIndex(), track2.getTrackIndex());

    videoPlayer.dispose();
  }

  @Test
  public void testSelectAudioTrack_validIndices() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    DefaultTrackSelector.Parameters mockParameters = mock(DefaultTrackSelector.Parameters.class);
    DefaultTrackSelector.Parameters.Builder mockBuilder =
        mock(DefaultTrackSelector.Parameters.Builder.class);

    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockAudioGroup = mock(Tracks.Group.class);

    Format audioFormat =
        new Format.Builder().setId("audio_track_1").setLabel("English").setLanguage("en").build();

    // Create a real TrackGroup with the format
    TrackGroup trackGroup = new TrackGroup(audioFormat);

    // Mock audio group with 2 tracks
    setGroupLength(mockAudioGroup, 2);
    when(mockAudioGroup.getType()).thenReturn(C.TRACK_TYPE_AUDIO);
    when(mockAudioGroup.getMediaTrackGroup()).thenReturn(trackGroup);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockAudioGroup);
    when(mockTracks.getGroups()).thenReturn(groups);

    // Set up track selector BEFORE creating VideoPlayer
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockTrackSelector.buildUponParameters()).thenReturn(mockBuilder);
    when(mockBuilder.setOverrideForType(any(TrackSelectionOverride.class))).thenReturn(mockBuilder);
    when(mockBuilder.build()).thenReturn(mockParameters);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test selecting a valid audio track
    videoPlayer.selectAudioTrack(0, 0);

    // Verify track selector was called
    verify(mockTrackSelector).buildUponParameters();
    verify(mockBuilder).setOverrideForType(any(TrackSelectionOverride.class));
    verify(mockBuilder).build();
    verify(mockTrackSelector).setParameters(mockParameters);

    videoPlayer.dispose();
  }

  @Test
  public void testSelectAudioTrack_nullTrackSelector() {
    // Track selector is null by default in mock
    VideoPlayer videoPlayer = createVideoPlayer();

    assertThrows(IllegalStateException.class, () -> videoPlayer.selectAudioTrack(0, 0));

    videoPlayer.dispose();
  }

  @Test
  public void testSelectAudioTrack_invalidGroupIndex() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockAudioGroup = mock(Tracks.Group.class);

    Format audioFormat =
        new Format.Builder().setId("audio_track_1").setLabel("English").setLanguage("en").build();

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockAudioGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test with invalid group index (only 1 group exists at index 0)
    assertThrows(IllegalArgumentException.class, () -> videoPlayer.selectAudioTrack(5, 0));

    videoPlayer.dispose();
  }

  @Test
  public void testSelectAudioTrack_invalidTrackIndex() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockAudioGroup = mock(Tracks.Group.class);

    Format audioFormat =
        new Format.Builder().setId("audio_track_1").setLabel("English").setLanguage("en").build();

    // Mock audio group with only 1 track
    setGroupLength(mockAudioGroup, 1);
    when(mockAudioGroup.getType()).thenReturn(C.TRACK_TYPE_AUDIO);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockAudioGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test with invalid track index (only 1 track exists at index 0)
    assertThrows(IllegalArgumentException.class, () -> videoPlayer.selectAudioTrack(0, 5));

    videoPlayer.dispose();
  }

  @Test
  public void testSelectAudioTrack_nonAudioGroup() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    // Mock video group (not audio)
    setGroupLength(mockVideoGroup, 1);
    when(mockVideoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test selecting from a non-audio group
    assertThrows(IllegalArgumentException.class, () -> videoPlayer.selectAudioTrack(0, 0));

    videoPlayer.dispose();
  }

  @Test
  public void testSelectAudioTrack_negativeIndices() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockAudioGroup = mock(Tracks.Group.class);

    Format audioFormat =
        new Format.Builder().setId("audio_track_1").setLabel("English").setLanguage("en").build();

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockAudioGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test with negative indices - should be caught by bounds checking
    assertThrows(IllegalArgumentException.class, () -> videoPlayer.selectAudioTrack(-1, 0));

    videoPlayer.dispose();
  }

  // ==================== Video Track Tests ====================

  @Test
  public void testGetVideoTracks_withMultipleVideoTracks() {
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup1 = mock(Tracks.Group.class);
    Tracks.Group mockVideoGroup2 = mock(Tracks.Group.class);
    Tracks.Group mockAudioGroup = mock(Tracks.Group.class);

    // Create mock formats for video tracks
    Format videoFormat1 =
        new Format.Builder()
            .setId("video_track_1")
            .setLabel("1080p")
            .setAverageBitrate(5000000)
            .setWidth(1920)
            .setHeight(1080)
            .setFrameRate(30.0f)
            .setCodecs("avc1.64001f")
            .build();

    Format videoFormat2 =
        new Format.Builder()
            .setId("video_track_2")
            .setLabel("720p")
            .setAverageBitrate(2500000)
            .setWidth(1280)
            .setHeight(720)
            .setFrameRate(24.0f)
            .setCodecs("avc1.4d401f")
            .build();

    // Mock video groups and set length field
    setGroupLength(mockVideoGroup1, 1);
    setGroupLength(mockVideoGroup2, 1);

    when(mockVideoGroup1.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(mockVideoGroup1.getTrackFormat(0)).thenReturn(videoFormat1);
    when(mockVideoGroup1.isTrackSelected(0)).thenReturn(true);

    when(mockVideoGroup2.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(mockVideoGroup2.getTrackFormat(0)).thenReturn(videoFormat2);
    when(mockVideoGroup2.isTrackSelected(0)).thenReturn(false);

    when(mockAudioGroup.getType()).thenReturn(C.TRACK_TYPE_AUDIO);

    // Mock tracks
    ImmutableList<Tracks.Group> groups =
        ImmutableList.of(mockVideoGroup1, mockVideoGroup2, mockAudioGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test the method
    NativeVideoTrackData nativeData = videoPlayer.getVideoTracks();
    List<ExoPlayerVideoTrackData> result = nativeData.getExoPlayerTracks();

    // Verify results
    assertNotNull(result);
    assertEquals(2, result.size());

    // Verify first track
    ExoPlayerVideoTrackData track1 = result.get(0);
    assertEquals(0L, track1.getGroupIndex());
    assertEquals(0L, track1.getTrackIndex());
    assertEquals("1080p", track1.getLabel());
    assertTrue(track1.isSelected());
    assertEquals(Long.valueOf(5000000), track1.getBitrate());
    assertEquals(Long.valueOf(1920), track1.getWidth());
    assertEquals(Long.valueOf(1080), track1.getHeight());
    assertEquals(Double.valueOf(30.0), track1.getFrameRate());
    assertEquals("avc1.64001f", track1.getCodec());

    // Verify second track
    ExoPlayerVideoTrackData track2 = result.get(1);
    assertEquals(1L, track2.getGroupIndex());
    assertEquals(0L, track2.getTrackIndex());
    assertEquals("720p", track2.getLabel());
    assertFalse(track2.isSelected());
    assertEquals(Long.valueOf(2500000), track2.getBitrate());
    assertEquals(Long.valueOf(1280), track2.getWidth());
    assertEquals(Long.valueOf(720), track2.getHeight());
    assertEquals(Double.valueOf(24.0), track2.getFrameRate());
    assertEquals("avc1.4d401f", track2.getCodec());

    videoPlayer.dispose();
  }

  @Test
  public void testGetVideoTracks_withNoVideoTracks() {
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockAudioGroup = mock(Tracks.Group.class);

    // Mock audio group only (no video tracks)
    when(mockAudioGroup.getType()).thenReturn(C.TRACK_TYPE_AUDIO);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockAudioGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test the method
    NativeVideoTrackData nativeData = videoPlayer.getVideoTracks();
    List<ExoPlayerVideoTrackData> result = nativeData.getExoPlayerTracks();

    // Verify results
    assertNotNull(result);
    assertEquals(0, result.size());

    videoPlayer.dispose();
  }

  @Test
  public void testGetVideoTracks_withNullValues() {
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    // Create format with null/missing values
    Format videoFormat =
        new Format.Builder()
            .setId("video_track_null")
            .setLabel(null) // Null label
            .setAverageBitrate(Format.NO_VALUE) // No bitrate
            .setWidth(Format.NO_VALUE) // No width
            .setHeight(Format.NO_VALUE) // No height
            .setFrameRate(Format.NO_VALUE) // No frame rate
            .setCodecs(null) // Null codec
            .build();

    // Mock video group and set length field
    setGroupLength(mockVideoGroup, 1);
    when(mockVideoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(mockVideoGroup.getTrackFormat(0)).thenReturn(videoFormat);
    when(mockVideoGroup.isTrackSelected(0)).thenReturn(false);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test the method
    NativeVideoTrackData nativeData = videoPlayer.getVideoTracks();
    List<ExoPlayerVideoTrackData> result = nativeData.getExoPlayerTracks();

    // Verify results
    assertNotNull(result);
    assertEquals(1, result.size());

    ExoPlayerVideoTrackData track = result.get(0);
    assertEquals(0L, track.getGroupIndex());
    assertEquals(0L, track.getTrackIndex());
    assertNull(track.getLabel()); // Null values should be preserved
    assertFalse(track.isSelected());
    assertNull(track.getBitrate());
    assertNull(track.getWidth());
    assertNull(track.getHeight());
    assertNull(track.getFrameRate());
    assertNull(track.getCodec());

    videoPlayer.dispose();
  }

  @Test
  public void testGetVideoTracks_withMultipleTracksInSameGroup() {
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    // Create formats for group with multiple tracks (adaptive streaming scenario)
    Format videoFormat1 =
        new Format.Builder()
            .setId("video_track_1")
            .setLabel("1080p")
            .setWidth(1920)
            .setHeight(1080)
            .setAverageBitrate(5000000)
            .build();

    Format videoFormat2 =
        new Format.Builder()
            .setId("video_track_2")
            .setLabel("720p")
            .setWidth(1280)
            .setHeight(720)
            .setAverageBitrate(2500000)
            .build();

    // Mock video group with multiple tracks
    setGroupLength(mockVideoGroup, 2);
    when(mockVideoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(mockVideoGroup.getTrackFormat(0)).thenReturn(videoFormat1);
    when(mockVideoGroup.getTrackFormat(1)).thenReturn(videoFormat2);
    when(mockVideoGroup.isTrackSelected(0)).thenReturn(true);
    when(mockVideoGroup.isTrackSelected(1)).thenReturn(false);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test the method
    NativeVideoTrackData nativeData = videoPlayer.getVideoTracks();
    List<ExoPlayerVideoTrackData> result = nativeData.getExoPlayerTracks();

    // Verify results
    assertNotNull(result);
    assertEquals(2, result.size());

    // Verify track indices are correct
    ExoPlayerVideoTrackData track1 = result.get(0);
    ExoPlayerVideoTrackData track2 = result.get(1);
    assertEquals(0L, track1.getGroupIndex());
    assertEquals(0L, track1.getTrackIndex());
    assertEquals(0L, track2.getGroupIndex());
    assertEquals(1L, track2.getTrackIndex());
    // Tracks have same group but different track indices
    assertEquals(track1.getGroupIndex(), track2.getGroupIndex());
    assertNotEquals(track1.getTrackIndex(), track2.getTrackIndex());

    videoPlayer.dispose();
  }

  @Test
  public void testSelectVideoTrack_validIndices() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    DefaultTrackSelector.Parameters mockParameters = mock(DefaultTrackSelector.Parameters.class);
    DefaultTrackSelector.Parameters.Builder mockBuilder =
        mock(DefaultTrackSelector.Parameters.Builder.class);

    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    Format videoFormat =
        new Format.Builder()
            .setId("video_track_1")
            .setLabel("1080p")
            .setWidth(1920)
            .setHeight(1080)
            .build();

    // Create a real TrackGroup with the format
    TrackGroup trackGroup = new TrackGroup(videoFormat);

    // Mock video group with 2 tracks
    setGroupLength(mockVideoGroup, 2);
    when(mockVideoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(mockVideoGroup.getMediaTrackGroup()).thenReturn(trackGroup);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);

    // Set up track selector BEFORE creating VideoPlayer
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getVideoFormat()).thenReturn(videoFormat);
    when(mockTrackSelector.buildUponParameters()).thenReturn(mockBuilder);
    when(mockBuilder.setOverrideForType(any(TrackSelectionOverride.class))).thenReturn(mockBuilder);
    when(mockBuilder.setTrackTypeDisabled(anyInt(), anyBoolean())).thenReturn(mockBuilder);
    when(mockBuilder.build()).thenReturn(mockParameters);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test selecting a valid video track
    videoPlayer.selectVideoTrack(0, 0);

    // Verify track selector was called
    verify(mockTrackSelector, atLeastOnce()).buildUponParameters();
    verify(mockBuilder, atLeastOnce()).build();
    verify(mockTrackSelector, atLeastOnce()).setParameters(mockParameters);

    videoPlayer.dispose();
  }

  @Test
  public void testSelectVideoTrack_disposeDuringDimensionChangeDelayDoesNotCrash() {
    // Regression test: disposing the player during the 150ms postDelayed
    // dimension-change workaround used to call seekTo()/play() on a released
    // ExoPlayer, throwing IllegalStateException. After the fix, dispose()
    // cancels the pending callback (and sets isDisposed) so the runnable
    // becomes a no-op.
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    DefaultTrackSelector.Parameters mockParameters = mock(DefaultTrackSelector.Parameters.class);
    DefaultTrackSelector.Parameters.Builder mockBuilder =
        mock(DefaultTrackSelector.Parameters.Builder.class);

    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    // Current playing format: 720p. New selected track: 1080p — triggers the
    // dimension-change branch that posts the delayed re-enable callback.
    Format currentFormat = new Format.Builder().setId("cur").setWidth(1280).setHeight(720).build();
    Format newFormat = new Format.Builder().setId("new").setWidth(1920).setHeight(1080).build();

    TrackGroup trackGroup = new TrackGroup(newFormat);
    setGroupLength(mockVideoGroup, 1);
    when(mockVideoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(mockVideoGroup.getMediaTrackGroup()).thenReturn(trackGroup);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);

    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getVideoFormat()).thenReturn(currentFormat);
    when(mockExoPlayer.isPlaying()).thenReturn(true);
    when(mockExoPlayer.getCurrentPosition()).thenReturn(1234L);
    when(mockTrackSelector.buildUponParameters()).thenReturn(mockBuilder);
    when(mockBuilder.setOverrideForType(any(TrackSelectionOverride.class))).thenReturn(mockBuilder);
    when(mockBuilder.setTrackTypeDisabled(anyInt(), anyBoolean())).thenReturn(mockBuilder);
    when(mockBuilder.build()).thenReturn(mockParameters);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Schedule the delayed renderer-reset callback.
    videoPlayer.selectVideoTrack(0, 0);

    // Simulate the player being disposed before the 150ms timer fires.
    videoPlayer.dispose();

    // Releasing the player makes further calls on it throw — model that on
    // the mock so a stray seekTo/play after dispose would surface.
    doThrow(new IllegalStateException("Player released")).when(mockExoPlayer).seekTo(anyLong());
    doThrow(new IllegalStateException("Player released")).when(mockExoPlayer).play();

    // Advance the main looper past the 150ms delay. Without the fix this
    // throws IllegalStateException; with the fix the callback is cancelled.
    ShadowLooper.shadowMainLooper().idleFor(200, java.util.concurrent.TimeUnit.MILLISECONDS);

    verify(mockExoPlayer, never()).seekTo(anyLong());
    verify(mockExoPlayer, never()).play();
  }

  private VideoPlayer scheduleRendererResetWhilePlaying() {
    DefaultTrackSelector selector = mock(DefaultTrackSelector.class);
    DefaultTrackSelector.Parameters parameters = mock(DefaultTrackSelector.Parameters.class);
    DefaultTrackSelector.Parameters.Builder builder =
        mock(DefaultTrackSelector.Parameters.Builder.class);
    Tracks tracks = mock(Tracks.class);
    Tracks.Group videoGroup = mock(Tracks.Group.class);
    Format oldFormat = new Format.Builder().setWidth(1280).setHeight(720).build();
    Format newFormat = new Format.Builder().setWidth(1920).setHeight(1080).build();
    when(videoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(videoGroup.getMediaTrackGroup()).thenReturn(new TrackGroup(newFormat));
    setGroupLength(videoGroup, 1);
    when(tracks.getGroups()).thenReturn(ImmutableList.of(videoGroup));
    when(mockExoPlayer.getTrackSelector()).thenReturn(selector);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(tracks);
    when(mockExoPlayer.getVideoFormat()).thenReturn(oldFormat);
    when(mockExoPlayer.isPlaying()).thenReturn(true);
    when(selector.buildUponParameters()).thenReturn(builder);
    when(builder.setTrackTypeDisabled(anyInt(), anyBoolean())).thenReturn(builder);
    when(builder.setOverrideForType(any(TrackSelectionOverride.class))).thenReturn(builder);
    when(builder.build()).thenReturn(parameters);
    VideoPlayer videoPlayer = createVideoPlayer();
    videoPlayer.selectVideoTrack(0, 0);
    return videoPlayer;
  }

  @Test
  public void focusLossDuringRendererResetDoesNotRestartPlayback() {
    VideoPlayer videoPlayer = scheduleRendererResetWhilePlaying();
    when(mockExoPlayer.getPlayWhenReady()).thenReturn(true);
    videoPlayer.setRequireExplicitResume(true);
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    ShadowLooper.shadowMainLooper().idleFor(200, java.util.concurrent.TimeUnit.MILLISECONDS);
    verify(mockExoPlayer, never()).play();
    videoPlayer.dispose();
  }

  @Test
  public void explicitPauseDuringRendererResetDoesNotRestartPlayback() {
    VideoPlayer videoPlayer = scheduleRendererResetWhilePlaying();
    videoPlayer.pause();
    ShadowLooper.shadowMainLooper().idleFor(200, java.util.concurrent.TimeUnit.MILLISECONDS);
    verify(mockExoPlayer, never()).play();
    videoPlayer.dispose();
  }

  @Test
  public void playbackEndDuringRendererResetDoesNotRestartPlayback() {
    VideoPlayer videoPlayer = scheduleRendererResetWhilePlaying();
    verify(mockExoPlayer, atLeast(2)).addListener(listenerCaptor.capture());
    for (Player.Listener listener : listenerCaptor.getAllValues()) {
      listener.onPlaybackStateChanged(Player.STATE_ENDED);
    }
    ShadowLooper.shadowMainLooper().idleFor(200, java.util.concurrent.TimeUnit.MILLISECONDS);
    verify(mockExoPlayer, never()).play();
    videoPlayer.dispose();
  }

  @Test
  public void decoderFailureCancelsPendingLocalResume() {
    VideoPlayer videoPlayer = createVideoPlayer();
    when(mockExoPlayer.getPlayWhenReady()).thenReturn(true);
    PlayerAudioFocus focus = videoPlayer.getAudioFocusForTesting();
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_WAIT_FOR_CALLBACK);
    verify(mockExoPlayer, atLeast(2)).addListener(listenerCaptor.capture());
    for (Player.Listener listener : listenerCaptor.getAllValues()) {
      listener.onPlaybackStateChanged(Player.STATE_IDLE);
    }
    focus.executePlayerCommand(AudioFocusManager.PLAYER_COMMAND_PLAY_WHEN_READY);
    verify(mockExoPlayer, never()).play();
    videoPlayer.dispose();
  }

  @Test
  public void testSelectVideoTrack_nullCurrentFormatStillUsesRendererResetWorkaround() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    DefaultTrackSelector.Parameters mockParameters = mock(DefaultTrackSelector.Parameters.class);
    DefaultTrackSelector.Parameters.Builder mockBuilder =
        mock(DefaultTrackSelector.Parameters.Builder.class);

    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    Format newFormat = new Format.Builder().setId("new").setWidth(1920).setHeight(1080).build();

    TrackGroup trackGroup = new TrackGroup(newFormat);
    setGroupLength(mockVideoGroup, 1);
    when(mockVideoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);
    when(mockVideoGroup.getMediaTrackGroup()).thenReturn(trackGroup);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);

    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getVideoFormat()).thenReturn(null);
    when(mockExoPlayer.isPlaying()).thenReturn(false);
    when(mockExoPlayer.getCurrentPosition()).thenReturn(1234L);
    when(mockTrackSelector.buildUponParameters()).thenReturn(mockBuilder);
    when(mockBuilder.setOverrideForType(any(TrackSelectionOverride.class))).thenReturn(mockBuilder);
    when(mockBuilder.setTrackTypeDisabled(anyInt(), anyBoolean())).thenReturn(mockBuilder);
    when(mockBuilder.build()).thenReturn(mockParameters);

    VideoPlayer videoPlayer = createVideoPlayer();

    videoPlayer.selectVideoTrack(0, 0);

    verify(mockBuilder).setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, true);

    ShadowLooper.shadowMainLooper().idleFor(200, java.util.concurrent.TimeUnit.MILLISECONDS);

    verify(mockBuilder).setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, false);
    verify(mockBuilder, atLeastOnce()).setOverrideForType(any(TrackSelectionOverride.class));

    videoPlayer.dispose();
  }

  @Test
  public void testSelectVideoTrack_nullTrackSelector() {
    // Track selector is null by default in mock
    VideoPlayer videoPlayer = createVideoPlayer();

    assertThrows(IllegalStateException.class, () -> videoPlayer.selectVideoTrack(0, 0));

    videoPlayer.dispose();
  }

  @Test
  public void testSelectVideoTrack_invalidGroupIndex() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test with invalid group index (only 1 group exists at index 0)
    assertThrows(IllegalArgumentException.class, () -> videoPlayer.selectVideoTrack(5, 0));

    videoPlayer.dispose();
  }

  @Test
  public void testSelectVideoTrack_invalidTrackIndex() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    // Mock video group with only 1 track
    setGroupLength(mockVideoGroup, 1);
    when(mockVideoGroup.getType()).thenReturn(C.TRACK_TYPE_VIDEO);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test with invalid track index (only 1 track exists at index 0)
    assertThrows(IllegalArgumentException.class, () -> videoPlayer.selectVideoTrack(0, 5));

    videoPlayer.dispose();
  }

  @Test
  public void testSelectVideoTrack_nonVideoGroup() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockAudioGroup = mock(Tracks.Group.class);

    // Mock audio group (not video)
    setGroupLength(mockAudioGroup, 1);
    when(mockAudioGroup.getType()).thenReturn(C.TRACK_TYPE_AUDIO);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockAudioGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test selecting from a non-video group
    assertThrows(IllegalArgumentException.class, () -> videoPlayer.selectVideoTrack(0, 0));

    videoPlayer.dispose();
  }

  @Test
  public void testSelectVideoTrack_negativeIndices() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    Tracks mockTracks = mock(Tracks.class);
    Tracks.Group mockVideoGroup = mock(Tracks.Group.class);

    ImmutableList<Tracks.Group> groups = ImmutableList.of(mockVideoGroup);
    when(mockTracks.getGroups()).thenReturn(groups);
    when(mockExoPlayer.getCurrentTracks()).thenReturn(mockTracks);
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test with negative group index only (not both -1)
    assertThrows(IllegalArgumentException.class, () -> videoPlayer.selectVideoTrack(-1, 0));

    videoPlayer.dispose();
  }

  @Test
  public void testEnableAutoVideoQuality() {
    DefaultTrackSelector mockTrackSelector = mock(DefaultTrackSelector.class);
    DefaultTrackSelector.Parameters mockParameters = mock(DefaultTrackSelector.Parameters.class);
    DefaultTrackSelector.Parameters.Builder mockBuilder =
        mock(DefaultTrackSelector.Parameters.Builder.class);

    // Set up track selector
    when(mockExoPlayer.getTrackSelector()).thenReturn(mockTrackSelector);
    when(mockTrackSelector.buildUponParameters()).thenReturn(mockBuilder);
    when(mockBuilder.clearOverridesOfType(C.TRACK_TYPE_VIDEO)).thenReturn(mockBuilder);
    when(mockBuilder.build()).thenReturn(mockParameters);

    VideoPlayer videoPlayer = createVideoPlayer();

    // Test enabling auto quality
    videoPlayer.enableAutoVideoQuality();

    // Verify track selector cleared video overrides
    verify(mockTrackSelector).buildUponParameters();
    verify(mockBuilder).clearOverridesOfType(C.TRACK_TYPE_VIDEO);
    verify(mockBuilder).build();
    verify(mockTrackSelector).setParameters(mockParameters);

    videoPlayer.dispose();
  }
}
