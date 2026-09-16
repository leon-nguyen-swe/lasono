package com.lasono.track.application.port.out;

public class StorageKeyInvalidException extends RuntimeException {

    public StorageKeyInvalidException(String message) {
        super(message);
    }
}