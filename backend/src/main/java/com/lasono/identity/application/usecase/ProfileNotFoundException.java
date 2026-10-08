package com.lasono.identity.application.usecase;

import java.util.UUID;

/** Nobody has this id. Not the same as {@link UserNotFoundException}, which is about the account of a login token. */
public class ProfileNotFoundException extends RuntimeException {

    public ProfileNotFoundException(UUID userId) {
        super("No user with id " + userId);
    }
}
