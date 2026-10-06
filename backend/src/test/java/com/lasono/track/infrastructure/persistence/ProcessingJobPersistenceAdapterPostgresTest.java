package com.lasono.track.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.lasono.PostgresIntegrationTest;
import com.lasono.track.application.port.out.ProcessingJob;
import com.lasono.track.domain.TrackId;

/**
 * The job queue relies on PostgreSQL features (row locks with SKIP LOCKED, UPDATE ... RETURNING), so
 * it is tested on a real database, not on H2.
 */
class ProcessingJobPersistenceAdapterPostgresTest extends PostgresIntegrationTest {

    @Autowired
    private ProcessingJobPersistenceAdapter adapter;

    @Test
    void enqueueStoresAPendingJobForTheTrack() {
        UUID trackId = insertTrack();

        adapter.enqueue(new TrackId(trackId));

        List<Map<String, Object>> jobs = jdbcTemplate.queryForList(
            "SELECT track_id, status, attempts FROM processing_jobs");
        assertThat(jobs).hasSize(1);
        assertThat(jobs.get(0)).containsEntry("track_id", trackId);
        assertThat(jobs.get(0)).containsEntry("status", "PENDING");
        assertThat(jobs.get(0)).containsEntry("attempts", 0);
    }

    @Test
    void claimNextReturnsTheDueJobAndMarksItRunningWithALease() {
        UUID trackId = insertTrack();
        adapter.enqueue(new TrackId(trackId));

        Optional<ProcessingJob> claimed = adapter.claimNext(Duration.ofMinutes(5));

        assertThat(claimed).isPresent();
        assertThat(claimed.get().trackId()).isEqualTo(new TrackId(trackId));
        assertThat(claimed.get().attempts()).isEqualTo(1);
        Map<String, Object> row = jdbcTemplate.queryForMap("SELECT status, attempts FROM processing_jobs");
        assertThat(row).containsEntry("status", "RUNNING");
        assertThat(row).containsEntry("attempts", 1);
        // The lease runs about 5 minutes from now (the database clock decides "now").
        Boolean leased = jdbcTemplate.queryForObject(
            "SELECT locked_until > now() + interval '4 minutes' AND locked_until <= now() + interval '5 minutes' "
                + "FROM processing_jobs", Boolean.class);
        assertThat(leased).isTrue();
    }

    @Test
    void claimNextReturnsNothingWhenThereIsNoJob() {
        assertThat(adapter.claimNext(Duration.ofMinutes(5))).isEmpty();
    }

    @Test
    void claimNextSkipsAJobThatIsNotDueYet() {
        adapter.enqueue(new TrackId(insertTrack()));
        jdbcTemplate.update("UPDATE processing_jobs SET run_after = now() + interval '1 hour'");

        assertThat(adapter.claimNext(Duration.ofMinutes(5))).isEmpty();

        assertThat(jdbcTemplate.queryForObject("SELECT status FROM processing_jobs", String.class))
            .isEqualTo("PENDING");
    }

    @Test
    void claimNextTakesTheJobThatHasWaitedLongestFirst() {
        UUID newerTrack = insertTrack();
        UUID olderTrack = insertTrack();
        // The "older" job is stored second, but it became due first.
        adapter.enqueue(new TrackId(newerTrack));
        adapter.enqueue(new TrackId(olderTrack));
        jdbcTemplate.update(
            "UPDATE processing_jobs SET run_after = now() - interval '1 hour' WHERE track_id = ?", olderTrack);

        Optional<ProcessingJob> claimed = adapter.claimNext(Duration.ofMinutes(5));

        assertThat(claimed).isPresent();
        assertThat(claimed.get().trackId()).isEqualTo(new TrackId(olderTrack));
    }

    @Test
    void workersClaimingAtTheSameTimeNeverTakeTheSameJob() throws Exception {
        int jobCount = 100;
        int workerCount = 8;
        for (int i = 0; i < jobCount; i++) {
            adapter.enqueue(new TrackId(insertTrack()));
        }

        ExecutorService workers = Executors.newFixedThreadPool(workerCount);
        CountDownLatch go = new CountDownLatch(1);
        List<Future<List<TrackId>>> results = new ArrayList<>();
        for (int i = 0; i < workerCount; i++) {
            results.add(workers.submit(() -> {
                go.await();
                List<TrackId> claimedByThisWorker = new ArrayList<>();
                Optional<ProcessingJob> job;
                while ((job = adapter.claimNext(Duration.ofMinutes(5))).isPresent()) {
                    claimedByThisWorker.add(job.get().trackId());
                }
                return claimedByThisWorker;
            }));
        }
        go.countDown();

        List<TrackId> claimed = new ArrayList<>();
        for (Future<List<TrackId>> result : results) {
            claimed.addAll(result.get(60, TimeUnit.SECONDS));
        }
        workers.shutdown();

        assertThat(claimed).doesNotHaveDuplicates();
        assertThat(claimed).hasSize(jobCount);
        assertThat(jdbcTemplate.queryForObject(
            "SELECT count(*) FROM processing_jobs WHERE attempts <> 1", Integer.class)).isZero();
    }

    private UUID insertTrack() {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update(
            "INSERT INTO tracks (id, title, description, status) VALUES (?, 'a song', NULL, 'PROCESSING')", id);
        return id;
    }
}
