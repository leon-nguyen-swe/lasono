package com.lasono.track.infrastructure.processing;

import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Comparator;
import java.util.stream.Stream;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.AudioProcessingException;
import com.lasono.track.application.port.out.AudioProcessor;
import com.lasono.track.application.port.out.ProcessedAudio;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.Waveform;

@Component
public class FfmpegAudioProcessor implements AudioProcessor {

    private static final int WAVEFORM_PEAKS = 200;

    private final String ffmpegPath;
    private final String ffprobePath;
    private final Duration timeout;

    public FfmpegAudioProcessor(
        @Value("${lasono.processing.ffmpeg-path:ffmpeg}") String ffmpegPath,
        @Value("${lasono.processing.ffprobe-path:ffprobe}") String ffprobePath,
        @Value("${lasono.processing.timeout-seconds:300}") long timeoutSeconds
    ) {
        this.ffmpegPath = ffmpegPath;
        this.ffprobePath = ffprobePath;
        this.timeout = Duration.ofSeconds(timeoutSeconds);
    }

    @Override
    public ProcessedAudio process(InputStream original) {
        Path workDir = null;
        try {
            workDir = Files.createTempDirectory("lasono-audio-");
            Path source = workDir.resolve("original");
            Files.copy(original, source);

            AudioDuration duration = readDuration(source, workDir);
            Waveform waveform = buildWaveform(source, workDir);
            return new ProcessedAudio(duration, waveform, new byte[0]);
        } catch (IOException e) {
            throw new AudioProcessingException("Failed to process the audio", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new AudioProcessingException("Audio processing was interrupted", e);
        } finally {
            deleteQuietly(workDir);
        }
    }

    private AudioDuration readDuration(Path source, Path workDir) throws IOException, InterruptedException {
        Path output = run(workDir, "probe",
            ffprobePath, "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", source.toString());
        double seconds = Double.parseDouble(Files.readString(output).trim());
        return new AudioDuration(Math.round(seconds * 1000));
    }

    /** Decodes the audio to 8 kHz mono 16-bit PCM and keeps the loudest sample of each of 200 parts. */
    private Waveform buildWaveform(Path source, Path workDir) throws IOException, InterruptedException {
        Path pcm = run(workDir, "pcm",
            ffmpegPath, "-v", "error", "-i", source.toString(),
            "-ac", "1", "-ar", "8000", "-f", "s16le", "-");
        ShortBuffer buffer = ByteBuffer.wrap(Files.readAllBytes(pcm)).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer();
        short[] samples = new short[buffer.remaining()];
        buffer.get(samples);
        return new Waveform(WaveformPeaks.fromPcm(samples, WAVEFORM_PEAKS));
    }

    /**
     * Runs a program and returns the file its standard output was written to. The output goes to
     * files, not pipes: nobody has to read a pipe, so the program can never block on a full one.
     */
    private Path run(Path workDir, String name, String... command) throws IOException, InterruptedException {
        Path stdout = workDir.resolve(name + ".out");
        new ProcessBuilder(command)
            .redirectOutput(stdout.toFile())
            .redirectError(workDir.resolve(name + ".err").toFile())
            .start()
            .waitFor();
        return stdout;
    }

    private static void deleteQuietly(Path directory) {
        if (directory == null) {
            return;
        }
        try (Stream<Path> paths = Files.walk(directory)) {
            paths.sorted(Comparator.reverseOrder()).forEach(path -> path.toFile().delete());
        } catch (IOException e) {
            // A leftover temporary file is not worth failing the request for.
        }
    }
}
