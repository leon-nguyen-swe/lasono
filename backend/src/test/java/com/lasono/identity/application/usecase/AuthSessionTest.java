package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertFalse;

import org.junit.jupiter.api.Test;

class AuthSessionTest {

    @Test
    void toString_shouldNotShowTheRefreshToken() {
        AuthSession session = new AuthSession(new LoginResult("access-abc", "Bearer", 900), "the-secret-refresh-value");

        assertFalse(session.toString().contains("the-secret-refresh-value"));
    }
}
