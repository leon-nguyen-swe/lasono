package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.identity.domain.DisplayName;
import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.InMemoryRefreshTokenRepository;
import com.lasono.identity.domain.InMemoryUserRepository;
import com.lasono.identity.domain.RefreshToken;
import com.lasono.identity.domain.RefreshTokenCheck;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;

class LoginUseCaseTest {

    private static final String PASSWORD = "correct horse";
    private static final Instant NOW = Instant.parse("2026-10-08T10:00:00Z");
    private static final Duration TTL = Duration.ofDays(30);

    private InMemoryUserRepository userRepository;
    private FakePasswordHasher passwordHasher;
    private FakeAccessTokenIssuer tokenIssuer;
    private InMemoryRefreshTokenRepository refreshTokens;
    private FakeRefreshTokenCodec refreshTokenCodec;
    private LoginUseCase useCase;
    private String aliceId;

    @BeforeEach
    void setUp() {
        userRepository = new InMemoryUserRepository();
        passwordHasher = new FakePasswordHasher();
        tokenIssuer = new FakeAccessTokenIssuer();
        refreshTokens = new InMemoryRefreshTokenRepository();
        refreshTokenCodec = new FakeRefreshTokenCodec();
        useCase = new LoginUseCase(
            userRepository,
            passwordHasher,
            tokenIssuer,
            refreshTokens,
            refreshTokenCodec,
            Clock.fixed(NOW, ZoneOffset.UTC),
            TTL
        );
        aliceId = new RegisterUserUseCase(userRepository, passwordHasher)
            .execute(new RegisterUserCommand("alice@example.com", "Alice", PASSWORD))
            .userId();
    }

    @Test
    void execute_shouldGiveATokenForTheRightUser() {
        LoginResult result = useCase.execute(new LoginCommand("alice@example.com", PASSWORD)).access();

        assertEquals(FakeAccessTokenIssuer.PREFIX + aliceId, result.accessToken());
        assertEquals("Bearer", result.tokenType());
        assertEquals(FakeAccessTokenIssuer.LIFETIME_SECONDS, result.expiresIn());
    }

    @Test
    void execute_shouldGiveARefreshTokenAndKeepOnlyItsHashInTheDatabase() {
        AuthSession session = useCase.execute(new LoginCommand("alice@example.com", PASSWORD));

        assertEquals("raw-1", session.refreshToken());
        assertTrue(refreshTokens.findByTokenHashForUpdate("raw-1").isEmpty());
        RefreshToken stored = refreshTokens.findByTokenHashForUpdate(refreshTokenCodec.hash("raw-1")).orElseThrow();
        assertEquals(aliceId, stored.getUserId().getValue().toString());
        assertEquals(NOW.plus(TTL), stored.getExpiresAt());
        assertEquals(RefreshTokenCheck.USABLE, stored.check(NOW));
    }

    // Each login is its own session: logging out on one device must not end the session on another.
    @Test
    void execute_shouldStartANewFamilyForEveryLogin() {
        AuthSession laptop = useCase.execute(new LoginCommand("alice@example.com", PASSWORD));
        AuthSession phone = useCase.execute(new LoginCommand("alice@example.com", PASSWORD));

        UUID laptopFamily = refreshTokens.findByTokenHashForUpdate(refreshTokenCodec.hash(laptop.refreshToken()))
            .orElseThrow().getFamilyId();
        UUID phoneFamily = refreshTokens.findByTokenHashForUpdate(refreshTokenCodec.hash(phone.refreshToken()))
            .orElseThrow().getFamilyId();
        assertNotEquals(laptopFamily, phoneFamily);
    }

    @Test
    void execute_shouldGiveNoRefreshTokenWhenTheLoginFails() {
        assertThrows(InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("alice@example.com", "wrong horse")));
        assertThrows(InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("nobody@example.com", PASSWORD)));

        assertTrue(refreshTokens.findByTokenHashForUpdate(refreshTokenCodec.hash("raw-1")).isEmpty());
    }

    @Test
    void execute_shouldIgnoreCaseAndSurroundingSpacesInTheEmail() {
        LoginResult result = useCase.execute(new LoginCommand("  ALICE@Example.com ", PASSWORD)).access();

        assertEquals(FakeAccessTokenIssuer.PREFIX + aliceId, result.accessToken());
    }

    @Test
    void execute_shouldRefuseAWrongPasswordAndIssueNoToken() {
        assertThrows(
            InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("alice@example.com", "wrong horse"))
        );

        assertEquals(0, tokenIssuer.calls());
    }

    @Test
    void execute_shouldRefuseAnUnknownEmailAndIssueNoToken() {
        assertThrows(
            InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("nobody@example.com", PASSWORD))
        );

        assertEquals(0, tokenIssuer.calls());
    }

    // An email that is not even an email gets the same answer, not a "bad email" error.
    @Test
    void execute_shouldTreatAMalformedEmailAsInvalidCredentials() {
        assertThrows(
            InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("not-an-email", PASSWORD))
        );
    }

    @Test
    void execute_shouldTreatAMissingEmailOrPasswordAsInvalidCredentials() {
        assertThrows(InvalidCredentialsException.class, () -> useCase.execute(new LoginCommand(null, PASSWORD)));
        assertThrows(
            InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("alice@example.com", null))
        );
    }

    @Test
    void execute_shouldGiveTheSameMessageWhetherThePasswordOrTheEmailWasWrong() {
        InvalidCredentialsException wrongPassword = assertThrows(
            InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("alice@example.com", "wrong horse"))
        );
        InvalidCredentialsException unknownEmail = assertThrows(
            InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("nobody@example.com", PASSWORD))
        );

        assertEquals(wrongPassword.getMessage(), unknownEmail.getMessage());
    }

    // Comparing a password is slow on purpose. If an unknown email skipped it, the faster answer
    // would tell a stranger which emails exist. So every failure costs exactly one comparison.
    @Test
    void execute_shouldCompareOnePasswordWhateverTheReasonForFailing() {
        assertThrows(InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("alice@example.com", "wrong horse")));
        assertEquals(1, passwordHasher.matchCalls());

        assertThrows(InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("nobody@example.com", PASSWORD)));
        assertEquals(2, passwordHasher.matchCalls());

        assertThrows(InvalidCredentialsException.class,
            () -> useCase.execute(new LoginCommand("not-an-email", PASSWORD)));
        assertEquals(3, passwordHasher.matchCalls());
    }

    // The length rule belongs to choosing a password. Someone who chose theirs under an older, looser rule
    // must still be able to log in.
    @Test
    void execute_shouldNotApplyThePasswordRuleOfRegistration() {
        userRepository.save(new User(
            new UserId(UUID.randomUUID()),
            new Email("old@example.com"),
            new DisplayName("Old Timer"),
            FakePasswordHasher.PREFIX + "abc"
        ));

        LoginResult result = useCase.execute(new LoginCommand("old@example.com", "abc")).access();

        assertEquals("Bearer", result.tokenType());
    }
}
