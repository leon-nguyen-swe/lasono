package com.lasono.track.application.port.out;

import java.time.Instant;
import java.util.UUID;

import com.lasono.track.domain.model.TrackStatus;
import com.lasono.track.domain.model.Visibility;

/**
 * The few fields of a track the list needs, without loading the whole track and its audio.
 * {@code durationMs} is null until the audio has been processed.
 */
public record TrackSummary(
    UUID id,
    UUID ownerId,
    String title,
    String description,
    Visibility visibility,
    TrackStatus status,
    Instant createdAt,
    Long durationMs) {
}
