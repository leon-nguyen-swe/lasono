package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.identity.domain.DisplayName;
import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.InMemoryUserRepository;
import com.lasono.identity.domain.User;
import com.lasono.identity.domain.UserId;

class GetProfileUseCaseTest {

    private InMemoryUserRepository userRepository;
    private GetProfileUseCase useCase;
    private UserId aliceId;

    @BeforeEach
    void setUp() {
        userRepository = new InMemoryUserRepository();
        useCase = new GetProfileUseCase(userRepository);
        aliceId = new UserId(UUID.randomUUID());
        userRepository.save(new User(aliceId, new Email("alice@example.com"), new DisplayName("Alice"), "$2a$10$hash"));
    }

    @Test
    void execute_shouldGiveTheIdAndTheDisplayName() {
        ProfileResult profile = useCase.execute(aliceId.getValue());

        assertEquals(aliceId.getValue().toString(), profile.userId());
        assertEquals("Alice", profile.displayName());
    }

    // A profile is public, so nothing private may be in it: not the email, not the hash.
    @Test
    void execute_shouldShowNothingPrivate() {
        ProfileResult profile = useCase.execute(aliceId.getValue());

        assertFalse(profile.toString().contains("alice@example.com"));
        assertFalse(profile.toString().contains("$2a$10$hash"));
    }

    @Test
    void execute_shouldThrowWhenNobodyHasThatId() {
        assertThrows(ProfileNotFoundException.class, () -> useCase.execute(UUID.randomUUID()));
    }
}
