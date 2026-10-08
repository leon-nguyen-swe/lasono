package com.lasono.track.application.usecase;

import java.io.InputStream;
import java.time.Clock;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.application.port.out.StreamUrlSigner;
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
    private final StreamUrlSigner streamUrlSigner;
    private final Clock clock;

    public StreamTrackUseCase(
        TrackRepository trackRepository,
        AudioStorage audioStorage,
        StreamUrlSigner streamUrlSigner,
        Clock clock
    ) {
        this.trackRepository = trackRepository;
        this.audioStorage = audioStorage;
        this.streamUrlSigner = streamUrlSigner;
        this.clock = clock;
    }

    public StreamTrackResult execute(UUID trackId, String rangeHeader, UUID viewerId, StreamSignature signature) {
        // A track the caller may not see is "not found", and this comes before "not ready": a different answer
        // for a private track would tell a stranger that it exists. The caller may see it as its owner, or by
        // holding a signature that was only handed out to someone who could.
        Track track = trackRepository.findById(new TrackId(trackId))
            .filter(found -> found.isVisibleTo(viewerId == null ? null : new OwnerId(viewerId))
                || holdsValidSignature(trackId, signature))
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

    private boolean holdsValidSignature(UUID trackId, StreamSignature signature) {
        if (signature == null) {
            return false;
        }
        // Right at the expiry is already too late.
        boolean stillValid = clock.instant().getEpochSecond() < signature.expiresAtEpochSecond();
        return stillValid
            && streamUrlSigner.isValid(trackId, signature.expiresAtEpochSecond(), signature.value());
    }
}
