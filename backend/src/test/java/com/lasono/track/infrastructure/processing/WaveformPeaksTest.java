package com.lasono.track.infrastructure.processing;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;

import org.junit.jupiter.api.Test;

class WaveformPeaksTest {

    @Test
    void returnsTheRequestedNumberOfPeaks() {
        short[] samples = new short[1000];

        List<Float> peaks = WaveformPeaks.fromPcm(samples, 10);

        assertThat(peaks).hasSize(10);
    }

    @Test
    void eachPeakIsTheLargestAbsoluteSampleOfItsPartScaledToZeroToOne() {
        // Two parts of four samples: the loudest of the first is 16384 (half of the maximum), the
        // loudest of the second is -32768 (the maximum, only negative).
        short[] samples = {0, 16384, 0, 0, 0, 0, -32768, 0};

        List<Float> peaks = WaveformPeaks.fromPcm(samples, 2);

        assertThat(peaks).containsExactly(0.5f, 1.0f);
    }
}
