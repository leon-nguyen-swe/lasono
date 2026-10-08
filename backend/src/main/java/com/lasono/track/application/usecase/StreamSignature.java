package com.lasono.track.application.usecase;

/** The proof of permission carried by a stream address: until when it holds, and the signature over it. */
public record StreamSignature(long expiresAtEpochSecond, String value) {}
