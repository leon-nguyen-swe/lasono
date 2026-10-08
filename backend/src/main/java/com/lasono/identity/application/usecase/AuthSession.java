package com.lasono.identity.application.usecase;

/**
 * What a login or a refresh gives back. The access token goes to the client in the response body; the refresh
 * token must go in a cookie only, so the two are kept apart.
 */
public record AuthSession(LoginResult access, String refreshToken) {

    // A record prints all its fields; the refresh token must not end up in a log.
    @Override
    public String toString() {
        return "AuthSession[access=" + access + ", refreshToken=***]";
    }
}
