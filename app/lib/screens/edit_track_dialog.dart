import 'package:flutter/material.dart';

import '../api/track_api.dart';
import '../models/track.dart';

/// The form for the owner to change a track. It closes with the changed track,
/// or with null when nothing was saved.
class EditTrackDialog extends StatefulWidget {
  const EditTrackDialog({super.key, required this.track, required this.api});

  final Track track;
  final TrackApi api;

  @override
  State<EditTrackDialog> createState() => _EditTrackDialogState();
}

class _EditTrackDialogState extends State<EditTrackDialog> {
  late final _title = TextEditingController(text: widget.track.title);
  late final _description = TextEditingController(text: widget.track.description);
  late bool _private = widget.track.visibility == 'PRIVATE';

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final track = widget.track;
    final visibility = _private ? 'PRIVATE' : 'PUBLIC';
    // Only what changed is sent, so a change made somewhere else is not undone.
    final title = _title.text == track.title ? null : _title.text;
    final description = _description.text == track.description ? null : _description.text;
    final newVisibility = visibility == track.visibility ? null : visibility;
    if (title == null && description == null && newVisibility == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.api.updateTrack(
        track.id,
        title: title,
        description: description,
        visibility: newVisibility,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on TrackApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit track'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('editTitleField'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              key: const Key('editDescriptionField'),
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            SwitchListTile(
              key: const Key('editPrivateSwitch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Private'),
              value: _private,
              onChanged: _saving ? null : (value) => setState(() => _private = value),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelEditButton'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('saveEditButton'),
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
