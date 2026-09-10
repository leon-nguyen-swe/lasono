package com.lasono.track.domain.audio.model;

import java.util.ArrayList;
import java.util.List;

import com.lasono.track.domain.audio.exception.AudioWaveformInvalidException;

public final class Waveform {

    private final List<Float> samples;

    public Waveform(List<Float> samples) {
        if (samples == null) {
            throw new AudioWaveformInvalidException("Samples must not be null");
        }
        if (samples.isEmpty()) {
            throw new AudioWaveformInvalidException("Samples must not be empty");
        }
        
        this.samples = new ArrayList<>(samples);
    }

    public List<Float> getSamples() {
        return new ArrayList<>(this.samples);
    }
}