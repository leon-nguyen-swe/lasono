package com.lasono.identity.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.identity.domain.exception.EmailAlreadyRegisteredException;

class InMemoryUserRepositoryTest {

    private InMemoryUserRepository repository;

    @BeforeEach
    void setUp() {
        repository = new InMemoryUserRepository();
    }

    @Test
    void shouldFindASavedUserByEmail() {
        User alice = aUser("alice@example.com", "Alice");

        repository.save(alice);

        assertSame(alice, repository.findByEmail(new Email("alice@example.com")).orElseThrow());
    }

    @Test
    void shouldFindASavedUserById() {
        User alice = aUser("alice@example.com", "Alice");

        repository.save(alice);

        assertSame(alice, repository.findById(alice.getId()).orElseThrow());
    }

    @Test
    void shouldNotFindAnIdThatWasNeverSaved() {
        repository.save(aUser("alice@example.com", "Alice"));

        assertTrue(repository.findById(new UserId(UUID.randomUUID())).isEmpty());
    }

    @Test
    void shouldNotFindAnEmailThatWasNeverSaved() {
        assertTrue(repository.findByEmail(new Email("nobody@example.com")).isEmpty());
    }

    @Test
    void shouldRejectASecondUserWithTheSameEmail() {
        repository.save(aUser("alice@example.com", "Alice"));

        assertThrows(
            EmailAlreadyRegisteredException.class,
            () -> repository.save(aUser("alice@example.com", "Another Alice"))
        );
        assertEquals(1, repository.size());
    }

    @Test
    void shouldSaveUsersWithDifferentEmails() {
        repository.save(aUser("alice@example.com", "Alice"));
        repository.save(aUser("bob@example.com", "Bob"));

        assertEquals(2, repository.size());
    }

    private static User aUser(String email, String name) {
        return new User(new UserId(UUID.randomUUID()), new Email(email), new DisplayName(name), "$2a$10$hash");
    }
}
