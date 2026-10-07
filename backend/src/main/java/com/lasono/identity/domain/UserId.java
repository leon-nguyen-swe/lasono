package com.lasono.identity.domain;

import java.util.Objects;
import java.util.UUID;

public final class UserId {

    private final UUID id;

    public UserId(UUID id) {
        this.id = Objects.requireNonNull(id);
    }

    public UUID getValue() {
        return this.id;
    }

    @Override
    public boolean equals(Object o) {
        return o instanceof UserId other && this.id.equals(other.id);
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }
}
