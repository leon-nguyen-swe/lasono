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
        List<Float> peaks = new ArrayList<>(buckets);
        for (int bucket = 0; bucket < buckets; bucket++) {
            int from = (int) ((long) bucket * samples.length / buckets);
            int to = (int) ((long) (bucket + 1) * samples.length / buckets);
            int loudest = 0;
            for (int i = from; i < to; i++) {
                loudest = Math.max(loudest, Math.abs(samples[i]));
            }
            peaks.add(loudest / 32768f);
        }
        return peaks;
    }
}
