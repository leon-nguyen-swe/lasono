package com.lasono.shared.event;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/** Fired when a timestamped comment is posted on a track. */
public record CommentPosted(UUID commentId, UUID trackId, UUID authorId, Instant occurredAt) implements DomainEvent {
    public CommentPosted {
        Objects.requireNonNull(commentId, "commentId");
        Objects.requireNonNull(trackId, "trackId");
        Objects.requireNonNull(authorId, "authorId");
        Objects.requireNonNull(occurredAt, "occurredAt");
    }
}
