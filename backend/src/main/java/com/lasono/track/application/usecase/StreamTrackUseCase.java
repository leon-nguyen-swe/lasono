package com.lasono.track.application.usecase;

import java.io.InputStream;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.OwnerId;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.model.TrackStatus;

@Component 
public class StreamTrackUseCase {

    private final TrackRepository trackRepository;
    private final AudioStorage audioStorage;

    public StreamTrackUseCase(
        TrackRepository trackRepository,
        AudioStorage audioStorage
    ) {
        this.trackRepository = trackRepository;
        this.audioStorage = audioStorage;
    }

    public StreamTrackResult execute(UUID trackId, String rangeHeader, UUID viewerId) {
        // A track the caller may not see is "not found", and this comes before "not ready": a different answer
        // for a private track would tell a stranger that it exists.
        Track track = trackRepository.findById(new TrackId(trackId))
            .filter(found -> found.isVisibleTo(viewerId == null ? null : new OwnerId(viewerId)))
            .orElseThrow(() -> new TrackNotFoundException(trackId));

        // Only the converted MP3 is played. The original upload can be a huge WAV, or a corrupt file
        // when processing failed, so a track that is not READY has nothing to stream yet.
        if (track.getStatus() != TrackStatus.READY) {
            throw new TrackNotReadyException(trackId, track.getStatus().name());
        }

        StreamingAudio audio = track.toSnapshot().streamingAudio();
        if (audio == null) {
            throw new IllegalStateException("Track " + trackId + " is READY but has no streaming audio");
        }
        String storageKeyValue = audio.getStorageKey();
        long fileSize = audio.getFileSize();
        String mimeType = audio.getMimeType();

        long[] range = RangeHeaderParser.parse(rangeHeader, fileSize);
        long start = range[0];
        long end = range[1];

        InputStream stream = audioStorage.retrieveRange(
            new StorageKey(storageKeyValue), start, end - start + 1
        );

        boolean partial = rangeHeader != null;
        return new StreamTrackResult(stream, mimeType, fileSize, start, end, partial);
    }
}
