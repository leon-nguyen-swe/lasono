package com.lasono.track.application.usecase;

import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.TrackSnapshot;

@Component 
public class GetTrackUseCase {

    private final TrackRepository trackRepository;

    public GetTrackUseCase(TrackRepository trackRepository) {
        this.trackRepository = trackRepository;
    }

    public GetTrackResult execute(UUID trackId) {
        Track track = trackRepository.findById(new TrackId(trackId))
            .orElseThrow(() -> new TrackNotFoundException(trackId));

        TrackSnapshot snapshot = track.toSnapshot();

        String mimeType = null;
        if (snapshot.streamingAudio() != null) {
            mimeType = snapshot.streamingAudio().getMimeType();
        } else if (snapshot.originalAudio() != null) {
            mimeType = snapshot.originalAudio().getMimeType();
        }

        Double durationSeconds = snapshot.audioDuration() != null ? snapshot.audioDuration().toMilliseconds() / 1000.0 : null;

        return new GetTrackResult(
            snapshot.trackId().getValue().toString(),
            snapshot.title(),
            snapshot.description(),
            snapshot.trackStatus().toString(),
            mimeType,
            durationSeconds
        );        
    }
}