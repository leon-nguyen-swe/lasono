import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/track_api.dart' show maxUploadBytes;
import '../audio_picker.dart';
import '../core/text/file_size.dart';
import '../core/theme/theme.dart';
import '../data/repository_exception.dart';
import '../shell/app_context.dart';
import '../shell/app_shell.dart';
import '../widgets/states.dart';

/// What is wrong with a file before it is sent, in Vietnamese; null when it can be sent.
String? checkAudioFile({required String name, required int length}) {
  final lower = name.toLowerCase();
  if (!lower.endsWith('.mp3') && !lower.endsWith('.wav')) return 'Chỉ hỗ trợ file MP3 hoặc WAV.';
  if (length == 0) return 'File này trống.';
  if (length > maxUploadBytes) return 'File quá lớn (tối đa ${maxUploadBytes ~/ (1024 * 1024)} MB).';
  return null;
}

/// The title a track gets from its file: the name without the extension.
String titleFromFileName(String name) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  return base.replaceAll(RegExp(r'[_]+'), ' ').trim();
}

/// What went wrong with an upload, for a person. The server speaks English; the messages it is known to send are translated.
String describeUploadError(Object error) {
  if (error is RepositoryException && error.kind == RepositoryErrorKind.invalid) {
    final message = error.message;
    if (message.startsWith('File too large')) return 'File quá lớn (tối đa ${maxUploadBytes ~/ (1024 * 1024)} MB).';
    if (message.contains('Unsupported audio format') || message.contains('Only MP3 and WAV')) {
      return 'Định dạng này chưa được hỗ trợ. Hãy dùng file MP3 hoặc WAV.';
    }
    if (message == 'Upload timed out') return 'Tải lên quá lâu. Hãy kiểm tra mạng rồi thử lại.';
    if (message == 'Enter a title') return 'Hãy nhập tiêu đề.';
    if (message == 'File is empty') return 'File này trống.';
  }
  return errorMessageFor(error);
}

/// Upload a track: choose or drop a file, give it a title, and send it. The server then processes the audio, so the
/// user is taken to the track page, which shows it as "processing" until it is ready.
class UploadPage extends StatefulWidget {
  const UploadPage({super.key, this.pickAudio});

  /// The file dialog; a test gives its own.
  final AudioPicker? pickAudio;

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  PickedAudio? _picked;
  bool _private = false;
  bool _dragging = false;
  bool _uploading = false;
  String? _fileError;
  String? _titleError;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    if (_uploading) return;
    final pick = widget.pickAudio ?? pickAudioFile;
    final picked = await pick();
    if (picked != null && mounted) _accept(picked);
  }

  Future<void> _dropped(List<DropItem> files) async {
    if (_uploading || files.isEmpty) return;
    final file = files.first;
    final bytes = await file.readAsBytes();
    if (mounted) _accept(PickedAudio(name: file.name, bytes: bytes));
  }

  void _accept(PickedAudio picked) {
    final problem = checkAudioFile(name: picked.name, length: picked.bytes.length);
    setState(() {
      _error = null;
      _fileError = problem;
      if (problem != null) return;
      _picked = picked;
      // Keep a title the user already typed; fill it from the file name otherwise.
      if (_title.text.trim().isEmpty) _title.text = titleFromFileName(picked.name);
      _titleError = null;
    });
  }

  Future<void> _upload() async {
    final picked = _picked;
    if (picked == null || _uploading) return;
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = 'Hãy nhập tiêu đề.');
      return;
    }
    final repos = context.repos;
    setState(() {
      _uploading = true;
      _error = null;
      _titleError = null;
    });
    try {
      final id = await repos.tracks.uploadTrack(
        title: _title.text.trim(),
        description: _description.text.trim(),
        visibility: _private ? 'PRIVATE' : 'PUBLIC',
        filename: picked.name,
        bytes: picked.bytes,
      );
      if (mounted) context.go('/tracks/${Uri.encodeComponent(id)}');
    } on RepositoryException catch (e) {
      if (mounted) setState(() => _error = describeUploadError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = AppColors.of(context);
    return SingleChildScrollView(
      child: PageContainer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tải bài hát lên', key: const Key('uploadTitle'), style: text.headlineMedium),
                const SizedBox(height: AppSpacing.xs),
                Text('MP3 hoặc WAV, tối đa 50 MB.', style: text.bodyMedium?.copyWith(color: c.textSecondary)),
                const SizedBox(height: AppSpacing.xl),
                _dropZone(context),
                if (_fileError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_fileError!, key: const Key('fileError'), style: text.bodyMedium?.copyWith(color: c.error)),
                ],
                if (_picked != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _form(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropZone(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final picked = _picked;
    return DropTarget(
      enable: !_uploading,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        _dropped(details.files);
      },
      child: Material(
        color: _dragging ? c.accentSoft : c.surface,
        borderRadius: AppRadius.all(AppRadius.lg),
        child: InkWell(
          key: const Key('dropZone'),
          borderRadius: AppRadius.all(AppRadius.lg),
          onTap: _uploading ? null : _choose,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              borderRadius: AppRadius.all(AppRadius.lg),
              border: Border.all(color: _dragging ? c.accent : c.inputBorder, width: _dragging ? 2 : 1.5),
            ),
            child: picked == null
                ? Column(
                    children: [
                      Icon(Icons.cloud_upload_outlined, size: 48, color: c.accent),
                      const SizedBox(height: AppSpacing.md),
                      Text('Kéo thả file vào đây', style: text.titleMedium, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.xs),
                      Text('hoặc bấm để chọn từ máy', style: text.bodyMedium?.copyWith(color: c.textSecondary), textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.lg),
                      OutlinedButton(key: const Key('pickButton'), onPressed: _choose, child: const Text('Chọn file')),
                    ],
                  )
                : Row(
                    children: [
                      Icon(Icons.audio_file_outlined, size: 40, color: c.accent),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(picked.name, key: const Key('pickedName'), maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                            Text(formatFileSize(picked.bytes.length), key: const Key('pickedSize'), style: text.bodySmall?.copyWith(color: c.textSecondary)),
                          ],
                        ),
                      ),
                      TextButton(key: const Key('changeFileButton'), onPressed: _uploading ? null : _choose, child: const Text('Đổi file')),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('titleField'),
          controller: _title,
          enabled: !_uploading,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: 'Tiêu đề', errorText: _titleError),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: const Key('descriptionField'),
          controller: _description,
          enabled: !_uploading,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Mô tả (không bắt buộc)'),
        ),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile(
          key: const Key('privateSwitch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Riêng tư'),
          subtitle: const Text('Chỉ mình bạn thấy và nghe được. Có thể đổi sau.'),
          value: _private,
          onChanged: _uploading ? null : (value) => setState(() => _private = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            key: const Key('uploadError'),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: c.error.withValues(alpha: 0.12), borderRadius: AppRadius.all(AppRadius.md)),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 20, color: c.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_error!, style: text.bodySmall?.copyWith(color: c.textPrimary))),
              ],
            ),
          ),
        ],
        if (_uploading) ...[
          const SizedBox(height: AppSpacing.lg),
          const LinearProgressIndicator(key: Key('uploadProgress')),
          const SizedBox(height: AppSpacing.sm),
          Text('Đang tải lên… đừng đóng trang này.', style: text.bodySmall?.copyWith(color: c.textSecondary)),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          key: const Key('uploadSubmit'),
          onPressed: _uploading ? null : _upload,
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(_uploading ? 'Đang tải lên…' : 'Tải lên'),
        ),
      ],
    );
  }
}
