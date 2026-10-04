package com.lasono.track.infrastructure.persistence;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TrackJpaRepository extends JpaRepository<TrackJpaEntity, UUID> {

    @Query(
        value = "SELECT * FROM tracks ORDER BY created_at DESC, id DESC LIMIT :limit",
        nativeQuery = true)
    List<TrackJpaEntity> findNewest(@Param("limit") int limit);

    // Keyset pagination: compare the (created_at, id) pair, so the index
    // idx_tracks_created_at_id can be used and tracks created at the same time are not skipped.
    @Query(
        value = "SELECT * FROM tracks WHERE (created_at, id) < (:createdAt, :id) "
            + "ORDER BY created_at DESC, id DESC LIMIT :limit",
        nativeQuery = true)
    List<TrackJpaEntity> findNewestAfter(
        @Param("createdAt") Instant createdAt,
        @Param("id") UUID id,
        @Param("limit") int limit);
}
