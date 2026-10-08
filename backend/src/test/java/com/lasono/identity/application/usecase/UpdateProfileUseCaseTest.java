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
import com.lasono.identity.domain.exception.DisplayNameInvalidException;

class UpdateProfileUseCaseTest {

    private InMemoryUserRepository userRepository;
    private UpdateProfileUseCase useCase;
    private UserId aliceId;

    @BeforeEach
    void setUp() {
        userRepository = new InMemoryUserRepository();
        useCase = new UpdateProfileUseCase(userRepository);
        aliceId = new UserId(UUID.randomUUID());
        userRepository.save(new User(aliceId, new Email("alice@example.com"), new DisplayName("Alice"), "$2a$10$hash"));
    }

    private User stored() {
        return userRepository.findById(aliceId).orElseThrow();
    }

    @Test
    void execute_shouldChangeTheDisplayNameAndGiveTheAccountBack() {
        CurrentUserResult result = useCase.execute(aliceId.getValue(), "Alice B.");

        assertEquals("Alice B.", result.displayName());
        assertEquals("alice@example.com", result.email());
        assertEquals(aliceId.getValue().toString(), result.userId());
        assertEquals("Alice B.", stored().getDisplayName().getValue());
    }

    @Test
    void execute_shouldTrimTheNameLikeRegistrationDoes() {
        useCase.execute(aliceId.getValue(), "  Alice B.  ");

        assertEquals("Alice B.", stored().getDisplayName().getValue());
    }

    @Test
    void execute_shouldKeepTheEmailAndThePasswordHash() {
        useCase.execute(aliceId.getValue(), "Alice B.");

        assertEquals("alice@example.com", stored().getEmail().getValue());
        assertEquals("$2a$10$hash", stored().getPasswordHash());
    }

    @Test
    void execute_shouldRefuseABlankOrTooLongOrMissingNameAndChangeNothing() {
        assertThrows(DisplayNameInvalidException.class, () -> useCase.execute(aliceId.getValue(), "   "));
        assertThrows(DisplayNameInvalidException.class, () -> useCase.execute(aliceId.getValue(), "x".repeat(51)));
        assertThrows(DisplayNameInvalidException.class, () -> useCase.execute(aliceId.getValue(), null));

        assertEquals("Alice", stored().getDisplayName().getValue());
    }

    // The account of a valid token can be gone; the token proves nothing then, which is how /users/me treats it.
    @Test
    void execute_shouldThrowWhenTheAccountIsGone() {
        assertThrows(UserNotFoundException.class, () -> useCase.execute(UUID.randomUUID(), "Alice B."));
    }
}
