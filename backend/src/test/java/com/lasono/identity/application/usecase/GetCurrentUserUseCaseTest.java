package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import com.lasono.identity.domain.InMemoryUserRepository;

class GetCurrentUserUseCaseTest {

    private GetCurrentUserUseCase useCase;
    private String aliceId;

    @BeforeEach
    void setUp() {
        InMemoryUserRepository userRepository = new InMemoryUserRepository();
        useCase = new GetCurrentUserUseCase(userRepository);
        aliceId = new RegisterUserUseCase(userRepository, new FakePasswordHasher())
            .execute(new RegisterUserCommand("alice@example.com", "Alice", "correct horse"))
            .userId();
    }

    @Test
    void execute_shouldReturnTheUserOfTheId() {
        CurrentUserResult result = useCase.execute(aliceId);

        assertEquals(aliceId, result.userId());
        assertEquals("alice@example.com", result.email());
        assertEquals("Alice", result.displayName());
    }

    // A token can outlive the account it was made for.
    @Test
    void execute_shouldSayNotFoundForAnIdNobodyHas() {
        assertThrows(UserNotFoundException.class, () -> useCase.execute(UUID.randomUUID().toString()));
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"not-a-uuid", "12345"})
    void execute_shouldSayNotFoundForAnIdThatIsNotAUuid(String userId) {
        assertThrows(UserNotFoundException.class, () -> useCase.execute(userId));
    }
}
