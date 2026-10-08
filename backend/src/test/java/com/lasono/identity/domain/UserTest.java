package com.lasono.identity.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;

import com.lasono.identity.domain.exception.UserInvalidException;

class UserTest {

    private static final UserId ID = new UserId(UUID.randomUUID());
    private static final Email EMAIL = new Email("alice@example.com");
    private static final DisplayName NAME = new DisplayName("Alice");
    private static final String HASH = "$2a$10$notARealHashJustForTests";

    @Test
    void shouldKeepItsData() {
        User user = new User(ID, EMAIL, NAME, HASH);

        assertEquals(ID, user.getId());
        assertEquals(EMAIL, user.getEmail());
        assertEquals(NAME, user.getDisplayName());
        assertEquals(HASH, user.getPasswordHash());
    }

    @Test
    void shouldRejectMissingId() {
        assertThrows(NullPointerException.class, () -> new User(null, EMAIL, NAME, HASH));
    }

    @Test
    void shouldRejectMissingEmail() {
        assertThrows(NullPointerException.class, () -> new User(ID, null, NAME, HASH));
    }

    @Test
    void shouldRejectMissingDisplayName() {
        assertThrows(NullPointerException.class, () -> new User(ID, EMAIL, null, HASH));
    }

    // The domain only ever holds the hash of a password, never the password itself.
    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"   "})
    void shouldRejectMissingPasswordHash(String hash) {
        assertThrows(UserInvalidException.class, () -> new User(ID, EMAIL, NAME, hash));
    }

    @Test
    void shouldChangeItsDisplayNameAndKeepEverythingElse() {
        User user = new User(ID, EMAIL, NAME, HASH);

        user.changeDisplayName(new DisplayName("Alice B."));

        assertEquals(new DisplayName("Alice B."), user.getDisplayName());
        assertEquals(ID, user.getId());
        assertEquals(EMAIL, user.getEmail());
        assertEquals(HASH, user.getPasswordHash());
    }

    @Test
    void shouldKeepItsDisplayNameWhenTheNewOneIsMissing() {
        User user = new User(ID, EMAIL, NAME, HASH);

        assertThrows(NullPointerException.class, () -> user.changeDisplayName(null));

        assertEquals(NAME, user.getDisplayName());
    }
}
