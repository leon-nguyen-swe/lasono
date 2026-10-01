package com.lasono.track.application.usecase;

import java.util.UUID;

public class TrackNotFoundException extends RuntimeException {

    public TrackNotFoundException(UUID trackId) {
        super("Track not found: " + trackId);
    }
}