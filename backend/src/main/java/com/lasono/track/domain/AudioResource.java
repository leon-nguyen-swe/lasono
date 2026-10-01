package com.lasono.track.domain;

import java.util.Objects;

import com.lasono.track.domain.audio.exception.AudioResourceInvalidException;
import com.lasono.track.domain.audio.exception.AudioResourceInvalidStateException;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioResourceStatus;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;

public class AudioResource {

    private final AudioResourceId id;
    private AudioResourceStatus status;
    private OriginalAudio originalAudio;
    private StreamingAudio streamingAudio;
    private AudioDuration audioDuration;
    private Waveform waveform;

    public AudioResource(AudioResourceId id) {
        this.id = Objects.requireNonNull(id);
        this.status = AudioResourceStatus.CREATED;
    }

    private AudioResource(
        AudioResourceId id,
        AudioResourceStatus status,
        OriginalAudio originalAudio,
        StreamingAudio streamingAudio,
        AudioDuration audioDuration,
        Waveform waveform
    ) {
        this.id = Objects.requireNonNull(id);
        this.status = Objects.requireNonNull(status);
        this.originalAudio = originalAudio;
        this.streamingAudio = streamingAudio;
        this.audioDuration = audioDuration;
        this.waveform = waveform;
    }

    public AudioResourceId getId() {
        return this.id;
    }

    public AudioResourceStatus getStatus() {
        return this.status;
    }

    public OriginalAudio getOriginalAudio() {
        return this.originalAudio;
    }

    public StreamingAudio getStreamingAudio() {
        return this.streamingAudio;
    }

    public AudioDuration getAudioDuration() {
        return this.audioDuration;
    }

    public Waveform getWaveform() {
        return this.waveform;
    }

    void uploadCompleted(OriginalAudio originalAudio) {
        if (this.status != AudioResourceStatus.CREATED) {
            throw new AudioResourceInvalidStateException("Expected state: CREATED\nActual state: " + this.status);
        }
        if (originalAudio == null) {
            throw new AudioResourceInvalidException("Original Audio must not be null");
        }
        this.originalAudio = originalAudio;
        this.status = AudioResourceStatus.UPLOADED;
    }

    void startProcessing() {
        if (this.status != AudioResourceStatus.UPLOADED) {
            throw new AudioResourceInvalidStateException("Expected state: UPLOADED\nActual state: " + this.status);
        }
        this.status = AudioResourceStatus.PROCESSING;
    }

    void processingCompleted(StreamingAudio streamingAudio, AudioDuration audioDuration, Waveform waveform) {
        if (this.status != AudioResourceStatus.PROCESSING) {
            throw new AudioResourceInvalidStateException("Expected state: PROCESSING\nActual state: " + this.status);
        }        
        if (streamingAudio == null) {
            throw new AudioResourceInvalidException("Streaming Audio must not be null");
        }
        if (audioDuration == null) {
            throw new AudioResourceInvalidException("Audio Duration must not be null");
        }
        if (waveform == null) {
            throw new AudioResourceInvalidException("Waveform must not be null");
        }
        this.streamingAudio = streamingAudio;
        this.audioDuration = audioDuration;
        this.waveform = waveform;
        this.status = AudioResourceStatus.READY;
    }
    
    public static AudioResource reconstitute(
        AudioResourceId id,
        AudioResourceStatus status,
        OriginalAudio originalAudio,
        StreamingAudio streamingAudio,
        AudioDuration audioDuration,
        Waveform waveform
    ) {
        return new AudioResource(id, status, originalAudio, streamingAudio, audioDuration, waveform);
    }
}