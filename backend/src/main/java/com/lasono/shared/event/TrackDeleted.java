package com.lasono.shared.event;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/**
 * Fired by the track module when a track is deleted.
 * The engagement module listens to this event to cascade-delete likes and comments of that track.
 */
public record TrackDeleted(UUID trackId, UUID ownerId, Instant occurredAt) implements DomainEvent {
    public TrackDeleted {
        Objects.requireNonNull(trackId, "trackId");
        Objects.requireNonNull(ownerId, "ownerId");
        Objects.requireNonNull(occurredAt, "occurredAt");
    }
}
