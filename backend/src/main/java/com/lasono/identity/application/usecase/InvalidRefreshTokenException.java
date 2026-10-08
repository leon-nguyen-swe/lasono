package com.lasono.identity.application.usecase;

/** One answer for every refresh token that cannot be used, so the caller learns nothing about why. */
public class InvalidRefreshTokenException extends RuntimeException {

    public InvalidRefreshTokenException() {
        super("Invalid refresh token");
    }
}
