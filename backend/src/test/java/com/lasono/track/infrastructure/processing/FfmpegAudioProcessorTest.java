package com.lasono.track.infrastructure.processing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
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
        Path threeSeconds = sineWave(3);

        try (InputStream audio = Files.newInputStream(threeSeconds)) {
            ProcessedAudio result = processor.process(audio);

            assertThat(result.duration().toMilliseconds()).isCloseTo(3000L, within(50L));
        }
    }

    /** A 440 Hz tone, stereo, 44.1 kHz, saved as a WAV file. */
    private Path sineWave(int seconds) throws Exception {
        Path file = tempDir.resolve("sine-" + seconds + "s.wav");
        Process ffmpeg = new ProcessBuilder(
                "ffmpeg", "-v", "error", "-y",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=" + seconds,
                "-ar", "44100", "-ac", "2", file.toString())
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start();
        assertThat(ffmpeg.waitFor(30, TimeUnit.SECONDS)).as("ffmpeg finished").isTrue();
        assertThat(ffmpeg.exitValue()).as("ffmpeg exit code").isZero();
        return file;
    }
}
