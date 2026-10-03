import 'dart:async';

import 'package:flutter/material.dart';

import '../player_service.dart';

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.streamUrl,
  });

  final PlayerService player;
  final Uri streamUrl;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  final _subscriptions = <StreamSubscription<Object?>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
    ]);
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
        await widget.player.load(widget.streamUrl);
        _loaded = true;
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

  String _format(Duration value) {
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '${value.inMinutes}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
