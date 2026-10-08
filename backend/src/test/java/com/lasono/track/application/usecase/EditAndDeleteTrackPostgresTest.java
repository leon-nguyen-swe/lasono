package com.lasono.track.application.usecase;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.transaction.support.TransactionTemplate;

import com.lasono.PostgresIntegrationTest;
import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;
import com.lasono.track.domain.model.Visibility;

/**
 * Deleting touches the tracks, audio_resources and processing_jobs tables, which point at each other, and then
 * the files on disk. Editing and deleting the same track at once must take turns. A fake cannot show either,
 * so they run on a real PostgreSQL with the real audio storage.
 */
class EditAndDeleteTrackPostgresTest extends PostgresIntegrationTest {

    private static final UUID OWNER = TrackFixtures.OWNER.getValue();

    @Autowired
    private DeleteTrackUseCase deleteTrack;

    @Autowired
    private UpdateTrackUseCase updateTrack;

    @Autowired
    private TrackRepository trackRepository;

    @Autowired
    private ProcessingJobQueue jobQueue;

    @Autowired
    private AudioStorage audioStorage;

    @Autowired
    private TransactionTemplate transactionTemplate;

    @Value("${lasono.storage.root}")
    private String storageRoot;

    /** A finished track: both files on disk, a job row left behind, and every table filled in. */
    private Track aReadyTrack() {
        StorageKey original = audioStorage.store(new ByteArrayInputStream("original".getBytes()), AudioFormat.WAV);
        StorageKey mp3 = audioStorage.store(new ByteArrayInputStream("mp3".getBytes()), AudioFormat.MP3);
        Track track = new Track(new TrackId(UUID.randomUUID()), TrackFixtures.OWNER, "My Song", "desc", Visibility.PUBLIC);
        track.uploadCompleted(new OriginalAudio(original.value(), AudioFormat.WAV, 8, "audio/wav"));
        track.startProcessing();
        track.processingCompleted(
            new StreamingAudio(mp3.value(), AudioFormat.MP3, 3, "audio/mpeg"),
            new AudioDuration(3000L),
            new Waveform(List.of(0.1f, 0.5f)));
        trackRepository.save(track);
        jobQueue.enqueue(track.getId());
        return track;
    }

    private boolean onDisk(StorageKey key) {
        return Files.exists(Path.of(storageRoot).resolve(key.value()));
    }

    private int count(String table) {
        return jdbcTemplate.queryForObject("SELECT count(*) FROM " + table, Integer.class);
    }

    @Test
    void deletingATrackRemovesItsRowsFromEveryTableAndItsFilesFromDisk() {
        Track track = aReadyTrack();
        Track other = aReadyTrack();
        StorageKey original = new StorageKey(track.toSnapshot().originalAudio().getStorageKey());
        StorageKey mp3 = new StorageKey(track.toSnapshot().streamingAudio().getStorageKey());
        assertThat(onDisk(original)).isTrue();
        assertThat(onDisk(mp3)).isTrue();

        deleteTrack.execute(track.getId().getValue(), OWNER);

        assertThat(trackRepository.findById(track.getId())).isEmpty();
        assertThat(count("tracks")).isEqualTo(1);
        assertThat(count("audio_resources")).isEqualTo(1);
        assertThat(count("processing_jobs")).isEqualTo(1);
        assertThat(onDisk(original)).isFalse();
        assertThat(onDisk(mp3)).isFalse();
        assertThat(trackRepository.findById(other.getId())).isPresent();
    }

    @Test
    void aStrangerCannotDeleteATrackAndNothingIsRemoved() {
        Track track = aReadyTrack();
        StorageKey mp3 = new StorageKey(track.toSnapshot().streamingAudio().getStorageKey());

        assertThatThrownBy(() -> deleteTrack.execute(track.getId().getValue(), UUID.randomUUID()))
            .isInstanceOf(TrackNotOwnedException.class);

        assertThat(count("tracks")).isEqualTo(1);
        assertThat(count("audio_resources")).isEqualTo(1);
        assertThat(count("processing_jobs")).isEqualTo(1);
        assertThat(onDisk(mp3)).isTrue();
    }

    @Test
    void aTrackBeingProcessedCannotBeDeleted() {
        Track track = new Track(new TrackId(UUID.randomUUID()), TrackFixtures.OWNER, "Busy", null);
        StorageKey original = audioStorage.store(new ByteArrayInputStream("original".getBytes()), AudioFormat.WAV);
        track.uploadCompleted(new OriginalAudio(original.value(), AudioFormat.WAV, 8, "audio/wav"));
        trackRepository.save(track);
        jobQueue.enqueue(track.getId());

        assertThatThrownBy(() -> deleteTrack.execute(track.getId().getValue(), OWNER))
            .isInstanceOf(TrackStillProcessingException.class);

        assertThat(count("tracks")).isEqualTo(1);
        assertThat(count("processing_jobs")).isEqualTo(1);
        assertThat(onDisk(original)).isTrue();
    }

    @Test
    void anEditIsSavedInTheDatabase() {
        Track track = aReadyTrack();

        updateTrack.execute(new UpdateTrackCommand(track.getId().getValue(), OWNER, "Renamed", "", "PRIVATE"));

        Track reloaded = trackRepository.findById(track.getId()).orElseThrow();
        assertThat(reloaded.getTitle()).isEqualTo("Renamed");
        assertThat(reloaded.getDescription()).isEmpty();
        assertThat(reloaded.getVisibility()).isEqualTo(Visibility.PRIVATE);
        assertThat(reloaded.getOwnerId()).isEqualTo(TrackFixtures.OWNER);
    }

    // Without the lock an edit would not wait, and one that read the track before the delete could save its copy
    // afterwards and bring the deleted track back. With it, the edit waits and finds nothing.
    @Test
    void anEditThatArrivesDuringADeleteWaitsAndThenFindsTheTrackGone() throws Exception {
        Track track = aReadyTrack();
        ExecutorService executor = Executors.newFixedThreadPool(1);
        CountDownLatch deleterHoldsTheLock = new CountDownLatch(1);
        try {
            Future<?> deleter = executor.submit(() -> transactionTemplate.executeWithoutResult(status -> {
                trackRepository.findByIdForUpdate(track.getId()).orElseThrow();
                deleterHoldsTheLock.countDown();
                pause(700);
                jobQueue.discardJobsOf(track.getId());
                trackRepository.delete(track.getId());
            }));
            assertThat(deleterHoldsTheLock.await(5, TimeUnit.SECONDS)).as("the delete holds the lock").isTrue();

            long startedWaiting = System.nanoTime();
            assertThatThrownBy(() -> updateTrack.execute(
                new UpdateTrackCommand(track.getId().getValue(), OWNER, "Too late", null, null)))
                .isInstanceOf(TrackNotFoundException.class);
            long waitedMillis = (System.nanoTime() - startedWaiting) / 1_000_000;
            deleter.get(10, TimeUnit.SECONDS);

            assertThat(waitedMillis).isGreaterThan(300);
            assertThat(count("tracks")).isZero();
        } finally {
            executor.shutdownNow();
        }
    }

    private static void pause(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
