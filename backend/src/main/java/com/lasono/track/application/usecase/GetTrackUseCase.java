package com.lasono.track.application.usecase;

import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.track.domain.OwnerId;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;

@Component 
public class GetTrackUseCase {

    private final TrackRepository trackRepository;

    public GetTrackUseCase(TrackRepository trackRepository) {
        this.trackRepository = trackRepository;
    }

    public GetTrackResult execute(UUID trackId, UUID viewerId) {
        Track track = trackRepository.findById(new TrackId(trackId))
            .filter(found -> found.isVisibleTo(viewerId == null ? null : new OwnerId(viewerId)))
            .orElseThrow(() -> new TrackNotFoundException(trackId));

        return GetTrackResult.from(track);
    }
}