package com.lasono.track.application.usecase;

import java.io.InputStream;

public record UploadTrackCommand(
    String title,
    String description,
    InputStream audioData,
    String originalFileName,
    long fileSize,
    String mimeType
) {}