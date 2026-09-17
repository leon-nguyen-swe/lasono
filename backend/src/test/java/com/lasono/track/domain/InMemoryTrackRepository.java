package com.lasono.track.domain;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

public class InMemoryTrackRepository implements TrackRepository {

    private final Map<TrackId, Track> store = new HashMap<>();

    @Override
    public Track save(Track track) {
        store.put(track.getId(), track);
        return track;
    }

    @Override
    public Optional<Track> findById(TrackId id) {
        return Optional.ofNullable(store.get(id));
    }
}
