package com.lasono.identity.infrastructure.security;

import java.nio.charset.StandardCharsets;

import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Component;

import com.lasono.identity.application.port.out.PasswordHasher;

@Component
public class BCryptPasswordHasher implements PasswordHasher {

    // Cost 10 means 2^10 rounds. Each +1 doubles the time, for the login and for an attacker alike.
    private static final int COST = 10;

    private static final int MAX_PASSWORD_BYTES = 72;

    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(COST);

    @Override
    public String hash(String rawPassword) {
        return encoder.encode(rawPassword);
    }

    @Override
    public boolean matches(String rawPassword, String hash) {
        // BCrypt reads only the first 72 bytes, so a longer password would match the hash of its own first
        // 72 bytes and a typo at the end would still log in. Refusing it also saves hashing a huge input.
        if (rawPassword != null && rawPassword.getBytes(StandardCharsets.UTF_8).length > MAX_PASSWORD_BYTES) {
            return false;
        }
        return encoder.matches(rawPassword, hash);
    }
}
