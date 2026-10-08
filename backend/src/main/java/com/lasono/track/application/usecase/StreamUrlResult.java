package com.lasono.track.application.usecase;

import java.time.Instant;

/** An address the browser's audio player can use without a login header, valid until {@code expiresAt}. */
public record StreamUrlResult(String url, Instant expiresAt) {}
