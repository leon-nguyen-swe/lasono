import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../audio_picker.dart';
import '../models/track.dart';

class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key, this.api, this.pickAudio});

  final TrackApi? api;
  final AudioPicker? pickAudio;

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  late final TrackApi _api = widget.api ?? TrackApi();
  late final AudioPicker _pickAudio = widget.pickAudio ?? pickAudioFile;
  final _idController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  PickedAudio? _picked;
  Track? _track;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _idController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Track> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final track = await action();
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

  Future<void> _load() async {
    final id = _idController.text.trim();
    if (id.isEmpty) {
      setState(() {
        _track = null;
        _error = 'Enter a track id';
      });
      return;
    }
    await _run(() => _api.getTrack(id));
  }

  Future<void> _chooseFile() async {
    final picked = await _pickAudio();
    if (!mounted || picked == null) return;
    setState(() => _picked = picked);
  }

  Future<void> _upload() async {
    final picked = _picked;
    if (picked == null) {
      setState(() => _error = 'Choose an audio file');
      return;
    }
    await _run(() async {
      final trackId = await _api.uploadTrack(
        title: _titleController.text,
        description: _descriptionController.text,
        filename: picked.name,
        bytes: picked.bytes,
      );
      _idController.text = trackId;
      return _api.getTrack(trackId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = _track;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Upload', style: Theme.of(context).textTheme.titleMedium),
        TextField(
          key: const Key('titleField'),
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        TextField(
          key: const Key('descriptionField'),
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton(
              key: const Key('chooseFileButton'),
              onPressed: _loading ? null : _chooseFile,
              child: const Text('Choose file'),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(_picked?.name ?? 'No file chosen')),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('uploadButton'),
          onPressed: _loading ? null : _upload,
          child: const Text('Upload'),
        ),
        const Divider(height: 32),
        Text('Load by id', style: Theme.of(context).textTheme.titleMedium),
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
    );
  }
}
