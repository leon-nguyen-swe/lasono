package com.lasono.track.domain;

import java.util.Optional;

public interface TrackRepository {

    Track save(Track track);

    Optional<Track> findById(TrackId id);
}
