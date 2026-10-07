package com.lasono.identity.application.usecase;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class RegisterUserCommandTest {

    // A record prints every field in toString(), so a logged command would leak the password.
    @Test
    void toString_shouldNotContainThePassword() {
        RegisterUserCommand command = new RegisterUserCommand("alice@example.com", "Alice", "s3cret-pass");

        assertFalse(command.toString().contains("s3cret-pass"));
    }

    @Test
    void toString_shouldStillShowTheEmail() {
        RegisterUserCommand command = new RegisterUserCommand("alice@example.com", "Alice", "s3cret-pass");

        assertTrue(command.toString().contains("alice@example.com"));
    }
}
