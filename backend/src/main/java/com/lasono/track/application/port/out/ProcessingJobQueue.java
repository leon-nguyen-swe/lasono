package com.lasono.track.application.port.out;

import com.lasono.track.domain.TrackId;

public interface ProcessingJobQueue {

    /** Adds a job that asks a worker to process the audio of {@code trackId}. */
    void enqueue(TrackId trackId);
}
