package com.lasono.identity.application.usecase;

/** What anyone may see of a user. No email and nothing about the password: only the id and the name. */
public record ProfileResult(String userId, String displayName) {}
