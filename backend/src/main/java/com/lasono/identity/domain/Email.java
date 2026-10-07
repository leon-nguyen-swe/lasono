package com.lasono.identity.domain;

import java.util.Locale;
import java.util.regex.Pattern;

import com.lasono.identity.domain.exception.EmailInvalidException;

public final class Email {

    // RFC 5321: an address is at most 254 characters long.
    private static final int MAX_LENGTH = 254;

    // Exactly one "@", no whitespace, and a domain with at least one dot. A real check is sending a mail.
    private static final Pattern SHAPE = Pattern.compile("^[^@\\s]+@[^@\\s.]+(\\.[^@\\s.]+)+$");

    private final String value;

    public Email(String value) {
        if (value == null) {
            throw new EmailInvalidException("Email must not be null");
        }
        // Lowercase so that Alice@x.com and alice@x.com are the same account.
        String normalized = value.trim().toLowerCase(Locale.ROOT);
        if (normalized.length() > MAX_LENGTH) {
            throw new EmailInvalidException("Email must be at most " + MAX_LENGTH + " characters");
        }
        if (!SHAPE.matcher(normalized).matches()) {
            throw new EmailInvalidException("Email is not valid");
        }
        this.value = normalized;
    }

    public String getValue() {
        return this.value;
    }

    @Override
    public boolean equals(Object o) {
        return o instanceof Email other && this.value.equals(other.value);
    }

    @Override
    public int hashCode() {
        return value.hashCode();
    }
}
