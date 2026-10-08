package com.lasono.identity.application.port.out;

public interface PasswordHasher {

    /** Returns a salted, slow hash of the password. The password itself must never be stored. */
    String hash(String rawPassword);

    /**
     * Tells whether the password belongs to the hash. Anything odd (no password, a password too long
     * for the algorithm, a hash that is not a hash) gives {@code false}, never an exception: a login is
     * open to strangers, so their input must end in "no" and not in a server error.
     */
    boolean matches(String rawPassword, String hash);
}
