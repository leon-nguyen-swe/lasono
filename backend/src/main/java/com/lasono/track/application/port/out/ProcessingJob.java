package com.lasono.track.application.port.out;

import java.util.UUID;

import com.lasono.track.domain.TrackId;

/** A job a worker has claimed. {@code attempts} counts this attempt. */
public record ProcessingJob(UUID id, TrackId trackId, int attempts, int maxAttempts) {}
