package com.lasono.track.domain;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

/**
 * Keeps what was saved, not the object itself: like a database, a change the caller did not
 * {@link #save} is not visible to the next {@link #findById}.
 */
public class InMemoryTrackRepository implements TrackRepository {

    private final Map<TrackId, TrackSnapshot> store = new HashMap<>();

    @Override
    public Track save(Track track) {
        store.put(track.getId(), track.toSnapshot());
        return track;
    }

    @Override
    public Optional<Track> findById(TrackId id) {
        return Optional.ofNullable(store.get(id)).map(InMemoryTrackRepository::toTrack);
    }

    /** There is nothing to lock in memory: a test that needs the lock to wait runs against PostgreSQL. */
    @Override
    public Optional<Track> findByIdForUpdate(TrackId id) {
        return findById(id);
    }

    @Override
    public void delete(TrackId id) {
        store.remove(id);
    }

    private static Track toTrack(TrackSnapshot snapshot) {
        AudioResource audioResource = AudioResource.reconstitute(
            snapshot.audioResourceId(),
            snapshot.audioResourceStatus(),
            snapshot.originalAudio(),
            snapshot.streamingAudio(),
            snapshot.audioDuration(),
            snapshot.waveform());
        return Track.reconstitute(
            snapshot.trackId(), snapshot.ownerId(), snapshot.title(), snapshot.description(), snapshot.visibility(), snapshot.trackStatus(),
            audioResource);
    }
}
