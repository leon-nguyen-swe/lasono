package com.lasono.shared.event;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/** Fired when a comment is deleted from a track. */
public record CommentDeleted(UUID commentId, UUID trackId, Instant occurredAt) implements DomainEvent {
    public CommentDeleted {
        Objects.requireNonNull(commentId, "commentId");
        Objects.requireNonNull(trackId, "trackId");
        Objects.requireNonNull(occurredAt, "occurredAt");
    }
}
