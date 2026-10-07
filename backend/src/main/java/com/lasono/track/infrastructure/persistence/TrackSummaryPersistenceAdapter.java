package com.lasono.track.infrastructure.persistence;

import java.util.List;

import org.springframework.stereotype.Repository;

import com.lasono.track.application.port.out.TrackPosition;
import com.lasono.track.application.port.out.TrackSummary;
import com.lasono.track.application.port.out.TrackSummaryReader;

@Repository
public class TrackSummaryPersistenceAdapter implements TrackSummaryReader {

    private final TrackJpaRepository trackJpaRepository;

    public TrackSummaryPersistenceAdapter(TrackJpaRepository trackJpaRepository) {
        this.trackJpaRepository = trackJpaRepository;
    }

    @Override
    public List<TrackSummary> findNewestAfter(TrackPosition after, int limit) {
        List<TrackJpaEntity> tracks = after == null
            ? trackJpaRepository.findNewest(limit)
            : trackJpaRepository.findNewestAfter(after.createdAt(), after.id(), limit);

        return tracks.stream().map(TrackSummaryPersistenceAdapter::toSummary).toList();
    }

    private static TrackSummary toSummary(TrackJpaEntity track) {
        return new TrackSummary(
            track.getId(),
            track.getTitle(),
            track.getDescription(),
            track.getStatus(),
            track.getCreatedAt(),
            null
        );
    }
}
