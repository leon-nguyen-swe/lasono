package com.lasono.track.application.usecase;

import java.util.UUID;

/**
 * A track whose audio is still being processed cannot be deleted yet. The worker saves its result when it
 * is done, and if the track were gone by then, that save would bring the deleted track back.
 */
public class TrackStillProcessingException extends RuntimeException {

    public TrackStillProcessingException(UUID trackId) {
        super("Track " + trackId + " is still being processed and cannot be deleted yet, try again in a moment");
    }
}
