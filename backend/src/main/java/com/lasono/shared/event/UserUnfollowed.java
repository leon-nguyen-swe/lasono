package com.lasono.shared.event;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/** Fired when a user unfollows another user. */
public record UserUnfollowed(UUID followerId, UUID followeeId, Instant occurredAt) implements DomainEvent {
    public UserUnfollowed {
        Objects.requireNonNull(followerId, "followerId");
        Objects.requireNonNull(followeeId, "followeeId");
        Objects.requireNonNull(occurredAt, "occurredAt");
    }
}
