package com.lasono.identity.application.usecase;

public record RegisterUserResult(
    String userId,
    String email,
    String displayName
) {}
