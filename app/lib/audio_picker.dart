import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedAudio {
  const PickedAudio({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

typedef AudioPicker = Future<PickedAudio?> Function();

/// Opens the platform file dialog for MP3/WAV. Returns null when cancelled.
/// On web there is no file path, so the whole file is read into memory.
Future<PickedAudio?> pickAudioFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['mp3', 'wav'],
  );
  if (file == null) return null;
  return PickedAudio(name: file.name, bytes: await file.readAsBytes());
}
