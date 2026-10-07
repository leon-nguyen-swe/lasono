package com.lasono.track.application.usecase;

import java.util.List;

public record GetTrackResult(
    String id,
    String title,
    String description,
    String status,
    String mimeType,
    Double durationSeconds,
    List<Float> waveform
) {}
