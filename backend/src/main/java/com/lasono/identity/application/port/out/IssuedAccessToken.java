package com.lasono.identity.application.port.out;

/** A signed access token and how many seconds it stays valid, for the client to know when to refresh. */
public record IssuedAccessToken(String value, long expiresInSeconds) {
}
