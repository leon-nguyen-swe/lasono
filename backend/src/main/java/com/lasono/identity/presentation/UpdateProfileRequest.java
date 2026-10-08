package com.lasono.identity.presentation;

/** The body of a PATCH to /users/me. Only the display name can be changed here. */
public record UpdateProfileRequest(String displayName) {}
