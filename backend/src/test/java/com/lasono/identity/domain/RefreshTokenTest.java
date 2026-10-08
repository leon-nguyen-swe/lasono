package com.lasono.identity.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import com.lasono.identity.domain.exception.RefreshTokenInvalidStateException;

class RefreshTokenTest {

    private static final Instant NOW = Instant.parse("2026-10-08T10:00:00Z");
    private static final Duration LIFETIME = Duration.ofDays(30);
    private static final UserId USER = new UserId(UUID.randomUUID());

    private static RefreshToken aToken() {
        return RefreshToken.issueNewFamily(USER, "hash-1", NOW, LIFETIME);
    }

    @Test
    void aNewTokenIsUsableAndExpiresAfterItsLifetime() {
        RefreshToken token = aToken();

        assertEquals(RefreshTokenCheck.USABLE, token.check(NOW));
        assertEquals(NOW.plus(LIFETIME), token.getExpiresAt());
        assertNull(token.getUsedAt());
        assertNull(token.getRevokedAt());
        assertEquals(USER, token.getUserId());
        assertEquals("hash-1", token.getTokenHash());
    }

    @Test
    void aLoginStartsANewFamilyEachTime() {
        assertNotEquals(aToken().getFamilyId(), aToken().getFamilyId());
    }

    @Test
    void theReplacementOfAUsedTokenStaysInItsFamily() {
        RefreshToken first = aToken();

        RefreshToken second = RefreshToken.issueInFamily(first.getFamilyId(), USER, "hash-2", NOW, LIFETIME);

        assertEquals(first.getFamilyId(), second.getFamilyId());
        assertNotEquals(first.getId(), second.getId());
    }

    @Test
    void aTokenIsExpiredFromTheMomentOfItsExpiryOn() {
        RefreshToken token = aToken();

        assertEquals(RefreshTokenCheck.USABLE, token.check(token.getExpiresAt().minusSeconds(1)));
        assertEquals(RefreshTokenCheck.EXPIRED, token.check(token.getExpiresAt()));
        assertEquals(RefreshTokenCheck.EXPIRED, token.check(token.getExpiresAt().plusSeconds(1)));
    }

    @Test
    void aUsedTokenIsReportedAsAlreadyUsed() {
        RefreshToken token = aToken();

        token.markUsed(NOW.plusSeconds(5));

        assertEquals(RefreshTokenCheck.ALREADY_USED, token.check(NOW.plusSeconds(6)));
        assertEquals(NOW.plusSeconds(5), token.getUsedAt());
    }

    @Test
    void aTokenCanBeUsedOnlyOnce() {
        RefreshToken token = aToken();
        token.markUsed(NOW.plusSeconds(5));

        assertThrows(RefreshTokenInvalidStateException.class, () -> token.markUsed(NOW.plusSeconds(6)));
    }

    @Test
    void aRevokedTokenIsReportedAsRevoked() {
        RefreshToken token = aToken();

        token.revoke(NOW.plusSeconds(5));

        assertEquals(RefreshTokenCheck.REVOKED, token.check(NOW.plusSeconds(6)));
        assertEquals(NOW.plusSeconds(5), token.getRevokedAt());
    }

    @Test
    void revokedOutranksUsedAndExpired() {
        RefreshToken token = aToken();
        token.markUsed(NOW.plusSeconds(5));
        token.revoke(NOW.plusSeconds(6));

        assertEquals(RefreshTokenCheck.REVOKED, token.check(NOW.plusSeconds(7)));
        assertEquals(RefreshTokenCheck.REVOKED, token.check(token.getExpiresAt().plusSeconds(1)));
    }

    @Test
    void aUsedTokenShownAfterItsExpiryIsStillReportedAsReuse() {
        RefreshToken token = aToken();
        token.markUsed(NOW.plusSeconds(5));

        assertEquals(RefreshTokenCheck.ALREADY_USED, token.check(token.getExpiresAt().plusSeconds(1)));
    }

    @Test
    void revokingTwiceKeepsTheFirstMoment() {
        RefreshToken token = aToken();
        token.revoke(NOW.plusSeconds(5));

        token.revoke(NOW.plusSeconds(60));

        assertEquals(NOW.plusSeconds(5), token.getRevokedAt());
    }

    @Test
    void anExpiredOrRevokedTokenCannotBeUsed() {
        RefreshToken expired = aToken();
        RefreshToken revoked = aToken();
        revoked.revoke(NOW.plusSeconds(1));

        assertThrows(RefreshTokenInvalidStateException.class, () -> expired.markUsed(expired.getExpiresAt()));
        assertThrows(RefreshTokenInvalidStateException.class, () -> revoked.markUsed(NOW.plusSeconds(2)));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   "})
    void aTokenNeedsAHash(String hash) {
        assertThrows(
            RefreshTokenInvalidStateException.class,
            () -> RefreshToken.issueNewFamily(USER, hash, NOW, LIFETIME)
        );
    }
}
