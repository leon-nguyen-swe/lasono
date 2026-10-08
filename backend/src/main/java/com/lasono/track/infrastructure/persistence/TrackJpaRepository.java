package com.lasono.track.infrastructure.persistence;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import jakarta.persistence.LockModeType;

public interface TrackJpaRepository extends JpaRepository<TrackJpaEntity, UUID> {

    // SELECT ... FOR UPDATE: the row stays locked until the surrounding transaction ends, so a second request
    // for the same track waits here. It needs a transaction around it.
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<TrackJpaEntity> findWithLockById(UUID id);

    // Only what the viewer may see: public tracks and the viewer's own. This is in the query and not applied
    // afterwards, so a page is always full and the keyset position of its last track stays correct.
    @Query(
        value = "SELECT * FROM tracks WHERE (visibility = 'PUBLIC' OR owner_id = :viewer) "
            + "ORDER BY created_at DESC, id DESC LIMIT :limit",
        nativeQuery = true)
    List<TrackJpaEntity> findNewest(@Param("viewer") UUID viewer, @Param("limit") int limit);

    // Keyset pagination: compare the (created_at, id) pair, so the index
    // idx_tracks_created_at_id can be used and tracks created at the same time are not skipped.
    @Query(
        value = "SELECT * FROM tracks WHERE (created_at, id) < (:createdAt, :id) "
            + "AND (visibility = 'PUBLIC' OR owner_id = :viewer) "
            + "ORDER BY created_at DESC, id DESC LIMIT :limit",
        nativeQuery = true)
    List<TrackJpaEntity> findNewestAfter(
        @Param("createdAt") Instant createdAt,
        @Param("id") UUID id,
        @Param("viewer") UUID viewer,
        @Param("limit") int limit);
}
