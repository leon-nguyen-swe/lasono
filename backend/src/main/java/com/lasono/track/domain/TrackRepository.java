package com.lasono.track.domain;

import java.util.Optional;

public interface TrackRepository {

    Track save(Track track);

    Optional<Track> findById(TrackId id);

    /**
     * Like {@link #findById}, and also locks the track until the surrounding transaction ends, so two requests
     * that change or delete the same track wait for each other. Without the lock, a change that loses the race
     * to a delete would save its copy and bring the deleted track back. Needs a transaction around it.
     */
    Optional<Track> findByIdForUpdate(TrackId id);

    /** Removes the track and its audio resource. Removing a track that does not exist does nothing. */
    void delete(TrackId id);
}
