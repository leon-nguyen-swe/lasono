package com.lasono.track.domain;

import java.util.Objects;
import java.util.UUID;

public class AudioResourceId {

    private final UUID id;

    public AudioResourceId(UUID id) {
        this.id = Objects.requireNonNull(id);
    }

    @Override
    public boolean equals(Object o) {
        if (o instanceof AudioResourceId) {
            AudioResourceId other = (AudioResourceId) o;
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