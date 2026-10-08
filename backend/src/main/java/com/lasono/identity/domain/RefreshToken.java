package com.lasono.identity.domain;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import com.lasono.identity.domain.exception.RefreshTokenInvalidStateException;

public class RefreshToken {

    private final UUID id;
    private final UUID familyId;
    private final UserId userId;
    private final String tokenHash;
    private final Instant expiresAt;
    private Instant usedAt;
    private Instant revokedAt;

    private RefreshToken(
        UUID id,
        UUID familyId,
        UserId userId,
        String tokenHash,
        Instant expiresAt,
        Instant usedAt,
        Instant revokedAt
    ) {
        // Only the hash of a token is kept, and a token without one could never be found again.
        if (tokenHash == null || tokenHash.isBlank()) {
            throw new RefreshTokenInvalidStateException("A refresh token needs the hash of its value");
        }
        this.id = id;
        this.familyId = familyId;
        this.userId = userId;
        this.tokenHash = tokenHash;
        this.expiresAt = expiresAt;
        this.usedAt = usedAt;
        this.revokedAt = revokedAt;
    }

    /** The first token of a login: it starts a new family. */
    public static RefreshToken issueNewFamily(UserId userId, String tokenHash, Instant now, Duration timeToLive) {
        return new RefreshToken(UUID.randomUUID(), UUID.randomUUID(), userId, tokenHash, now.plus(timeToLive), null, null);
    }

    /** The token that replaces a used one: it stays in the family of the token it replaces. */
    public static RefreshToken issueInFamily(
        UUID familyId,
        UserId userId,
        String tokenHash,
        Instant now,
        Duration timeToLive
    ) {
        return new RefreshToken(UUID.randomUUID(), familyId, userId, tokenHash, now.plus(timeToLive), null, null);
    }

    public static RefreshToken reconstitute(
        UUID id,
        UUID familyId,
        UserId userId,
        String tokenHash,
        Instant expiresAt,
        Instant usedAt,
        Instant revokedAt
    ) {
        return new RefreshToken(id, familyId, userId, tokenHash, expiresAt, usedAt, revokedAt);
    }

    public RefreshTokenCheck check(Instant now) {
        // Revoked first, then used, then expired. A used token shown after its expiry is still a reuse:
        // it proves somebody holds a copy, which matters more than the fact that it has also run out.
        if (revokedAt != null) {
            return RefreshTokenCheck.REVOKED;
        }
        if (usedAt != null) {
            return RefreshTokenCheck.ALREADY_USED;
        }
        if (!now.isBefore(expiresAt)) {
            return RefreshTokenCheck.EXPIRED;
        }
        return RefreshTokenCheck.USABLE;
    }

    public void markUsed(Instant now) {
        RefreshTokenCheck state = check(now);
        if (state != RefreshTokenCheck.USABLE) {
            throw new RefreshTokenInvalidStateException("Cannot use a refresh token that is " + state);
        }
        this.usedAt = now;
    }

    /** Safe to call again: the first moment is kept. */
    public void revoke(Instant now) {
        if (this.revokedAt == null) {
            this.revokedAt = now;
        }
    }

    public UUID getId() {
        return this.id;
    }

    public UUID getFamilyId() {
        return this.familyId;
    }

    public UserId getUserId() {
        return this.userId;
    }

    public String getTokenHash() {
        return this.tokenHash;
    }

    public Instant getExpiresAt() {
        return this.expiresAt;
    }

    public Instant getUsedAt() {
        return this.usedAt;
    }

    public Instant getRevokedAt() {
        return this.revokedAt;
    }
}
