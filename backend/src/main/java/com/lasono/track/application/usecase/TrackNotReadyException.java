package com.lasono.track.application.usecase;

import java.util.UUID;

/** The track exists, but its audio is not ready to be played (still processing, or processing failed). */
public class TrackNotReadyException extends RuntimeException {

    public TrackNotReadyException(UUID trackId, String status) {
        super("Track " + trackId + " is not ready to be played, its status is " + status);
    }
}
