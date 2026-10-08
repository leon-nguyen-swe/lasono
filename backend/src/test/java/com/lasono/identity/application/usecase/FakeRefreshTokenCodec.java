package com.lasono.identity.application.usecase;

import com.lasono.identity.application.port.out.RefreshTokenCodec;

/** Readable fake values: the tokens are raw-1, raw-2, ... and the hash of a value is simply "hash-of-" + value. */
public class FakeRefreshTokenCodec implements RefreshTokenCodec {

    public static final String RAW_PREFIX = "raw-";
    public static final String HASH_PREFIX = "hash-of-";

    private int generated;

    @Override
    public String generate() {
        generated++;
        return RAW_PREFIX + generated;
    }

    @Override
    public String hash(String rawToken) {
        return HASH_PREFIX + rawToken;
    }
}
