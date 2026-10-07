import 'package:flutter/material.dart';

/// Shows where a track is in its life: PROCESSING while the server converts the audio, READY when
/// it can be played, FAILED when the conversion gave up.
///
/// A still hourglass marks PROCESSING, not a spinner: a spinner animates forever, which tires the
/// eye in a long list and keeps widget tests from ever settling.
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
        Icon(Icons.hourglass_top, size: 14, color: colors.onSurface),
        const SizedBox(width: 4),
        label,
      ],
    );
  }
}
