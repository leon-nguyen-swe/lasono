package com.lasono.track.domain;

import java.util.Objects;
import java.util.UUID;

import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;
import com.lasono.track.domain.exception.TrackInvalidStateException;
import com.lasono.track.domain.exception.TrackTitleInvalidException;
import com.lasono.track.domain.model.TrackStatus;

public class Track {

    private final TrackId id;
    private TrackStatus status;
    private String title;
    private String description;
    private final AudioResource audioResource;

    public Track(TrackId id, String title, String description) {
        validateTitle(title);
        this.id = Objects.requireNonNull(id);
        this.title = title;
        this.description = description;
        this.audioResource = new AudioResource(new AudioResourceId(UUID.randomUUID()));
        this.status = TrackStatus.PROCESSING;
    }

    private Track(TrackId id, String title, String description, TrackStatus status, AudioResource audioResource) {
        this.id = Objects.requireNonNull(id);
        this.title = title;
        this.description = description;
        this.status = Objects.requireNonNull(status);
        this.audioResource = Objects.requireNonNull(audioResource);
    }

    public static Track reconstitute(
        TrackId id,
        String title,
        String description,
        TrackStatus status,
        AudioResource audioResource
    ) {
        return new Track(id, title, description, status, audioResource);
    }

    public TrackId getId() {
        return this.id;
    }

    public TrackStatus getStatus() {
        return this.status;
    }

    public String getTitle() {
        return this.title;
    }

    public String getDescription() {
        return this.description;
    }

    public TrackSnapshot toSnapshot() {
        return new TrackSnapshot(
            this.id,
            this.title,
            this.description,
            this.status,
            this.audioResource.getId(),
            this.audioResource.getStatus(),
            this.audioResource.getOriginalAudio(),
            this.audioResource.getStreamingAudio(),
            this.audioResource.getAudioDuration(),
            this.audioResource.getWaveform()
        );
    }

    public void uploadCompleted(OriginalAudio originalAudio) {
        if (this.status != TrackStatus.PROCESSING) {
            throw new TrackInvalidStateException("Cannot upload audio when track state is: " + this.status);
        }
        this.audioResource.uploadCompleted(originalAudio);
    }

    public void startProcessing() {
        if (this.status != TrackStatus.PROCESSING) {
            throw new TrackInvalidStateException("Cannot start processing audio when track state is: " + this.status);
        }
        this.audioResource.startProcessing();
    }

    public void processingCompleted(StreamingAudio streamingAudio, AudioDuration audioDuration, Waveform waveform) {
        if (this.status != TrackStatus.PROCESSING) {
            throw new TrackInvalidStateException("Expected track state: PROCESSING\nActual track state: " + this.status);
        }
        this.audioResource.processingCompleted(streamingAudio, audioDuration, waveform);
        this.status = TrackStatus.READY;
    }

    public void rename(String newTitle) {
        validateTitle(newTitle);
        this.title = newTitle;
    }

    private void validateTitle(String title) {
        if (title == null) {
            throw new TrackTitleInvalidException("Track title must not be null");
        }
        if (title.isBlank()) {
            throw new TrackTitleInvalidException("Track title must not be blank");
        }
    }
}