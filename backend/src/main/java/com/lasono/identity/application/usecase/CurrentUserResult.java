package com.lasono.identity.application.usecase;

public record CurrentUserResult(
    String userId,
    String email,
    String displayName
) {}
