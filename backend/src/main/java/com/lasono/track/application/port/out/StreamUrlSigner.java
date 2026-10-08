package com.lasono.track.application.port.out;

import java.util.UUID;

/**
 * Signs and checks the addresses a browser uses to play a track. A browser's audio player cannot send an
 * Authorization header, so the permission to play is put in the address itself, for one track and until a given moment.
 */
public interface StreamUrlSigner {

    /** A signature for this track and this expiry. It cannot be reused for another track or another expiry. */
    String sign(UUID trackId, long expiresAtEpochSecond);

    /** True only for a signature made by {@link #sign} for exactly this track and expiry. Never throws. */
    boolean isValid(UUID trackId, long expiresAtEpochSecond, String signature);
}
