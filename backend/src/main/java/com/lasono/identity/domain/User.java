package com.lasono.identity.domain;

import java.util.Objects;

import com.lasono.identity.domain.exception.UserInvalidException;

public class User {

    private final UserId id;
    private final Email email;
    private final DisplayName displayName;
    private final String passwordHash;

    // Takes the hash of the password, never the password itself.
    public User(UserId id, Email email, DisplayName displayName, String passwordHash) {
        if (passwordHash == null || passwordHash.isBlank()) {
            throw new UserInvalidException("Password hash must not be blank");
        }
        this.id = Objects.requireNonNull(id);
        this.email = Objects.requireNonNull(email);
        this.displayName = Objects.requireNonNull(displayName);
        this.passwordHash = passwordHash;
    }

    public UserId getId() {
        return this.id;
    }

    public Email getEmail() {
        return this.email;
    }

    public DisplayName getDisplayName() {
        return this.displayName;
    }

    public String getPasswordHash() {
        return this.passwordHash;
    }
}
