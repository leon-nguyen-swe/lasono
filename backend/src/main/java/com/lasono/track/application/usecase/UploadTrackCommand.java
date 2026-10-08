package com.lasono.track.application.usecase;

import java.io.InputStream;
import java.util.UUID;

public record UploadTrackCommand(
    UUID ownerId,
    String title,
    String description,
    InputStream audioData,
    long fileSize,
    String mimeType
) {}