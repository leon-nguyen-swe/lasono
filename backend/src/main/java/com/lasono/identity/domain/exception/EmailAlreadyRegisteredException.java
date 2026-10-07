package com.lasono.identity.domain.exception;

import com.lasono.identity.domain.Email;

public class EmailAlreadyRegisteredException extends RuntimeException {

    public EmailAlreadyRegisteredException(Email email) {
        super("Email already registered: " + email.getValue());
    }
}
