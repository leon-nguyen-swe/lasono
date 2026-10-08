package com.lasono.identity.infrastructure.security;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Objects;

import org.springframework.stereotype.Component;

import com.lasono.identity.application.port.out.RefreshTokenCodec;

/**
 * The value is 256 random bits, so it cannot be guessed and does not need a slow hash like a password
 * does. A plain SHA-256 is enough to make a stolen database useless for logging in.
 */
@Component
public class Sha256RefreshTokenCodec implements RefreshTokenCodec {

    private static final int TOKEN_BYTES = 32;

    private final SecureRandom random = new SecureRandom();

    @Override
    public String generate() {
        byte[] bytes = new byte[TOKEN_BYTES];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    @Override
    public String hash(String rawToken) {
        Objects.requireNonNull(rawToken, "rawToken");
        try {
            // A MessageDigest keeps state while it works, so each call gets its own.
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(rawToken.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            // Every Java platform must offer SHA-256, so this cannot happen.
            throw new IllegalStateException(e);
        }
    }
}
