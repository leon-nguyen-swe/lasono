package com.lasono.track.domain.audio.model;

import com.lasono.track.domain.audio.exception.AudioDurationInvalidException;

public final class AudioDuration {

    private final long milliseconds;

    public AudioDuration(long milliseconds) {
        if (milliseconds < 0) {
            throw new AudioDurationInvalidException("Audio duration cannot be negative");
        }
        this.milliseconds = milliseconds;
    }

    public long toMilliseconds() {
        return milliseconds;
    }
}