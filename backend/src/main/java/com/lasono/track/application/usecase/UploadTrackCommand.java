package com.lasono.track.application.usecase;

import java.io.InputStream;
import java.util.UUID;

public record UploadTrackCommand(
    UUID ownerId,
    String title,
    String description,
    InputStream audioData,
    long fileSize,
    String mimeType,
    String visibility
) {

    /** An upload that does not say who may see it: the track will be public. */
    public UploadTrackCommand(
        UUID ownerId,
        String title,
        String description,
        InputStream audioData,
        long fileSize,
        String mimeType
    ) {
        this(ownerId, title, description, audioData, fileSize, mimeType, null);
    }
}