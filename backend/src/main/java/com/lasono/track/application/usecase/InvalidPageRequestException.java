package com.lasono.track.application.usecase;

/** The client asked for a page that cannot exist, for example with a malformed cursor. */
public class InvalidPageRequestException extends RuntimeException {

    public InvalidPageRequestException(String message) {
        super(message);
    }
}
