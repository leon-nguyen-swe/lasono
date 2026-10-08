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

    private static final UUID NOBODY = new UUID(0L, 0L);

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
    public List<TrackSummary> findNewestOfOwnerAfter(UUID ownerId, TrackPosition after, int limit, UUID viewerId) {
        UUID viewer = viewerOrNobody(viewerId);
        List<TrackJpaEntity> tracks = after == null
            ? trackJpaRepository.findNewestOfOwner(ownerId, viewer, limit)
            : trackJpaRepository.findNewestOfOwnerAfter(ownerId, viewer, after.createdAt(), after.id(), limit);
        return withDurations(tracks);
    }

    @Override
    public List<TrackSummary> findNewestAfter(TrackPosition after, int limit, UUID viewerId) {
        UUID viewer = viewerOrNobody(viewerId);
        List<TrackJpaEntity> tracks = after == null
            ? trackJpaRepository.findNewest(viewer, limit)
            : trackJpaRepository.findNewestAfter(after.createdAt(), after.id(), viewer, limit);
        return withDurations(tracks);
    }

    // Nobody logged in is "a viewer who owns nothing". A real value keeps the query simple: a null parameter
    // has no type for PostgreSQL to compare with. No user has the all-zero id.
    private static UUID viewerOrNobody(UUID viewerId) {
        return viewerId == null ? NOBODY : viewerId;
    }

    private List<TrackSummary> withDurations(List<TrackJpaEntity> tracks) {
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
            track.getOwnerId(),
            track.getTitle(),
            track.getDescription(),
            track.getVisibility(),
            track.getStatus(),
            track.getCreatedAt(),
            durationMs
        );
    }
}
