package com.lasono.track.infrastructure.persistence;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Repository;

import com.lasono.track.application.port.out.TrackPosition;
import com.lasono.track.application.port.out.TrackSummary;
import com.lasono.track.application.port.out.TrackSummaryReader;

@Repository
public class TrackSummaryPersistenceAdapter implements TrackSummaryReader {

    private final TrackJpaRepository trackJpaRepository;
    private final AudioResourceJpaRepository audioResourceJpaRepository;

    public TrackSummaryPersistenceAdapter(
        TrackJpaRepository trackJpaRepository,
        AudioResourceJpaRepository audioResourceJpaRepository
    ) {
        this.trackJpaRepository = trackJpaRepository;
        this.audioResourceJpaRepository = audioResourceJpaRepository;
    }

    @Override
    public List<TrackSummary> findNewestAfter(TrackPosition after, int limit) {
        List<TrackJpaEntity> tracks = after == null
            ? trackJpaRepository.findNewest(limit)
            : trackJpaRepository.findNewestAfter(after.createdAt(), after.id(), limit);
        if (tracks.isEmpty()) {
            return List.of();
        }

        // One query for the whole page, not one per track.
        Map<UUID, Long> durations = new HashMap<>();
        audioResourceJpaRepository.findDurationsByTrackIds(tracks.stream().map(TrackJpaEntity::getId).toList())
            .forEach(row -> durations.put(row.getTrackId(), row.getDurationMs()));

        return tracks.stream()
            .map(track -> toSummary(track, durations.get(track.getId())))
            .toList();
    }

    private static TrackSummary toSummary(TrackJpaEntity track, Long durationMs) {
        return new TrackSummary(
            track.getId(),
            track.getTitle(),
            track.getDescription(),
            track.getStatus(),
            track.getCreatedAt(),
            durationMs
        );
    }
}
