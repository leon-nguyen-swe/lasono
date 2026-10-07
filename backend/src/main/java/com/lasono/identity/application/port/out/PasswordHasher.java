package com.lasono.identity.application.port.out;

public interface PasswordHasher {

    /** Returns a salted, slow hash of the password. The password itself must never be stored. */
    String hash(String rawPassword);
}
