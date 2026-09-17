package com.lasono.track.application.usecase;

import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;

@Component 
public class UploadTrackUseCase {

    private final AudioStorage audioStorage;
    private final TrackRepository trackRepository;

    public UploadTrackUseCase(
        AudioStorage audioStorage,
        TrackRepository trackRepository
    ) {
        this.audioStorage = audioStorage;
        this.trackRepository = trackRepository;
    }

    public UploadTrackResult execute(UploadTrackCommand command) {
        StorageKey key = audioStorage.store(command.audioData(), command.originalFileName());
        
        Track track = new Track(
            new TrackId(UUID.randomUUID()), 
            command.title(), 
            command.description()
        );

        AudioFormat format = AudioFormat.fromMimeType(command.mimeType());
        OriginalAudio originalAudio = new OriginalAudio(
            key.value(), 
            format, 
            command.fileSize(), 
            command.mimeType()
        );

        track.uploadCompleted(originalAudio);

        trackRepository.save(track);

        return new UploadTrackResult(
            track.getId().getValue().toString(),
            track.getTitle(),
            track.getStatus().toString()
        );
    }
}