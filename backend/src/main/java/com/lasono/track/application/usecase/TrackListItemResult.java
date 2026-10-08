package com.lasono.track.application.usecase;

public record TrackListItemResult(
    String id,
    String title,
    String description,
    String visibility,
    String status,
    Double durationSeconds
) {}
