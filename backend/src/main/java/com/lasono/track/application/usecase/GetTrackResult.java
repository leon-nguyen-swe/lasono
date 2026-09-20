package com.lasono.track.application.usecase;

public record GetTrackResult(
    String id,
    String title,
    String description,
    String status,
    String mimeType,
    Double durationSeconds
) {}
