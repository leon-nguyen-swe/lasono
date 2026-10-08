package com.lasono.identity.application.usecase;

public class UserNotFoundException extends RuntimeException {

    public UserNotFoundException() {
        super("The account of this token no longer exists");
    }
}
