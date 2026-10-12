package com.lasono.shared.event;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/** Fired when a user removes their like from a track. */
public record TrackUnliked(UUID trackId, UUID userId, Instant occurredAt) implements DomainEvent {
    public TrackUnliked {
        Objects.requireNonNull(trackId, "trackId");
        Objects.requireNonNull(userId, "userId");
        Objects.requireNonNull(occurredAt, "occurredAt");
    }
}
