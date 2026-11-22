import 'dart:math';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/duration_extensions.dart';
import 'package:immich_mobile/models/cast/cast_manager_state.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/video_player_provider.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/widgets/asset_viewer/animated_play_pause.dart';
import 'package:immich_ui/immich_ui.dart';

class VideoControls extends ConsumerStatefulWidget {
  final String videoPlayerName;

  const VideoControls({super.key, required this.videoPlayerName});

  @override
  ConsumerState<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends ConsumerState<VideoControls> {
  late final RestartableTimer _hideTimer;

  AutoDisposeStateNotifierProvider<VideoPlayerNotifier, VideoPlayerState> get _provider =>
      videoPlayerProvider(widget.videoPlayerName);

  @override
  void initState() {
    super.initState();
    _hideTimer = RestartableTimer(const Duration(seconds: 5), _onHideTimer);
  }

  @override
  void didUpdateWidget(covariant VideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPlayerName != widget.videoPlayerName) {
      _hideTimer.reset();
    }
  }

  @override
  void dispose() {
    _hideTimer.cancel();
    super.dispose();
  }

  void _onHideTimer() {
    if (!mounted) {
      return;
    }
    if (ref.read(_provider).status == VideoPlaybackStatus.playing) {
      ref.read(assetViewerProvider.notifier).setControls(false);
    }
  }

  void _toggle(bool isCasting) {
    if (isCasting) {
      ref.read(castProvider.notifier).toggle();
      return;
    }

    ref.read(_provider.notifier).toggle();
  }

  void _onSeek(bool isCasting, double value) {
    final seekTo = Duration(microseconds: value.toInt());

    if (isCasting) {
      ref.read(castProvider.notifier).seekTo(seekTo);
      return;
    }

    ref.read(_provider.notifier).seekTo(seekTo);
  }

  @override
  Widget build(BuildContext context) {
    final cast = ref.watch(castProvider);
    final isCasting = cast.isCasting;

    final (position, duration) = isCasting
        ? ref.watch(castProvider.select((c) => (c.currentTime, c.duration)))
        : ref.watch(_provider.select((v) => (v.position, v.duration)));

    final videoStatus = ref.watch(_provider.select((v) => v.status));
    final isPlaying = isCasting
        ? cast.castState == CastState.playing
        : videoStatus == VideoPlaybackStatus.playing || videoStatus == VideoPlaybackStatus.buffering;
    final isFinished = !isCasting && videoStatus == VideoPlaybackStatus.completed;

    ref.listen(assetViewerProvider.select((v) => v.showingControls), (prev, showing) {
      if (showing && prev != showing) {
        _hideTimer.reset();
      }
    });
    ref.listen(_provider.select((v) => v.status), (_, _) => _hideTimer.reset());

    final notifier = ref.watch(_provider.notifier);
    final isLoaded = duration != Duration.zero;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Column(
        spacing: 8,
        children: [
          Row(
            children: [
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x94000000),
                  fixedSize: const Size(44, 44),
                ),
                iconSize: 26,
                icon: isFinished
                    ? const Icon(Icons.replay_rounded, color: Colors.white)
                    : AnimatedPlayPause(color: Colors.white, playing: isPlaying),
                onPressed: () => _toggle(isCasting),
              ),
              const Spacer(),
              IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: const BoxDecoration(
                    color: Color(0x94000000),
                    borderRadius: BorderRadius.all(Radius.circular(ImmichRadius.pill)),
                  ),
                  child: Text(
                    "${position.format()} / ${duration.format()}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white38,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              year2023: false,
            ),
            child: Slider(
              value: min(position.inMicroseconds.toDouble(), duration.inMicroseconds.toDouble()),
              min: 0,
              max: max(duration.inMicroseconds.toDouble(), 1),
              padding: EdgeInsets.zero,
              onChangeStart: (_) => notifier.hold(),
              onChangeEnd: (_) => notifier.release(),
              onChanged: isLoaded ? (value) => _onSeek(isCasting, value) : null,
            ),
          ),
        ],
      ),
    );
  }
}
