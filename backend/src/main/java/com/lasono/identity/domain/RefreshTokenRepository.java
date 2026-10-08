package com.lasono.identity.domain;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public interface RefreshTokenRepository {

    /** Stores a new token, or the new state (used, revoked) of one that is already stored. */
    void save(RefreshToken token);

    /**
     * Finds a token by the hash of its value and locks it until the surrounding transaction ends.
     * Two requests that exchange the same token therefore cannot both read it as unused: the second one
     * waits, then sees it as used.
     */
    Optional<RefreshToken> findByTokenHashForUpdate(String tokenHash);

    /** Revokes every token of the family that is not revoked yet. */
    void revokeFamily(UUID familyId, Instant now);
}
