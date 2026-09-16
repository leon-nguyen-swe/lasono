package com.lasono.track.application.port.out;

public record StorageKey(String value) {
    public StorageKey {
        if (value == null || value.isBlank()) {
            throw new StorageKeyInvalidException("Storage must not be blank");
        }
    }
}