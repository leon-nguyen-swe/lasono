package com.lasono.track.domain.exception;

public class TrackInvalidStateException extends RuntimeException {

    public TrackInvalidStateException(String message) {
        super(message);
    }
}