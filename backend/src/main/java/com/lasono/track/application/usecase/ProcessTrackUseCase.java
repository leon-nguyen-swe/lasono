package com.lasono.track.application.usecase;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.UUID;

import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.AudioProcessor;
import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.application.port.out.ProcessedAudio;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.model.TrackStatus;

/**
 * Processes the audio of one uploaded track: reads its duration, builds its waveform and stores an
 * MP3 to stream, then marks the track READY. The heavy work runs outside any database transaction.
 */
@Component
public class ProcessTrackUseCase {

    private final TrackRepository trackRepository;
    private final AudioStorage audioStorage;
    private final AudioProcessor audioProcessor;

    public ProcessTrackUseCase(
        TrackRepository trackRepository,
        AudioStorage audioStorage,
        AudioProcessor audioProcessor
    ) {
        this.trackRepository = trackRepository;
        this.audioStorage = audioStorage;
        this.audioProcessor = audioProcessor;
    }

    public void execute(UUID trackId) {
        Track track = trackRepository.findById(new TrackId(trackId))
            .orElseThrow(() -> new TrackNotFoundException(trackId));
        if (track.getStatus() != TrackStatus.PROCESSING) {
            // Already finished (READY or FAILED), e.g. the worker died after saving but before
            // reporting the job as done. Running the job again must change nothing.
            return;
        }
        OriginalAudio original = track.toSnapshot().originalAudio();

        // Only in memory: the database keeps the track as it was until the work is finished, so a
        // retry after a crash starts from the same state.
        track.startProcessing();

        ProcessedAudio processed = process(original);

        byte[] mp3 = processed.streamingAudio();
        StorageKey mp3Key = audioStorage.store(new ByteArrayInputStream(mp3), AudioFormat.MP3);
        track.processingCompleted(
            new StreamingAudio(mp3Key.value(), AudioFormat.MP3, mp3.length, "audio/mpeg"),
            processed.duration(),
            processed.waveform());
        trackRepository.save(track);
    }

    private ProcessedAudio process(OriginalAudio original) {
        try (InputStream audio = audioStorage.retrieve(new StorageKey(original.getStorageKey()))) {
            return audioProcessor.process(audio);
        } catch (IOException e) {
            throw new AudioStorageException("Failed to read the original audio", e);
        }
    }
}
