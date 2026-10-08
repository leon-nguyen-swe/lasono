package com.lasono.track.application.usecase;

import java.util.UUID;

import com.lasono.track.domain.OwnerId;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;

/** The rule for changing or deleting a track, in one place so that both use cases answer alike. */
final class OwnedTrack {

    private OwnedTrack() {
    }

    /**
     * Finds the track and locks it until the transaction ends. A track the caller may not see is "not found",
     * as everywhere else (D7), so a private track of someone else cannot be told from one that is not there.
     * A track the caller can see but does not own is "not yours": there is nothing to hide about a public track.
     */
    static Track findForChange(TrackRepository trackRepository, UUID trackId, UUID requesterId) {
        OwnerId requester = new OwnerId(requesterId);
        Track track = trackRepository.findByIdForUpdate(new TrackId(trackId))
            .filter(found -> found.isVisibleTo(requester))
            .orElseThrow(() -> new TrackNotFoundException(trackId));
        if (!track.isOwnedBy(requester)) {
            throw new TrackNotOwnedException(trackId);
        }
        return track;
    }
}
