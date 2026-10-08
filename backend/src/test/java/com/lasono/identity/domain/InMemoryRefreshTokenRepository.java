package com.lasono.identity.domain;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * Keeps what was saved, not the object itself: like a database, a change the caller did not
 * {@link #save} is not visible to the next {@link #findByTokenHashForUpdate}.
 */
public class InMemoryRefreshTokenRepository implements RefreshTokenRepository {

    private final Map<String, RefreshToken> byHash = new LinkedHashMap<>();

    @Override
    public void save(RefreshToken token) {
        byHash.put(token.getTokenHash(), copy(token));
    }

    @Override
    public Optional<RefreshToken> findByTokenHashForUpdate(String tokenHash) {
        return Optional.ofNullable(byHash.get(tokenHash)).map(InMemoryRefreshTokenRepository::copy);
    }

    @Override
    public void revokeFamily(UUID familyId, Instant now) {
        byHash.values().stream()
            .filter(token -> token.getFamilyId().equals(familyId))
            .forEach(token -> token.revoke(now));
    }

    private static RefreshToken copy(RefreshToken token) {
        return RefreshToken.reconstitute(
            token.getId(),
            token.getFamilyId(),
            token.getUserId(),
            token.getTokenHash(),
            token.getExpiresAt(),
            token.getUsedAt(),
            token.getRevokedAt()
        );
    }
}
