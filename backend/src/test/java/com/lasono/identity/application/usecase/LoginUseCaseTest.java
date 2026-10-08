package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.identity.domain.DisplayName;
import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.InMemoryUserRepository;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;

class LoginUseCaseTest {

    private static final String PASSWORD = "correct horse";

    private InMemoryUserRepository userRepository;
    private FakePasswordHasher passwordHasher;
    private FakeAccessTokenIssuer tokenIssuer;
    private LoginUseCase useCase;
    private String aliceId;

    @BeforeEach
    void setUp() {
        userRepository = new InMemoryUserRepository();
        passwordHasher = new FakePasswordHasher();
        tokenIssuer = new FakeAccessTokenIssuer();
        useCase = new LoginUseCase(userRepository, passwordHasher, tokenIssuer);
        aliceId = new RegisterUserUseCase(userRepository, passwordHasher)
            .execute(new RegisterUserCommand("alice@example.com", "Alice", PASSWORD))
            .userId();
    }

    @Test
    void execute_shouldGiveATokenForTheRightUser() {
        LoginResult result = useCase.execute(new LoginCommand("alice@example.com", PASSWORD));

        assertEquals(FakeAccessTokenIssuer.PREFIX + aliceId, result.accessToken());
        assertEquals("Bearer", result.tokenType());
        assertEquals(FakeAccessTokenIssuer.LIFETIME_SECONDS, result.expiresIn());
    }

    @Test
    void execute_shouldIgnoreCaseAndSurroundingSpacesInTheEmail() {
        LoginResult result = useCase.execute(new LoginCommand("  ALICE@Example.com ", PASSWORD));

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

        LoginResult result = useCase.execute(new LoginCommand("old@example.com", "abc"));

        assertEquals("Bearer", result.tokenType());
    }
}
