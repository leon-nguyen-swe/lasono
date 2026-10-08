import 'dart:async';

import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../player_service.dart';
import 'waveform_view.dart';

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.streamUrl,
    this.waveform,
  });

  final PlayerService player;
  /// Gives the address to play. It is asked for at the first Play, because a
  /// signed address stops working after a while.
  final Future<Uri> Function() streamUrl;

  /// Peaks of the track, drawn above the slider. Null when the track has none.
  final List<double>? waveform;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  final _subscriptions = <StreamSubscription<Object?>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragMs;
  bool _playing = false;
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  // The player is shared between tracks and its streams replay their latest
  // value to new listeners (the previous track's duration/position). So we only
  // listen after this track has loaded, when those values are its own.
  void _listenToPlayer() {
    _subscriptions.addAll([
      widget.player.positionStream.listen(
        (value) => setState(() => _position = value),
      ),
      widget.player.durationStream.listen(
        (value) => setState(() => _duration = value ?? Duration.zero),
      ),
      widget.player.playingStream.listen(
        (value) => setState(() => _playing = value),
      ),
      widget.player.completedStream.listen((_) => _rewind()),
    ]);
  }

  Future<void> _rewind() async {
    setState(() {
      _dragMs = null;
      _position = Duration.zero;
    });
    await widget.player.pause();
    await widget.player.seek(Duration.zero);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    unawaited(widget.player.stop());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await widget.player.pause();
      return;
    }

    if (!_loaded) {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        await widget.player.load(await widget.streamUrl());
        _loaded = true;
        _listenToPlayer();
      } on TrackApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
        return;
      } on PlaybackException {
        if (mounted) setState(() => _error = 'Cannot play this track');
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    if (!mounted) return;
    await widget.player.play();
  }

  Future<void> _seekTo(double milliseconds) async {
    final target = Duration(milliseconds: milliseconds.round());
    setState(() {
      _dragMs = null;
      _position = target;
    });
    await widget.player.seek(target);
  }

  String _format(Duration value) {
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '${value.inMinutes}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds.toDouble();
    final canSeek = _loaded && maxMs > 0;
    final valueMs =
        canSeek ? (_dragMs ?? _position.inMilliseconds.toDouble()).clamp(0.0, maxMs) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.waveform case final peaks? when peaks.isNotEmpty)
          WaveformView(
            key: const Key('waveform'),
            peaks: peaks,
            progress: canSeek ? valueMs / maxMs : 0,
            onSeek: canSeek ? (fraction) => _seekTo(fraction * maxMs) : null,
          ),
        Slider(
          key: const Key('seekSlider'),
          min: 0,
          max: canSeek ? maxMs : 1,
          value: valueMs,
          onChanged: canSeek ? (value) => setState(() => _dragMs = value) : null,
          onChangeEnd: canSeek ? _seekTo : null,
        ),
        Row(
          children: [
            if (_loading)
              const SizedBox(
                key: Key('playerLoading'),
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                key: const Key('playButton'),
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                onPressed: _togglePlay,
              ),
            const SizedBox(width: 12),
            Text('${_format(_position)} / ${_format(_duration)}'),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
