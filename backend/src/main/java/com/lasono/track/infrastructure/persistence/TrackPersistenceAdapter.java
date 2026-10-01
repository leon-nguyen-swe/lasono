package com.lasono.track.infrastructure.persistence;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.springframework.stereotype.Repository;

import com.lasono.track.domain.AudioResource;
import com.lasono.track.domain.AudioResourceId;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.TrackSnapshot;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;

@Repository 
public class TrackPersistenceAdapter implements TrackRepository {

    private final TrackJpaRepository trackJpaRepository;
    private final AudioResourceJpaRepository audioResourceJpaRepository;

    public TrackPersistenceAdapter(
        TrackJpaRepository trackJpaRepository,
        AudioResourceJpaRepository audioResourceJpaRepository
    ) {
        this.trackJpaRepository = trackJpaRepository;
        this.audioResourceJpaRepository = audioResourceJpaRepository;
    }

    @Override 
    public Track save(Track track) {
        TrackSnapshot snapshot = track.toSnapshot();

        TrackJpaEntity trackEntity = new TrackJpaEntity(
            snapshot.trackId().getValue(),
            snapshot.title(),
            snapshot.description(),
            snapshot.trackStatus()
        );

        OriginalAudio originalAudio = snapshot.originalAudio();
        StreamingAudio streamingAudio = snapshot.streamingAudio();
        AudioDuration audioDuration = snapshot.audioDuration();
        AudioResourceJpaEntity audioResourceEntity = new AudioResourceJpaEntity(
            snapshot.audioResourceId().getValue(),
            trackEntity,
            snapshot.audioResourceStatus(),
            originalAudio != null ? originalAudio.getStorageKey() : null,
            originalAudio != null ? originalAudio.getFormat().name() : null,
            originalAudio != null ? originalAudio.getFileSize() : null,
            originalAudio != null ? originalAudio.getMimeType() : null,
            streamingAudio != null ? streamingAudio.getStorageKey() : null,
            streamingAudio != null ? streamingAudio.getFormat().name() : null,
            streamingAudio != null ? streamingAudio.getFileSize() : null,
            streamingAudio != null ? streamingAudio.getMimeType() : null,
            audioDuration != null ? audioDuration.toMilliseconds() : null,
            toFloatArray(snapshot.waveform())
        );

        trackJpaRepository.save(trackEntity);
        audioResourceJpaRepository.save(audioResourceEntity);

        return track;
    }

    private float[] toFloatArray(Waveform waveform) {
        if (waveform == null) {
            return null;
        }
        List<Float> samples = waveform.getSamples();
        float[] result = new float[samples.size()];
        for (int i = 0; i < samples.size(); i++) {
            result[i] = samples.get(i);
        }
        return result;
    }

    public Optional<Track> findById(TrackId id) {
        Optional<TrackJpaEntity> trackEntity = trackJpaRepository.findById(id.getValue());
        if (trackEntity.isEmpty()) {
            return Optional.empty();
        }

        Optional<AudioResourceJpaEntity> audioResourceEntity = audioResourceJpaRepository.findByTrack_Id(id.getValue());
        if (audioResourceEntity.isEmpty()) {
            return Optional.empty();
        }

        TrackJpaEntity track = trackEntity.get();
        AudioResourceJpaEntity audioResource = audioResourceEntity.get();

        OriginalAudio originalAudio = null;
        if (audioResource.getOriginalStorageKey() != null) {
            originalAudio = new OriginalAudio(
                audioResource.getOriginalStorageKey(),
                AudioFormat.valueOf(audioResource.getOriginalFormat()), 
                audioResource.getOriginalFileSize(), 
                audioResource.getOriginalMimeType()
            );
        }

        StreamingAudio streamingAudio = null;
        if (audioResource.getStreamingStorageKey() != null) {
            streamingAudio = new StreamingAudio(
                audioResource.getStreamingStorageKey(), 
                AudioFormat.valueOf(audioResource.getStreamingFormat()), 
                audioResource.getStreamingFileSize(), 
                audioResource.getStreamingMimeType()
            );
        }

        AudioDuration audioDuration = null;
        if (audioResource.getDurationMs() != null) {
            audioDuration = new AudioDuration(audioResource.getDurationMs());
        }

        Waveform waveform = null;
        if (audioResource.getWaveformSamples() != null) {
            List<Float> samples = new ArrayList<>();
            for (float sample : audioResource.getWaveformSamples()) {
                samples.add(sample);
            }
            waveform = new Waveform(samples);
        }

        AudioResource domainAudioResource = AudioResource.reconstitute(
            new AudioResourceId(audioResource.getId()), 
            audioResource.getStatus(), 
            originalAudio, 
            streamingAudio, 
            audioDuration, 
            waveform
        );

        Track domainTrack = Track.reconstitute(
            new TrackId(track.getId()), 
            track.getTitle(), 
            track.getDescription(), 
            track.getStatus(), 
            domainAudioResource
        );

        return Optional.of(domainTrack);
    }
}
