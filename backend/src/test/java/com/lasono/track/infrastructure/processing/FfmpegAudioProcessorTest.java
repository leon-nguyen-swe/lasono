package com.lasono.track.infrastructure.processing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import com.lasono.track.application.port.out.AudioProcessingException;
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

    @Test
    void convertsTheAudioToA128KbpsMp3() throws Exception {
        ProcessedAudio result = process(sineWave(3));

        // Ask ffprobe, not the processor, what the converted bytes really are.
        Path mp3 = Files.write(tempDir.resolve("streaming.mp3"), result.streamingAudio());
        assertThat(probe(mp3, "format_name")).isEqualTo("mp3");
        assertThat(Double.parseDouble(probe(mp3, "duration"))).isCloseTo(3.0, within(0.1));
        assertThat(Long.parseLong(probe(mp3, "bit_rate"))).isCloseTo(128_000L, within(8_000L));
    }

    @Test
    void rejectsAFileThatIsNotAudio() {
        byte[] notAudio = "this is just text, not an audio file".getBytes(StandardCharsets.UTF_8);

        assertThatThrownBy(() -> processor.process(new ByteArrayInputStream(notAudio)))
            .isInstanceOf(AudioProcessingException.class)
            .hasMessageContaining("ffprobe");
    }

    @Test
    void rejectsAudioThatHasNoSound() throws Exception {
        // A valid WAV file whose length is zero: ffprobe reads it, but there is nothing to draw.
        Path empty = generate("empty.wav", "anullsrc=channel_layout=stereo:sample_rate=44100", "0");

        assertThatThrownBy(() -> process(empty)).isInstanceOf(AudioProcessingException.class);
    }

    @Test
    void stopsAProgramThatRunsTooLongAndCleansUp() throws Exception {
        // A fake ffprobe that never finishes in time. "exec" makes the script become the sleep
        // program itself, so stopping the process stops the sleep too.
        Path slowProbe = tempDir.resolve("slow-ffprobe.sh");
        Files.writeString(slowProbe, "#!/bin/sh\nexec sleep 20\n");
        assertThat(slowProbe.toFile().setExecutable(true)).isTrue();
        FfmpegAudioProcessor impatient = new FfmpegAudioProcessor("ffmpeg", slowProbe.toString(), 1);
        long workDirsBefore = leftoverWorkDirs();

        long started = System.nanoTime();
        assertThatThrownBy(() -> impatient.process(new ByteArrayInputStream("any bytes".getBytes(StandardCharsets.UTF_8))))
            .isInstanceOf(AudioProcessingException.class)
            .hasMessageContaining("timed out");

        assertThat(Duration.ofNanos(System.nanoTime() - started)).isLessThan(Duration.ofSeconds(10));
        assertThat(leftoverWorkDirs()).isEqualTo(workDirsBefore);
    }

    /** How many working directories of the processor exist in the temporary directory. */
    private static long leftoverWorkDirs() throws Exception {
        try (Stream<Path> entries = Files.list(Path.of(System.getProperty("java.io.tmpdir")))) {
            return entries.filter(path -> path.getFileName().toString().startsWith("lasono-audio-")).count();
        }
    }

    private String probe(Path file, String entry) throws Exception {
        Path output = tempDir.resolve("probe-" + entry + ".txt");
        Process ffprobe = new ProcessBuilder(
                "ffprobe", "-v", "error", "-show_entries", "format=" + entry,
                "-of", "default=noprint_wrappers=1:nokey=1", file.toString())
            .redirectOutput(output.toFile())
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start();
        assertThat(ffprobe.waitFor(30, TimeUnit.SECONDS)).as("ffprobe finished").isTrue();
        return Files.readString(output).trim();
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
        return generate(fileName, lavfiSource, null);
    }

    /** {@code maxSeconds} cuts the audio to that length; {@code null} keeps it as the source makes it. */
    private Path generate(String fileName, String lavfiSource, String maxSeconds) throws Exception {
        Path file = tempDir.resolve(fileName);
        List<String> command = new ArrayList<>(List.of(
            "ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", lavfiSource, "-ar", "44100", "-ac", "2"));
        if (maxSeconds != null) {
            command.addAll(List.of("-t", maxSeconds));
        }
        command.add(file.toString());
        Process ffmpeg = new ProcessBuilder(command)
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start();
        assertThat(ffmpeg.waitFor(30, TimeUnit.SECONDS)).as("ffmpeg finished").isTrue();
        assertThat(ffmpeg.exitValue()).as("ffmpeg exit code").isZero();
        return file;
    }
}
