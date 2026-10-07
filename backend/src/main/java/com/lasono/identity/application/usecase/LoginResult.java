package com.lasono.identity.application.usecase;

public record LoginResult(
    String accessToken,
    String tokenType,
    long expiresIn
) {}
