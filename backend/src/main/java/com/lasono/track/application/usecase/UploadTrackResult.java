package com.lasono.track.application.usecase;

public record UploadTrackResult(
    String trackId,
    String title,
    String status
) {}