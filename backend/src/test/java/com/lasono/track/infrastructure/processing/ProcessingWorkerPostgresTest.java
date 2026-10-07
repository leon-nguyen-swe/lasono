package com.lasono.track.infrastructure.processing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.awaitility.Awaitility.await;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;

import com.lasono.PostgresIntegrationTest;
import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.application.usecase.UploadTrackCommand;
import com.lasono.track.application.usecase.UploadTrackResult;
import com.lasono.track.application.usecase.UploadTrackUseCase;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.TrackSnapshot;
import com.lasono.track.domain.model.TrackStatus;

/**
 * The whole processing pipeline with a real PostgreSQL and a real ffmpeg: a track is uploaded and the
 * background worker, started by configuration, turns it into a READY track. Needs ffmpeg and ffprobe
 * on the PATH. The context is closed afterwards so this worker cannot take jobs of other tests.
 */
@DirtiesContext
@TestPropertySource(properties = {
    "lasono.processing.worker-enabled=true",
    "lasono.processing.poll-interval-ms=200"
})
class ProcessingWorkerPostgresTest extends PostgresIntegrationTest {

    @Autowired
    private UploadTrackUseCase uploadTrack;

    @Autowired
    private TrackRepository trackRepository;

    @Autowired
    private AudioStorage audioStorage;

    @TempDir
    private Path tempDir;

    @Test
    void anUploadedTrackBecomesReadyByItselfWithItsDurationWaveformAndMp3() throws Exception {
        byte[] wav = threeSecondTone();
        UploadTrackResult uploaded = uploadTrack.execute(
            new UploadTrackCommand("My Song", "desc", new ByteArrayInputStream(wav), wav.length, "audio/wav"));
        TrackId id = new TrackId(UUID.fromString(uploaded.trackId()));

        await().atMost(Duration.ofSeconds(30)).untilAsserted(() ->
            assertThat(jobStatus()).as("the worker finished the job").isEqualTo("DONE"));

        TrackSnapshot track = trackRepository.findById(id).orElseThrow().toSnapshot();
        assertThat(track.trackStatus()).isEqualTo(TrackStatus.READY);
        assertThat(track.audioDuration().toMilliseconds()).isCloseTo(3000L, within(150L));
        assertThat(track.waveform().getSamples()).hasSize(200);
        try (InputStream mp3 = audioStorage.retrieve(new StorageKey(track.streamingAudio().getStorageKey()))) {
            assertThat(mp3.readAllBytes()).isNotEmpty();
        }
    }

    private String jobStatus() {
        return jdbcTemplate.queryForObject("SELECT status FROM processing_jobs", String.class);
    }

    /** A 440 Hz tone, stereo, 44.1 kHz, made by ffmpeg itself so no audio file is stored in the repository. */
    private byte[] threeSecondTone() throws Exception {
        Path wav = tempDir.resolve("tone.wav");
        Process ffmpeg = new ProcessBuilder(List.of(
                "ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
                "-ar", "44100", "-ac", "2", wav.toString()))
            .redirectErrorStream(true)
            .redirectOutput(tempDir.resolve("ffmpeg.log").toFile())
            .start();
        assertThat(ffmpeg.waitFor(30, TimeUnit.SECONDS)).as("ffmpeg finished").isTrue();
        assertThat(ffmpeg.exitValue()).as("ffmpeg exit code").isZero();
        return Files.readAllBytes(wav);
    }
}
