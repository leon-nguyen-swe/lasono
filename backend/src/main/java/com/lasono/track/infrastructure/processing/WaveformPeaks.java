package com.lasono.track.infrastructure.processing;

import java.util.ArrayList;
import java.util.List;

/** Turns raw audio samples into a short list of loudness peaks that is cheap to draw. */
final class WaveformPeaks {

    private WaveformPeaks() {
    }

    /**
     * Splits {@code samples} (16-bit PCM) into {@code buckets} equal parts and returns the loudest
     * sample of each part, scaled to the range 0..1.
     */
    static List<Float> fromPcm(short[] samples, int buckets) {
        if (samples.length == 0) {
            throw new IllegalArgumentException("There are no samples to build a waveform from");
        }
        // With fewer samples than parts, each sample gets its own peak.
        int parts = Math.min(buckets, samples.length);
        List<Float> peaks = new ArrayList<>(parts);
        for (int bucket = 0; bucket < parts; bucket++) {
            int from = (int) ((long) bucket * samples.length / parts);
            int to = (int) ((long) (bucket + 1) * samples.length / parts);
            int loudest = 0;
            for (int i = from; i < to; i++) {
                loudest = Math.max(loudest, Math.abs(samples[i]));
            }
            peaks.add(loudest / 32768f);
        }
        return peaks;
    }
}
