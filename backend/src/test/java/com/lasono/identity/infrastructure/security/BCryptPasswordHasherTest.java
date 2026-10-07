package com.lasono.identity.infrastructure.security;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

class BCryptPasswordHasherTest {

    private static final String PASSWORD = "correct horse";

    private final BCryptPasswordHasher hasher = new BCryptPasswordHasher();

    // matches() is how a login will later check a password, so it is the proof that the hash is usable.
    private final BCryptPasswordEncoder verifier = new BCryptPasswordEncoder();

    @Test
    void hash_shouldNotReturnThePassword() {
        assertNotEquals(PASSWORD, hasher.hash(PASSWORD));
    }

    @Test
    void hash_shouldBeA60CharacterBCryptHashWithCost10() {
        String hash = hasher.hash(PASSWORD);

        assertTrue(hash.startsWith("$2a$10$"), hash);
        assertEquals(60, hash.length());
    }

    @Test
    void hash_shouldMatchTheRightPasswordOnly() {
        String hash = hasher.hash(PASSWORD);

        assertTrue(verifier.matches(PASSWORD, hash));
        assertFalse(verifier.matches("wrong horse", hash));
    }

    @Test
    void hash_shouldDifferEachTimeBecauseOfTheSalt() {
        assertNotEquals(hasher.hash(PASSWORD), hasher.hash(PASSWORD));
    }

    // 24 x "ế" is exactly 72 bytes in UTF-8, the longest password the use case accepts.
    @Test
    void hash_shouldWorkForTheLongestAllowedVietnamesePassword() {
        String password = "ế".repeat(24);

        assertTrue(verifier.matches(password, hasher.hash(password)));
    }
}
