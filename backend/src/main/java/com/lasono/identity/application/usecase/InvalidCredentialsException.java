package com.lasono.identity.application.usecase;

/** One answer for every failed login, so the caller cannot tell a wrong password from an unknown email. */
public class InvalidCredentialsException extends RuntimeException {

    public InvalidCredentialsException() {
        super("Invalid email or password");
    }
}
