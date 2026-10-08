package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.identity.domain.InMemoryRefreshTokenRepository;
import com.lasono.identity.domain.RefreshToken;
import com.lasono.identity.domain.RefreshTokenCheck;
import com.lasono.identity.domain.UserId;

class RefreshSessionUseCaseTest {

    private static final Instant NOW = Instant.parse("2026-10-08T10:00:00Z");
    private static final Duration TTL = Duration.ofDays(30);

    private InMemoryRefreshTokenRepository tokens;
    private FakeRefreshTokenCodec codec;
    private FakeAccessTokenIssuer accessTokenIssuer;
    private RefreshSessionUseCase useCase;
    private UserId alice;

    @BeforeEach
    void setUp() {
        tokens = new InMemoryRefreshTokenRepository();
        codec = new FakeRefreshTokenCodec();
        accessTokenIssuer = new FakeAccessTokenIssuer();
        useCase = new RefreshSessionUseCase(tokens, codec, accessTokenIssuer, Clock.fixed(NOW, ZoneOffset.UTC), TTL);
        alice = new UserId(UUID.randomUUID());
    }

    // A token the client already holds, as a login would have left it a minute ago.
    private RefreshToken givenTokenInNewFamily(String rawValue) {
        RefreshToken token = RefreshToken.issueNewFamily(alice, codec.hash(rawValue), NOW.minusSeconds(60), TTL);
        tokens.save(token);
        return token;
    }

    private RefreshToken stored(String rawValue) {
        return tokens.findByTokenHashForUpdate(codec.hash(rawValue)).orElseThrow();
    }

    @Test
    void execute_shouldGiveANewAccessTokenAndANewRefreshTokenForTheSameUser() {
        givenTokenInNewFamily("old");

        AuthSession session = useCase.execute("old");

        assertEquals(FakeAccessTokenIssuer.PREFIX + alice.getValue(), session.access().accessToken());
        assertEquals("Bearer", session.access().tokenType());
        assertEquals(FakeAccessTokenIssuer.LIFETIME_SECONDS, session.access().expiresIn());
        assertEquals("raw-1", session.refreshToken());
    }

    @Test
    void execute_shouldMarkTheOldTokenUsedAndKeepTheNewOneInTheSameFamily() {
        RefreshToken old = givenTokenInNewFamily("old");

        useCase.execute("old");

        assertEquals(NOW, stored("old").getUsedAt());
        RefreshToken replacement = stored("raw-1");
        assertEquals(old.getFamilyId(), replacement.getFamilyId());
        assertEquals(alice, replacement.getUserId());
        assertEquals(NOW.plus(TTL), replacement.getExpiresAt());
        assertEquals(RefreshTokenCheck.USABLE, replacement.check(NOW));
    }

    @Test
    void execute_shouldStoreOnlyTheHashOfTheNewToken() {
        givenTokenInNewFamily("old");

        AuthSession session = useCase.execute("old");

        assertTrue(tokens.findByTokenHashForUpdate(session.refreshToken()).isEmpty());
        assertTrue(tokens.findByTokenHashForUpdate(codec.hash(session.refreshToken())).isPresent());
    }

    @Test
    void execute_shouldLetTheNewTokenBeExchangedAgain() {
        RefreshToken old = givenTokenInNewFamily("old");

        AuthSession first = useCase.execute("old");
        AuthSession second = useCase.execute(first.refreshToken());

        assertEquals("raw-2", second.refreshToken());
        assertEquals(old.getFamilyId(), stored("raw-2").getFamilyId());
    }

    @Test
    void execute_shouldRefuseATokenItDoesNotKnowAndIssueNothing() {
        givenTokenInNewFamily("old");

        assertThrows(InvalidRefreshTokenException.class, () -> useCase.execute("stranger"));

        assertEquals(0, accessTokenIssuer.calls());
        assertTrue(tokens.findByTokenHashForUpdate(codec.hash("raw-1")).isEmpty());
    }

    @Test
    void execute_shouldRefuseAMissingOrEmptyToken() {
        assertThrows(InvalidRefreshTokenException.class, () -> useCase.execute(null));
        assertThrows(InvalidRefreshTokenException.class, () -> useCase.execute(""));
        assertThrows(InvalidRefreshTokenException.class, () -> useCase.execute("   "));
    }

    // An old cookie that ran out is not a sign of theft, so the family stays as it is.
    @Test
    void execute_shouldRefuseAnExpiredTokenWithoutRevokingTheFamily() {
        RefreshToken expired = RefreshToken.issueNewFamily(alice, codec.hash("old"), NOW.minus(TTL).minusSeconds(1), TTL);
        tokens.save(expired);

        assertThrows(InvalidRefreshTokenException.class, () -> useCase.execute("old"));

        assertNull(stored("old").getRevokedAt());
        assertEquals(0, accessTokenIssuer.calls());
    }

    @Test
    void execute_shouldRefuseARevokedToken() {
        RefreshToken revoked = givenTokenInNewFamily("old");
        revoked.revoke(NOW.minusSeconds(5));
        tokens.save(revoked);

        assertThrows(InvalidRefreshTokenException.class, () -> useCase.execute("old"));

        assertEquals(0, accessTokenIssuer.calls());
    }

    // A used token shown again means somebody holds a copy, and nobody can tell which holder is the thief.
    // So the whole family is revoked, including the newest token, and the real user has to log in again.
    @Test
    void execute_shouldRevokeTheWholeFamilyWhenAUsedTokenIsShownAgain() {
        givenTokenInNewFamily("old");
        AuthSession first = useCase.execute("old");
        int issuedBefore = accessTokenIssuer.calls();

        assertThrows(InvalidRefreshTokenException.class, () -> useCase.execute("old"));

        assertEquals(NOW, stored(first.refreshToken()).getRevokedAt());
        assertThrows(InvalidRefreshTokenException.class, () -> useCase.execute(first.refreshToken()));
        assertEquals(issuedBefore, accessTokenIssuer.calls());
    }

    @Test
    void execute_shouldLeaveAnotherSessionOfTheSameUserAloneWhenAFamilyIsRevoked() {
        givenTokenInNewFamily("old");
        givenTokenInNewFamily("phone");
        useCase.execute("old");

        assertThrows(InvalidRefreshTokenException.class, () -> useCase.execute("old"));

        assertNull(stored("phone").getRevokedAt());
        assertNotNull(useCase.execute("phone"));
    }
}
