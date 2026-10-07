import 'package:flutter/material.dart';

/// Shows where a track is in its life: PROCESSING while the server converts the audio, READY when
/// it can be played, FAILED when the conversion gave up.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = Text(
      status,
      style: TextStyle(color: status == 'FAILED' ? colors.error : colors.onSurface),
    );
    if (status != 'PROCESSING') return label;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        label,
      ],
    );
  }
}
