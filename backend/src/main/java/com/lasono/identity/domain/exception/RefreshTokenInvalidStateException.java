package com.lasono.identity.domain.exception;

public class RefreshTokenInvalidStateException extends RuntimeException {

    public RefreshTokenInvalidStateException(String message) {
        super(message);
    }
}
