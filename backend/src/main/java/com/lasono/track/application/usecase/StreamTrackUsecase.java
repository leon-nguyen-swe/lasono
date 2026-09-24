package com.lasono.track.application.usecase;

import java.io.InputStream;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.TrackSnapshot;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;

@Component 
public class StreamTrackUsecase {

    private final TrackRepository trackRepository;
    private final AudioStorage audioStorage;

    public StreamTrackUsecase(
        TrackRepository trackRepository,
        AudioStorage audioStorage
    ) {
        this.trackRepository = trackRepository;
        this.audioStorage = audioStorage;
    }

    public StreamTrackResult execute(UUID trackId, String rangeHeader) {
        Track track = trackRepository.findById(new TrackId(trackId))
            .orElseThrow(() -> new TrackNotFoundException(trackId));
        
        TrackSnapshot snapshot = track.toSnapshot();

        String storageKeyValue;
        long fileSize;
        String mimeType;

        if (snapshot.streamingAudio() != null) {
            StreamingAudio audio = snapshot.streamingAudio();
            storageKeyValue = audio.getStorageKey();
            fileSize = audio.getFileSize();
            mimeType = audio.getMimeType();
        } else if (snapshot.originalAudio() != null) {
            OriginalAudio originalAudio = snapshot.originalAudio();
            storageKeyValue = originalAudio.getStorageKey();
            fileSize = originalAudio.getFileSize();
            mimeType = originalAudio.getMimeType();
        } else {
            throw new IllegalStateException("Track " + trackId + " has no audio resource");
        }

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
