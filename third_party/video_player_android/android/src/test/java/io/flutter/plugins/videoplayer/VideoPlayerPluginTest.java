// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

import android.content.Context;
import android.util.LongSparseArray;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformViewRegistry;
import io.flutter.plugins.videoplayer.platformview.PlatformVideoViewFactory;
import io.flutter.plugins.videoplayer.platformview.PlatformViewVideoPlayer;
import io.flutter.plugins.videoplayer.texture.TextureVideoPlayer;
import io.flutter.view.TextureRegistry;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.Map;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mock;
import org.mockito.MockedStatic;
import org.mockito.MockitoAnnotations;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class VideoPlayerPluginTest {
  @Mock private TextureRegistry mockTextureRegistry;
  @Mock private TextureRegistry.SurfaceProducer mockSurfaceProducer;
  @Mock private PlatformViewRegistry mockPlatformViewRegistry;
  @Mock private BinaryMessenger mockMessenger;
  private FlutterPlugin.FlutterPluginBinding binding;
  private VideoPlayerPlugin plugin;

  @Before
  public void setUp() {
    MockitoAnnotations.openMocks(this);
    when(mockTextureRegistry.createSurfaceProducer()).thenReturn(mockSurfaceProducer);

    binding = mock(FlutterPlugin.FlutterPluginBinding.class);
    when(binding.getApplicationContext()).thenReturn(mock(Context.class));
    when(binding.getTextureRegistry()).thenReturn(mockTextureRegistry);
    when(binding.getBinaryMessenger()).thenReturn(mockMessenger);
    when(binding.getPlatformViewRegistry()).thenReturn(mockPlatformViewRegistry);

    plugin = new VideoPlayerPlugin();
    plugin.onAttachedToEngine(binding);
  }

  @SuppressWarnings("unchecked")
  private LongSparseArray<VideoPlayer> getVideoPlayers() throws Exception {
    final Field field = VideoPlayerPlugin.class.getDeclaredField("videoPlayers");
    field.setAccessible(true);
    return (LongSparseArray<VideoPlayer>) field.get(plugin);
  }

  // This is only a placeholder test and doesn't actually initialize the plugin.
  @Test
  public void initPluginDoesNotThrow() {
    final VideoPlayerPlugin plugin = new VideoPlayerPlugin();
  }

  @Test
  public void registersPlatformVideoViewFactory() {
    verify(mockPlatformViewRegistry)
        .registerViewFactory(
            eq("plugins.flutter.dev/video_player_android"), any(PlatformVideoViewFactory.class));
  }

  @Test
  public void registersAndUnregistersFocusChannelWithEngine() {
    verify(mockMessenger)
        .setMessageHandler(eq("com.meowwatch.mobile/player_focus"), notNull());

    plugin.onDetachedFromEngine(binding);

    verify(mockMessenger)
        .setMessageHandler(eq("com.meowwatch.mobile/player_focus"), isNull());
  }

  @Test
  public void createsPlatformViewVideoPlayer() throws Exception {
    try (MockedStatic<PlatformViewVideoPlayer> mockedPlatformViewVideoPlayerStatic =
        mockStatic(PlatformViewVideoPlayer.class)) {
      mockedPlatformViewVideoPlayerStatic
          .when(() -> PlatformViewVideoPlayer.create(any(), any(), any(), any()))
          .thenReturn(mock(PlatformViewVideoPlayer.class));

      final CreationOptions options =
          new CreationOptions(
              "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
              null,
              new HashMap<>(),
              null,
              null);

      final long playerId = plugin.createForPlatformView(options);

      final LongSparseArray<VideoPlayer> videoPlayers = getVideoPlayers();
      assertTrue(videoPlayers.get(playerId) instanceof PlatformViewVideoPlayer);
    }
  }

  @Test
  public void createsTextureVideoPlayer() throws Exception {
    try (MockedStatic<TextureVideoPlayer> mockedTextureVideoPlayerStatic =
        mockStatic(TextureVideoPlayer.class)) {
      mockedTextureVideoPlayerStatic
          .when(() -> TextureVideoPlayer.create(any(), any(), any(), any(), any()))
          .thenReturn(mock(TextureVideoPlayer.class));

      final CreationOptions options =
          new CreationOptions(
              "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
              null,
              new HashMap<>(),
              null,
              null);

      final TexturePlayerIds ids = plugin.createForTextureView(options);

      final LongSparseArray<VideoPlayer> videoPlayers = getVideoPlayers();
      assertTrue(videoPlayers.get(ids.getPlayerId()) instanceof TextureVideoPlayer);
    }
  }

  @Test
  public void focusCommandOnlyChangesTheAddressedOwnedPlayer() throws Exception {
    VideoPlayer togetherPlayer = mock(VideoPlayer.class);
    VideoPlayer localPlayer = mock(VideoPlayer.class);
    getVideoPlayers().put(1L, togetherPlayer);
    getVideoPlayers().put(2L, localPlayer);
    MethodChannel.Result result = mock(MethodChannel.Result.class);

    plugin.onPlayerFocusMethodCall(
        new MethodCall("setRequireExplicitResume", Map.of("playerId", 1, "required", true)),
        result);

    verify(togetherPlayer).setRequireExplicitResume(true);
    verify(localPlayer, never()).setRequireExplicitResume(anyBoolean());
    verify(result).success(null);
  }

  @Test
  public void focusCommandRejectsMalformedAndUnknownPlayerIds() throws Exception {
    VideoPlayer ownedPlayer = mock(VideoPlayer.class);
    getVideoPlayers().put(1L, ownedPlayer);
    MethodChannel.Result result = mock(MethodChannel.Result.class);

    plugin.onPlayerFocusMethodCall(
        new MethodCall("setRequireExplicitResume", Map.of("playerId", 1.5, "required", true)),
        result);
    plugin.onPlayerFocusMethodCall(
        new MethodCall("setRequireExplicitResume", Map.of("playerId", -1, "required", true)),
        result);
    plugin.onPlayerFocusMethodCall(
        new MethodCall("setRequireExplicitResume", Map.of("playerId", 1, "required", "yes")),
        result);
    plugin.onPlayerFocusMethodCall(
        new MethodCall(
            "setRequireExplicitResume", Map.of("playerId", 1, "required", true, "extra", 2)),
        result);
    plugin.onPlayerFocusMethodCall(
        new MethodCall("setRequireExplicitResume", Map.of("playerId", 9L, "required", true)),
        result);

    verify(result, times(4)).error(eq("invalid_arguments"), anyString(), isNull());
    verify(result).error(eq("unknown_player"), anyString(), isNull());
    verify(ownedPlayer, never()).setRequireExplicitResume(anyBoolean());
  }

  @Test
  public void focusChannelDoesNotExposeOtherPlayerCommands() throws Exception {
    VideoPlayer player = mock(VideoPlayer.class);
    getVideoPlayers().put(1L, player);
    MethodChannel.Result result = mock(MethodChannel.Result.class);

    plugin.onPlayerFocusMethodCall(
        new MethodCall("play", Map.of("playerId", 1L)), result);

    verify(result).notImplemented();
    verifyNoInteractions(player);
  }

  @Test
  public void disposedPlayerCannotBeChangedByFocusCommand() throws Exception {
    VideoPlayer player = mock(VideoPlayer.class);
    getVideoPlayers().put(1L, player);
    plugin.dispose(1L);
    MethodChannel.Result result = mock(MethodChannel.Result.class);

    plugin.onPlayerFocusMethodCall(
        new MethodCall("setRequireExplicitResume", Map.of("playerId", 1L, "required", true)),
        result);

    verify(result).error(eq("unknown_player"), anyString(), isNull());
    verify(player, never()).setRequireExplicitResume(anyBoolean());
  }
}
