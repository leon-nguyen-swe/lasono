package com.lasono.track.infrastructure.persistence;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface AudioResourceJpaRepository extends JpaRepository<AudioResourceJpaEntity, UUID> {  
    Optional<AudioResourceJpaEntity> findByTrack_Id(UUID trackId);

    /** Reads only these two columns, so the waveform of every track is not loaded just to show a list. */
    @Query("select a.track.id as trackId, a.durationMs as durationMs "
        + "from AudioResourceJpaEntity a where a.track.id in :trackIds")
    List<DurationOfTrack> findDurationsByTrackIds(@Param("trackIds") Collection<UUID> trackIds);

    interface DurationOfTrack {

        UUID getTrackId();

        Long getDurationMs();
    }
}