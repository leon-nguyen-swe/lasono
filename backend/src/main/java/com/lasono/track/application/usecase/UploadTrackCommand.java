package com.lasono.track.application.usecase;

import java.io.InputStream;

public record UploadTrackCommand(
    String title,
    String description,
    InputStream audioData,
    long fileSize,
    String mimeType
) {}