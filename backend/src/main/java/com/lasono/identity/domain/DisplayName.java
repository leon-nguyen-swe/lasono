package com.lasono.identity.domain;

import com.lasono.identity.domain.exception.DisplayNameInvalidException;

public final class DisplayName {

    private static final int MAX_LENGTH = 50;

    private final String value;

    public DisplayName(String value) {
        if (value == null) {
            throw new DisplayNameInvalidException("Display name must not be null");
        }
        String trimmed = value.trim();
        if (trimmed.isEmpty()) {
            throw new DisplayNameInvalidException("Display name must not be blank");
        }
        if (trimmed.length() > MAX_LENGTH) {
            throw new DisplayNameInvalidException("Display name must be at most " + MAX_LENGTH + " characters");
        }
        this.value = trimmed;
    }

    public String getValue() {
        return this.value;
    }

    @Override
    public boolean equals(Object o) {
        return o instanceof DisplayName other && this.value.equals(other.value);
    }

    @Override
    public int hashCode() {
        return value.hashCode();
    }
}
