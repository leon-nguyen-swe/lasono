package com.lasono.track.application.usecase;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionOperations;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.TrackSnapshot;
import com.lasono.track.domain.model.TrackStatus;

@Component
public class DeleteTrackUseCase {

    private static final Logger log = LoggerFactory.getLogger(DeleteTrackUseCase.class);

    private final TrackRepository trackRepository;
    private final ProcessingJobQueue processingJobQueue;
    private final AudioStorage audioStorage;
    private final TransactionOperations transaction;

    public DeleteTrackUseCase(
        TrackRepository trackRepository,
        ProcessingJobQueue processingJobQueue,
        AudioStorage audioStorage,
        TransactionOperations transaction
    ) {
        this.trackRepository = trackRepository;
        this.processingJobQueue = processingJobQueue;
        this.audioStorage = audioStorage;
        this.transaction = transaction;
    }

    // Not @Transactional as a whole: the files must be deleted after the database change is committed, and a
    // method-wide transaction would still be open while they are. The order matters. If the files went first and
    // the commit then failed, a track would point at files that are gone. This way the worst case is a file that
    // nobody refers to any more.
    public void execute(UUID trackId, UUID requesterId) {
        List<StorageKey> files = transaction.execute(status -> removeFromDatabase(trackId, requesterId));

        for (StorageKey file : files) {
            deleteQuietly(file);
        }
    }

    private List<StorageKey> removeFromDatabase(UUID trackId, UUID requesterId) {
        Track track = OwnedTrack.findForChange(trackRepository, trackId, requesterId);
        if (track.getStatus() == TrackStatus.PROCESSING) {
            throw new TrackStillProcessingException(trackId);
        }

        TrackSnapshot snapshot = track.toSnapshot();
        List<StorageKey> files = new ArrayList<>();
        if (snapshot.originalAudio() != null) {
            files.add(new StorageKey(snapshot.originalAudio().getStorageKey()));
        }
        if (snapshot.streamingAudio() != null) {
            files.add(new StorageKey(snapshot.streamingAudio().getStorageKey()));
        }

        processingJobQueue.discardJobsOf(track.getId());
        trackRepository.delete(track.getId());
        return files;
    }

    // The track is already gone, so a file that cannot be removed is a leftover and not a failed delete.
    private void deleteQuietly(StorageKey file) {
        try {
            audioStorage.delete(file);
        } catch (RuntimeException e) {
            log.warn("Could not delete the file {} of a deleted track; it is left behind", file.value(), e);
        }
    }
}
