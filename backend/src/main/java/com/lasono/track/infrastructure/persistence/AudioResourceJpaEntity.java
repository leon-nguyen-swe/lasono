package com.lasono.track.infrastructure.persistence;

import java.util.UUID;

import com.lasono.track.domain.audio.model.AudioResourceStatus;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter 
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor 
@Entity
@Table(name = "audio_resources")
public class AudioResourceJpaEntity {

    @Id
    private UUID id;

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "track_id", nullable = false)
    private TrackJpaEntity track;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private AudioResourceStatus status;

    @Column(name = "original_storage_key", length = 512)
    private String originalStorageKey;

    @Column(name = "original_format", length = 50)
    private String originalFormat;

    @Column(name = "original_file_size")
    private Long originalFileSize;
    
    @Column(name = "original_mime_type", length = 100)
    private String originalMimeType;

    @Column(name = "streaming_storage_key", length = 512)
    private String streamingStorageKey;

    @Column(name = "streaming_format", length = 50)
    private String streamingFormat;

    @Column(name = "streaming_file_size")
    private Long streamingFileSize;

    @Column(name = "streaming_mime_type", length = 100)
    private String streamingMimeType;

    @Column(name = "duration_ms")
    private Long durationMs;

    @Column(name = "waveform_samples")
    private float[] waveformSamples;
}
