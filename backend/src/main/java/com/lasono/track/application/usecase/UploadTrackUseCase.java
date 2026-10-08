package com.lasono.track.application.usecase;

import java.util.UUID;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.OwnerId;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.model.Visibility;

@Component 
public class UploadTrackUseCase {

    private final AudioStorage audioStorage;
    private final TrackRepository trackRepository;
    private final ProcessingJobQueue processingJobQueue;
    private final StoredAudioCleanup cleanup;

    public UploadTrackUseCase(
        AudioStorage audioStorage,
        TrackRepository trackRepository,
        ProcessingJobQueue processingJobQueue
    ) {
        this.audioStorage = audioStorage;
        this.trackRepository = trackRepository;
        this.processingJobQueue = processingJobQueue;
        this.cleanup = new StoredAudioCleanup(audioStorage);
    }

    @Transactional
    public UploadTrackResult execute(UploadTrackCommand command) {
        AudioFormat format = AudioFormat.fromMimeType(command.mimeType());

        // Validates the title and the visibility before any file is written.
        Track track = new Track(
            new TrackId(UUID.randomUUID()),
            new OwnerId(command.ownerId()),
            command.title(),
            command.description(),
            Visibility.parse(command.visibility())
        );

        StorageKey key = audioStorage.store(command.audioData(), format);

        try {
            OriginalAudio originalAudio = new OriginalAudio(
                key.value(),
                format,
                command.fileSize(),
                command.mimeType()
            );

            track.uploadCompleted(originalAudio);
            trackRepository.save(track);
            processingJobQueue.enqueue(track.getId());
        } catch (RuntimeException e) {
            cleanup.deleteQuietly(key, e);
            throw e;
        }

        return new UploadTrackResult(
            track.getId().getValue().toString(),
            track.getTitle(),
            track.getStatus().toString()
        );
    }
}