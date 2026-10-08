package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.identity.domain.InMemoryRefreshTokenRepository;
import com.lasono.identity.domain.RefreshToken;
import com.lasono.identity.domain.UserId;

class LogoutUseCaseTest {

    private static final Instant NOW = Instant.parse("2026-10-08T10:00:00Z");
    private static final Duration TTL = Duration.ofDays(30);

    private InMemoryRefreshTokenRepository tokens;
    private FakeRefreshTokenCodec codec;
    private LogoutUseCase useCase;
    private UserId alice;

    @BeforeEach
    void setUp() {
        tokens = new InMemoryRefreshTokenRepository();
        codec = new FakeRefreshTokenCodec();
        useCase = new LogoutUseCase(tokens, codec, Clock.fixed(NOW, ZoneOffset.UTC));
        alice = new UserId(UUID.randomUUID());
    }

    private RefreshToken givenTokenInNewFamily(String rawValue) {
        RefreshToken token = RefreshToken.issueNewFamily(alice, codec.hash(rawValue), NOW.minusSeconds(60), TTL);
        tokens.save(token);
        return token;
    }

    private RefreshToken stored(String rawValue) {
        return tokens.findByTokenHashForUpdate(codec.hash(rawValue)).orElseThrow();
    }

    @Test
    void execute_shouldRevokeTheWholeFamilyOfTheToken() {
        RefreshToken first = givenTokenInNewFamily("first");
        first.markUsed(NOW.minusSeconds(30));
        tokens.save(first);
        tokens.save(RefreshToken.issueInFamily(first.getFamilyId(), alice, codec.hash("second"), NOW.minusSeconds(30), TTL));

        useCase.execute("second");

        assertEquals(NOW, stored("first").getRevokedAt());
        assertEquals(NOW, stored("second").getRevokedAt());
    }

    @Test
    void execute_shouldLeaveAnotherSessionOfTheSameUserAlone() {
        givenTokenInNewFamily("laptop");
        givenTokenInNewFamily("phone");

        useCase.execute("laptop");

        assertEquals(NOW, stored("laptop").getRevokedAt());
        assertNull(stored("phone").getRevokedAt());
    }

    // A logout that fails would leave the user unsure whether they are out. An unknown or missing token
    // means there is nothing to end, which is the state the user wanted anyway.
    @Test
    void execute_shouldDoNothingAndNotFailForAnUnknownOrMissingToken() {
        givenTokenInNewFamily("laptop");

        assertDoesNotThrow(() -> useCase.execute("stranger"));
        assertDoesNotThrow(() -> useCase.execute(null));
        assertDoesNotThrow(() -> useCase.execute(""));
        assertDoesNotThrow(() -> useCase.execute("   "));

        assertNull(stored("laptop").getRevokedAt());
    }

    @Test
    void execute_shouldBeSafeToCallTwiceAndKeepTheFirstMoment() {
        RefreshToken token = givenTokenInNewFamily("laptop");
        token.revoke(NOW.minusSeconds(5));
        tokens.save(token);

        assertDoesNotThrow(() -> useCase.execute("laptop"));

        assertEquals(NOW.minusSeconds(5), stored("laptop").getRevokedAt());
    }
}
