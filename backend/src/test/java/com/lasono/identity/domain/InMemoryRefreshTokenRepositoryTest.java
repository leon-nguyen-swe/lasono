package com.lasono.identity.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class InMemoryRefreshTokenRepositoryTest {

    private static final Instant NOW = Instant.parse("2026-10-08T10:00:00Z");
    private static final Duration LIFETIME = Duration.ofDays(30);
    private static final UserId USER = new UserId(UUID.randomUUID());

    private InMemoryRefreshTokenRepository repository;

    @BeforeEach
    void setUp() {
        repository = new InMemoryRefreshTokenRepository();
    }

    private static RefreshToken aToken(String hash) {
        return RefreshToken.issueNewFamily(USER, hash, NOW, LIFETIME);
    }

    @Test
    void shouldFindASavedTokenByItsHash() {
        RefreshToken token = aToken("hash-1");
        repository.save(token);

        RefreshToken found = repository.findByTokenHashForUpdate("hash-1").orElseThrow();

        assertEquals(token.getId(), found.getId());
        assertEquals(token.getFamilyId(), found.getFamilyId());
        assertEquals(USER, found.getUserId());
        assertEquals(token.getExpiresAt(), found.getExpiresAt());
    }

    @Test
    void shouldNotFindAHashThatWasNeverSaved() {
        repository.save(aToken("hash-1"));

        assertTrue(repository.findByTokenHashForUpdate("other").isEmpty());
    }

    @Test
    void shouldKeepWhatWasSavedAndNotTheObjectItself() {
        RefreshToken token = aToken("hash-1");
        repository.save(token);

        token.markUsed(NOW.plusSeconds(1));

        assertNull(repository.findByTokenHashForUpdate("hash-1").orElseThrow().getUsedAt());
    }

    @Test
    void shouldShowAChangeOnlyAfterItIsSaved() {
        repository.save(aToken("hash-1"));
        RefreshToken loaded = repository.findByTokenHashForUpdate("hash-1").orElseThrow();
        loaded.markUsed(NOW.plusSeconds(1));
        repository.save(loaded);

        assertEquals(NOW.plusSeconds(1), repository.findByTokenHashForUpdate("hash-1").orElseThrow().getUsedAt());
    }

    @Test
    void revokeFamilyShouldRevokeEveryTokenOfThatFamilyAndNoOther() {
        RefreshToken first = aToken("hash-1");
        RefreshToken second = RefreshToken.issueInFamily(first.getFamilyId(), USER, "hash-2", NOW, LIFETIME);
        RefreshToken stranger = aToken("hash-3");
        repository.save(first);
        repository.save(second);
        repository.save(stranger);

        repository.revokeFamily(first.getFamilyId(), NOW.plusSeconds(9));

        assertEquals(NOW.plusSeconds(9), repository.findByTokenHashForUpdate("hash-1").orElseThrow().getRevokedAt());
        assertEquals(NOW.plusSeconds(9), repository.findByTokenHashForUpdate("hash-2").orElseThrow().getRevokedAt());
        assertNull(repository.findByTokenHashForUpdate("hash-3").orElseThrow().getRevokedAt());
    }

    @Test
    void revokeFamilyShouldKeepAnEarlierRevocationMoment() {
        RefreshToken token = aToken("hash-1");
        token.revoke(NOW.plusSeconds(1));
        repository.save(token);

        repository.revokeFamily(token.getFamilyId(), NOW.plusSeconds(60));

        assertEquals(NOW.plusSeconds(1), repository.findByTokenHashForUpdate("hash-1").orElseThrow().getRevokedAt());
    }
}
