package com.lasono.shared.event;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/** Fired when a user follows another user. */
public record UserFollowed(UUID followerId, UUID followeeId, Instant occurredAt) implements DomainEvent {
    public UserFollowed {
        Objects.requireNonNull(followerId, "followerId");
        Objects.requireNonNull(followeeId, "followeeId");
        Objects.requireNonNull(occurredAt, "occurredAt");
    }
}
