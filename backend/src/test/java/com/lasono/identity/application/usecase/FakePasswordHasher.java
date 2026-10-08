package com.lasono.identity.application.usecase;

import com.lasono.identity.application.port.out.PasswordHasher;

/** Fast stand-in for BCrypt that counts how often it was asked to hash. */
public class FakePasswordHasher implements PasswordHasher {

    public static final String PREFIX = "hashed:";

    private int calls;

    @Override
    public String hash(String rawPassword) {
        calls++;
        return PREFIX + rawPassword;
    }

    public int calls() {
        return calls;
    }
}
