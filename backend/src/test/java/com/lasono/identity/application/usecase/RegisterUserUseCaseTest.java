package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.InMemoryUserRepository;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.exception.DisplayNameInvalidException;
import com.lasono.identity.domain.exception.EmailAlreadyRegisteredException;
import com.lasono.identity.domain.exception.EmailInvalidException;

class RegisterUserUseCaseTest {

    private static final String PASSWORD = "correct horse";

    private InMemoryUserRepository userRepository;
    private FakePasswordHasher passwordHasher;
    private RegisterUserUseCase useCase;

    @BeforeEach
    void setUp() {
        userRepository = new InMemoryUserRepository();
        passwordHasher = new FakePasswordHasher();
        useCase = new RegisterUserUseCase(userRepository, passwordHasher);
    }

    @Test
    void execute_shouldReturnTheNewUser() {
        RegisterUserResult result = useCase.execute(aRegistration());

        assertEquals("alice@example.com", result.email());
        assertEquals("Alice", result.displayName());
        // The id must be a valid UUID.
        UUID.fromString(result.userId());
    }

    @Test
    void execute_shouldNormalizeTheEmailAndTrimTheDisplayName() {
        RegisterUserResult result = useCase.execute(
            new RegisterUserCommand("  Alice@Example.COM ", "  Alice  ", PASSWORD)
        );

        assertEquals("alice@example.com", result.email());
        assertEquals("Alice", result.displayName());
    }

    @Test
    void execute_shouldSaveTheUser() {
        RegisterUserResult result = useCase.execute(aRegistration());

        User saved = userRepository.findByEmail(new Email("alice@example.com")).orElseThrow();
        assertEquals(result.userId(), saved.getId().getValue().toString());
        assertEquals("Alice", saved.getDisplayName().getValue());
    }

    @Test
    void execute_shouldStoreTheHashAndNeverThePassword() {
        useCase.execute(aRegistration());

        User saved = userRepository.findByEmail(new Email("alice@example.com")).orElseThrow();
        assertNotEquals(PASSWORD, saved.getPasswordHash());
        assertEquals(FakePasswordHasher.PREFIX + PASSWORD, saved.getPasswordHash());
    }

    @Test
    void execute_shouldRejectAnEmailThatIsAlreadyRegistered() {
        useCase.execute(aRegistration());

        assertThrows(EmailAlreadyRegisteredException.class, () -> useCase.execute(aRegistration()));
    }

    @Test
    void execute_shouldTreatEmailsThatDifferOnlyByCaseAsTheSame() {
        useCase.execute(aRegistration());

        assertThrows(
            EmailAlreadyRegisteredException.class,
            () -> useCase.execute(new RegisterUserCommand("ALICE@Example.com", "Other", PASSWORD))
        );
    }

    @Test
    void execute_shouldKeepTheFirstUserWhenTheEmailIsTaken() {
        useCase.execute(aRegistration());

        assertThrows(
            EmailAlreadyRegisteredException.class,
            () -> useCase.execute(new RegisterUserCommand("alice@example.com", "Impostor", "another password"))
        );

        User saved = userRepository.findByEmail(new Email("alice@example.com")).orElseThrow();
        assertEquals("Alice", saved.getDisplayName().getValue());
        assertEquals(FakePasswordHasher.PREFIX + PASSWORD, saved.getPasswordHash());
    }

    @Test
    void execute_shouldRejectAnInvalidEmailAndSaveNothing() {
        assertThrows(
            EmailInvalidException.class,
            () -> useCase.execute(new RegisterUserCommand("not-an-email", "Alice", PASSWORD))
        );

        assertEquals(0, userRepository.size());
    }

    @Test
    void execute_shouldRejectAnInvalidDisplayNameAndSaveNothing() {
        assertThrows(
            DisplayNameInvalidException.class,
            () -> useCase.execute(new RegisterUserCommand("alice@example.com", "   ", PASSWORD))
        );

        assertEquals(0, userRepository.size());
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"1234567", "        "})
    void execute_shouldRejectAPasswordThatIsMissingBlankOrShorterThan8(String password) {
        assertThrows(
            PasswordInvalidException.class,
            () -> useCase.execute(new RegisterUserCommand("alice@example.com", "Alice", password))
        );

        assertEquals(0, userRepository.size());
    }

    @Test
    void execute_shouldAcceptAPasswordOfExactly8Characters() {
        useCase.execute(new RegisterUserCommand("alice@example.com", "Alice", "12345678"));

        assertEquals(1, userRepository.size());
    }

    // BCrypt only reads the first 72 bytes and silently ignores the rest.
    @Test
    void execute_shouldAcceptAPasswordOfExactly72Bytes() {
        useCase.execute(new RegisterUserCommand("alice@example.com", "Alice", "a".repeat(72)));

        assertEquals(1, userRepository.size());
    }

    @Test
    void execute_shouldRejectAPasswordOfMoreThan72Bytes() {
        assertThrows(
            PasswordInvalidException.class,
            () -> useCase.execute(new RegisterUserCommand("alice@example.com", "Alice", "a".repeat(73)))
        );
    }

    // 25 characters, but each "ế" takes 3 bytes in UTF-8, so 75 bytes in total.
    @Test
    void execute_shouldCountBytesAndNotCharactersWhenLimitingThePassword() {
        assertThrows(
            PasswordInvalidException.class,
            () -> useCase.execute(new RegisterUserCommand("alice@example.com", "Alice", "ế".repeat(25)))
        );
    }

    // BCrypt is slow on purpose, so cheap checks must come first.
    @Test
    void execute_shouldNotHashWhenTheInputIsInvalid() {
        assertThrows(
            EmailInvalidException.class,
            () -> useCase.execute(new RegisterUserCommand("not-an-email", "Alice", PASSWORD))
        );
        assertThrows(
            PasswordInvalidException.class,
            () -> useCase.execute(new RegisterUserCommand("alice@example.com", "Alice", "short"))
        );

        assertEquals(0, passwordHasher.calls());
    }

    private static RegisterUserCommand aRegistration() {
        return new RegisterUserCommand("alice@example.com", "Alice", PASSWORD);
    }
}
