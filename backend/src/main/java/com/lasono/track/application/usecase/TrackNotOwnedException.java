package com.lasono.track.application.usecase;

import java.util.UUID;

/** The caller can see the track but it is not theirs, so they may not change or delete it. */
public class TrackNotOwnedException extends RuntimeException {

    public TrackNotOwnedException(UUID trackId) {
        super("Only the owner can change or delete track " + trackId);
    }
}
