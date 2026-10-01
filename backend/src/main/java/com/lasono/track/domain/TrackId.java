package com.lasono.track.domain;

import java.util.UUID;
import java.util.Objects;

public class TrackId {

    private final UUID id;

    public TrackId(UUID id) {
        this.id = Objects.requireNonNull(id);
    }

    @Override
    public boolean equals(Object o) {
        if (o instanceof TrackId) {
            TrackId other = (TrackId) o;
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