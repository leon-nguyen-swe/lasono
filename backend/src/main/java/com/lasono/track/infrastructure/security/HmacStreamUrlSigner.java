package com.lasono.track.infrastructure.security;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.UUID;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.StreamUrlSigner;

/**
 * HMAC-SHA256 over {@code "stream:" + trackId + ":" + expiry}. The prefix says what the signature is for, so
 * it can never be taken for anything else signed with the same key. By default the key is the one that signs
 * login tokens.
 */
@Component
public class HmacStreamUrlSigner implements StreamUrlSigner {

    private static final String ALGORITHM = "HmacSHA256";
    private static final int MIN_SECRET_BYTES = 32;

    private final byte[] key;

    public HmacStreamUrlSigner(@Value("${lasono.stream.signing-secret:${lasono.jwt.secret}}") String secret) {
        if (secret == null || secret.getBytes(StandardCharsets.UTF_8).length < MIN_SECRET_BYTES) {
            throw new IllegalArgumentException("The key that signs stream addresses must be at least 32 bytes");
        }
        this.key = secret.getBytes(StandardCharsets.UTF_8);
    }

    @Override
    public String sign(UUID trackId, long expiresAtEpochSecond) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(hmac(trackId, expiresAtEpochSecond));
    }

    @Override
    public boolean isValid(UUID trackId, long expiresAtEpochSecond, String signature) {
        if (signature == null) {
            return false;
        }
        byte[] given;
        try {
            given = Base64.getUrlDecoder().decode(signature);
        } catch (IllegalArgumentException e) {
            return false;
        }
        // Compares every byte however early they differ, so the time taken does not tell how much was right.
        return MessageDigest.isEqual(given, hmac(trackId, expiresAtEpochSecond));
    }

    private byte[] hmac(UUID trackId, long expiresAtEpochSecond) {
        try {
            // A Mac keeps state while it works, so each call gets its own.
            Mac mac = Mac.getInstance(ALGORITHM);
            mac.init(new SecretKeySpec(key, ALGORITHM));
            return mac.doFinal(("stream:" + trackId + ":" + expiresAtEpochSecond).getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException e) {
            // Every Java platform must offer HmacSHA256 and the key is valid, so this cannot happen.
            throw new IllegalStateException(e);
        }
    }
}
