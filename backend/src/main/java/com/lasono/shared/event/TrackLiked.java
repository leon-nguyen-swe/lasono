package com.lasono.shared.event;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/** Fired when a user likes a track. */
public record TrackLiked(UUID trackId, UUID userId, Instant occurredAt) implements DomainEvent {
    public TrackLiked {
        Objects.requireNonNull(trackId, "trackId");
        Objects.requireNonNull(userId, "userId");
        Objects.requireNonNull(occurredAt, "occurredAt");
    }
}
