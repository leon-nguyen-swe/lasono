package com.lasono.track.domain;

import java.util.Objects;
import java.util.UUID;

/**
 * Who owns a track. It is only the id of the user: the track module keeps it as a plain value and never
 * imports anything from the identity module.
 */
public class OwnerId {

    private final UUID id;

    public OwnerId(UUID id) {
        this.id = Objects.requireNonNull(id);
    }

    @Override
    public boolean equals(Object o) {
        if (o instanceof OwnerId) {
            OwnerId other = (OwnerId) o;
            return this.id.equals(other.id);
        }
        return false;
    }

    @Override
    public int hashCode() {
        return id.hashCode();
    }

    public UUID getValue() {
        return this.id;
    }
}
