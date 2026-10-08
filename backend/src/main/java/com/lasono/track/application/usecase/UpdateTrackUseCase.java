package com.lasono.track.application.usecase;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.model.Visibility;

@Component
public class UpdateTrackUseCase {

    private final TrackRepository trackRepository;

    public UpdateTrackUseCase(TrackRepository trackRepository) {
        this.trackRepository = trackRepository;
    }

    // One transaction holds the lock on the track from the read to the save. Without it, a change that read the
    // track before a delete would save its copy after it, and the deleted track would be back.
    @Transactional
    public GetTrackResult execute(UpdateTrackCommand command) {
        Track track = OwnedTrack.findForChange(trackRepository, command.trackId(), command.requesterId());

        // Nothing is saved until every field has been accepted, so a bad one cannot leave the others half applied.
        if (command.title() != null) {
            track.rename(command.title());
        }
        if (command.description() != null) {
            track.changeDescription(command.description());
        }
        if (command.visibility() != null) {
            track.changeVisibility(Visibility.parse(command.visibility()));
        }

        trackRepository.save(track);
        return GetTrackResult.from(track);
    }
}
