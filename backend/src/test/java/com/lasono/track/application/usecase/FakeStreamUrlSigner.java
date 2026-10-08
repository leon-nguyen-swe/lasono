package com.lasono.track.application.usecase;

import java.util.UUID;

import com.lasono.track.application.port.out.StreamUrlSigner;

/** A readable signature, "sig-<track>-<expiry>", so a test can see what it was made for. */
public class FakeStreamUrlSigner implements StreamUrlSigner {

    @Override
    public String sign(UUID trackId, long expiresAtEpochSecond) {
        return "sig-" + trackId + "-" + expiresAtEpochSecond;
    }

    @Override
    public boolean isValid(UUID trackId, long expiresAtEpochSecond, String signature) {
        return sign(trackId, expiresAtEpochSecond).equals(signature);
    }
}
