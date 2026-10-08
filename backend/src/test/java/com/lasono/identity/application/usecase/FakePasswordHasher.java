package com.lasono.identity.application.usecase;

import com.lasono.identity.application.port.out.PasswordHasher;

/** Fast stand-in for BCrypt that counts how often it was asked to hash. */
public class FakePasswordHasher implements PasswordHasher {

    public static final String PREFIX = "hashed:";

    private int calls;
    private int matchCalls;

    @Override
    public String hash(String rawPassword) {
        calls++;
        return PREFIX + rawPassword;
    }

    @Override
    public boolean matches(String rawPassword, String hash) {
        matchCalls++;
        return rawPassword != null && hash != null && hash.equals(PREFIX + rawPassword);
    }

    public int calls() {
        return calls;
    }

    public int matchCalls() {
        return matchCalls;
    }
}
