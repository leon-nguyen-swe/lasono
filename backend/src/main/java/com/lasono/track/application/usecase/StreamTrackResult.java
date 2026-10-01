package com.lasono.track.application.usecase;

import java.io.InputStream;

public record StreamTrackResult(
    InputStream stream,
    String mimeType,
    long fileSize,
    long rangeStart,
    long rangeEnd,
    boolean partial
) {}