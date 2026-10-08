package com.lasono.identity.application.port.out;

/** Makes the secret value of a refresh token and turns it into the hash that is stored instead. */
public interface RefreshTokenCodec {

    /** A new unguessable value. It goes to the client once and is never stored as it is. */
    String generate();

    /** The same value always gives the same hash, so a token shown later can be found by its hash. */
    String hash(String rawToken);
}
