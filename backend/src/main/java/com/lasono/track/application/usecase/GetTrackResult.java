package com.lasono.track.application.usecase;

import java.util.List;

import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackSnapshot;

public record GetTrackResult(
    String id,
    String ownerId,
    String title,
    String description,
    String visibility,
    String status,
    String mimeType,
    Double durationSeconds,
    List<Float> waveform
) {

    public static GetTrackResult from(Track track) {
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
            snapshot.ownerId().getValue().toString(),
            snapshot.title(),
            snapshot.description(),
            snapshot.visibility().name(),
            snapshot.trackStatus().toString(),
            mimeType,
            durationSeconds,
            snapshot.waveform() != null ? snapshot.waveform().getSamples() : null
        );
    }
}
