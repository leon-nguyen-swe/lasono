import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../models/track.dart';

class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, this.api});

  final TrackApi? api;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  late final TrackApi _api = widget.api ?? TrackApi();
  final _idController = TextEditingController();

  Track? _track;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _idController.text.trim();
    if (id.isEmpty) {
      setState(() {
        _track = null;
        _error = 'Enter a track id';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final track = await _api.getTrack(id);
      if (!mounted) return;
      setState(() => _track = track);
    } on TrackApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _track = null;
        _error = e.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('trackIdField'),
            controller: _idController,
            decoration: const InputDecoration(labelText: 'Track id'),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('loadButton'),
            onPressed: _loading ? null : _load,
            child: const Text('Load'),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (track != null) ...[
            Text(track.title, style: Theme.of(context).textTheme.titleLarge),
            Text(track.description),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Status: '),
                Text(track.status),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
