package com.lasono.track.infrastructure.processing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import com.lasono.track.application.port.out.ProcessedAudio;

/**
 * Runs the real ffmpeg and ffprobe programs (see the ffmpegTest Gradle task). The audio is made
 * by ffmpeg itself, so no audio file is stored in the repository.
 */
@Tag("ffmpeg")
class FfmpegAudioProcessorTest {

    private final FfmpegAudioProcessor processor = new FfmpegAudioProcessor("ffmpeg", "ffprobe", 60);

    @TempDir
    Path tempDir;

    @Test
    void readsTheDurationOfTheAudio() throws Exception {
        ProcessedAudio result = process(sineWave(3));

        assertThat(result.duration().toMilliseconds()).isCloseTo(3000L, within(50L));
    }

    @Test
    void buildsAWaveformOfTwoHundredPeaks() throws Exception {
        ProcessedAudio result = process(sineWave(3));

        assertThat(result.waveform().getSamples()).hasSize(200);
    }

    @Test
    void thePeaksFollowTheLoudnessOverTime() throws Exception {
        // Two seconds of tone, then two seconds of silence: the first half of the peaks is loud and
        // the second half is quiet. The tone itself is soft: about 9% of the maximum volume.
        ProcessedAudio result = process(loudThenSilent(2));

        List<Float> peaks = result.waveform().getSamples();
        assertThat(peaks.stream().limit(90).toList()).allMatch(peak -> peak > 0.05f);
        assertThat(peaks.stream().skip(110).toList()).isNotEmpty().allMatch(peak -> peak < 0.01f);
    }

    private ProcessedAudio process(Path audioFile) throws Exception {
        try (InputStream audio = Files.newInputStream(audioFile)) {
            return processor.process(audio);
        }
    }

    /** A 440 Hz tone, stereo, 44.1 kHz, saved as a WAV file. */
    private Path sineWave(int seconds) throws Exception {
        return generate("sine-" + seconds + "s.wav", "sine=frequency=440:duration=" + seconds);
    }

    /** {@code seconds} of tone followed by {@code seconds} of silence. */
    private Path loudThenSilent(int seconds) throws Exception {
        return generate("loud-then-silent.wav",
            "sine=frequency=440:duration=" + seconds + ",apad=pad_dur=" + seconds);
    }

    private Path generate(String fileName, String lavfiSource) throws Exception {
        Path file = tempDir.resolve(fileName);
        Process ffmpeg = new ProcessBuilder(
                "ffmpeg", "-v", "error", "-y",
                "-f", "lavfi", "-i", lavfiSource,
                "-ar", "44100", "-ac", "2", file.toString())
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start();
        assertThat(ffmpeg.waitFor(30, TimeUnit.SECONDS)).as("ffmpeg finished").isTrue();
        assertThat(ffmpeg.exitValue()).as("ffmpeg exit code").isZero();
        return file;
    }
}
