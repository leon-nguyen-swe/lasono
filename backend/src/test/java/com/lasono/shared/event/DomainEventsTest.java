package com.lasono.shared.event;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.Test;

/** Verifies that every domain event enforces non-null fields and exposes the correct timestamp. */
class DomainEventsTest {

    private static final UUID ANY_ID = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static final Instant NOW = Instant.parse("2026-01-01T00:00:00Z");

    // ── TrackLiked ──────────────────────────────────────────────────────────

    @Test
    void trackLiked_rejectsNullTrackId() {
        assertThrows(NullPointerException.class, () -> new TrackLiked(null, ANY_ID, NOW));
    }

    @Test
    void trackLiked_rejectsNullUserId() {
        assertThrows(NullPointerException.class, () -> new TrackLiked(ANY_ID, null, NOW));
    }

    @Test
    void trackLiked_rejectsNullOccurredAt() {
        assertThrows(NullPointerException.class, () -> new TrackLiked(ANY_ID, ANY_ID, null));
    }

    @Test
    void trackLiked_exposesOccurredAt() {
        assertEquals(NOW, new TrackLiked(ANY_ID, ANY_ID, NOW).occurredAt());
    }

    // ── TrackUnliked ─────────────────────────────────────────────────────────

    @Test
    void trackUnliked_rejectsNullTrackId() {
        assertThrows(NullPointerException.class, () -> new TrackUnliked(null, ANY_ID, NOW));
    }

    @Test
    void trackUnliked_rejectsNullUserId() {
        assertThrows(NullPointerException.class, () -> new TrackUnliked(ANY_ID, null, NOW));
    }

    @Test
    void trackUnliked_rejectsNullOccurredAt() {
        assertThrows(NullPointerException.class, () -> new TrackUnliked(ANY_ID, ANY_ID, null));
    }

    @Test
    void trackUnliked_exposesOccurredAt() {
        assertEquals(NOW, new TrackUnliked(ANY_ID, ANY_ID, NOW).occurredAt());
    }

    // ── UserFollowed ──────────────────────────────────────────────────────────

    @Test
    void userFollowed_rejectsNullFollowerId() {
        assertThrows(NullPointerException.class, () -> new UserFollowed(null, ANY_ID, NOW));
    }

    @Test
    void userFollowed_rejectsNullFolloweeId() {
        assertThrows(NullPointerException.class, () -> new UserFollowed(ANY_ID, null, NOW));
    }

    @Test
    void userFollowed_rejectsNullOccurredAt() {
        assertThrows(NullPointerException.class, () -> new UserFollowed(ANY_ID, ANY_ID, null));
    }

    @Test
    void userFollowed_exposesOccurredAt() {
        assertEquals(NOW, new UserFollowed(ANY_ID, ANY_ID, NOW).occurredAt());
    }

    // ── UserUnfollowed ────────────────────────────────────────────────────────

    @Test
    void userUnfollowed_rejectsNullFollowerId() {
        assertThrows(NullPointerException.class, () -> new UserUnfollowed(null, ANY_ID, NOW));
    }

    @Test
    void userUnfollowed_rejectsNullFolloweeId() {
        assertThrows(NullPointerException.class, () -> new UserUnfollowed(ANY_ID, null, NOW));
    }

    @Test
    void userUnfollowed_rejectsNullOccurredAt() {
        assertThrows(NullPointerException.class, () -> new UserUnfollowed(ANY_ID, ANY_ID, null));
    }

    @Test
    void userUnfollowed_exposesOccurredAt() {
        assertEquals(NOW, new UserUnfollowed(ANY_ID, ANY_ID, NOW).occurredAt());
    }

    // ── CommentPosted ─────────────────────────────────────────────────────────

    @Test
    void commentPosted_rejectsNullCommentId() {
        assertThrows(NullPointerException.class, () -> new CommentPosted(null, ANY_ID, ANY_ID, NOW));
    }

    @Test
    void commentPosted_rejectsNullTrackId() {
        assertThrows(NullPointerException.class, () -> new CommentPosted(ANY_ID, null, ANY_ID, NOW));
    }

    @Test
    void commentPosted_rejectsNullAuthorId() {
        assertThrows(NullPointerException.class, () -> new CommentPosted(ANY_ID, ANY_ID, null, NOW));
    }

    @Test
    void commentPosted_rejectsNullOccurredAt() {
        assertThrows(NullPointerException.class, () -> new CommentPosted(ANY_ID, ANY_ID, ANY_ID, null));
    }

    @Test
    void commentPosted_exposesOccurredAt() {
        assertEquals(NOW, new CommentPosted(ANY_ID, ANY_ID, ANY_ID, NOW).occurredAt());
    }

    // ── CommentDeleted ────────────────────────────────────────────────────────

    @Test
    void commentDeleted_rejectsNullCommentId() {
        assertThrows(NullPointerException.class, () -> new CommentDeleted(null, ANY_ID, NOW));
    }

    @Test
    void commentDeleted_rejectsNullTrackId() {
        assertThrows(NullPointerException.class, () -> new CommentDeleted(ANY_ID, null, NOW));
    }

    @Test
    void commentDeleted_rejectsNullOccurredAt() {
        assertThrows(NullPointerException.class, () -> new CommentDeleted(ANY_ID, ANY_ID, null));
    }

    @Test
    void commentDeleted_exposesOccurredAt() {
        assertEquals(NOW, new CommentDeleted(ANY_ID, ANY_ID, NOW).occurredAt());
    }

    // ── TrackDeleted ──────────────────────────────────────────────────────────

    @Test
    void trackDeleted_rejectsNullTrackId() {
        assertThrows(NullPointerException.class, () -> new TrackDeleted(null, ANY_ID, NOW));
    }

    @Test
    void trackDeleted_rejectsNullOwnerId() {
        assertThrows(NullPointerException.class, () -> new TrackDeleted(ANY_ID, null, NOW));
    }

    @Test
    void trackDeleted_rejectsNullOccurredAt() {
        assertThrows(NullPointerException.class, () -> new TrackDeleted(ANY_ID, ANY_ID, null));
    }

    @Test
    void trackDeleted_exposesOccurredAt() {
        assertEquals(NOW, new TrackDeleted(ANY_ID, ANY_ID, NOW).occurredAt());
    }
}
