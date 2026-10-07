package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class LoginCommandTest {

    // A record prints every field in toString(), so a logged command would leak the password.
    @Test
    void toString_shouldNotContainThePassword() {
        LoginCommand command = new LoginCommand("alice@example.com", "s3cret-pass");

        assertFalse(command.toString().contains("s3cret-pass"));
        assertTrue(command.toString().contains("alice@example.com"));
    }
}
