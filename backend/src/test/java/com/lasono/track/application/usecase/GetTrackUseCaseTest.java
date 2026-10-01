package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;

@ExtendWith(MockitoExtension.class)
class GetTrackUseCaseTest {

    @Mock
    private TrackRepository trackRepository;

    private GetTrackUseCase useCase;

    @BeforeEach
    void setUp() {
        useCase = new GetTrackUseCase(trackRepository);
    }

    @Test
    void returnsTrackInfoWhenTrackExists() {
        UUID id = UUID.randomUUID();
        Track track = new Track(new TrackId(id), "My song", "Some description");
        track.uploadCompleted(new OriginalAudio(
            "abc.mp3", AudioFormat.fromMimeType("audio/mpeg"), 1024, "audio/mpeg"
        ));
        when(trackRepository.findById(new TrackId(id))).thenReturn(Optional.of(track));

        GetTrackResult result = useCase.execute(id);

        assertEquals(id.toString(), result.id());
        assertEquals("My song", result.title());
        assertEquals("Some description", result.description());
        assertEquals("PROCESSING", result.status());
        assertEquals("audio/mpeg", result.mimeType());
        assertNull(result.durationSeconds());
    }

    @Test
    void throwsTrackNotFoundWhenTrackDoesNotExist() {
        UUID id = UUID.randomUUID();
        when(trackRepository.findById(new TrackId(id))).thenReturn(Optional.empty());

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id));
    }

    @Test
    void returnsStreamingMimeTypeAndDurationWhenTrackIsReady() {
        UUID id = UUID.randomUUID();
        Track track = new Track(new TrackId(id), "My song", "Some description");
        track.uploadCompleted(new OriginalAudio(
            "original.wav", AudioFormat.fromMimeType("audio/mpeg"), 2048, "audio/wav"
        ));
        track.startProcessing();
        track.processingCompleted(
            new StreamingAudio("stream.mp3", AudioFormat.fromMimeType("audio/mpeg"), 1024, "audio/mpeg"),
            new AudioDuration(3500),
            new Waveform(List.of(0.1f, 0.5f))
        );
        when(trackRepository.findById(new TrackId(id))).thenReturn(Optional.of(track));

        GetTrackResult result = useCase.execute(id);

        assertEquals("READY", result.status());
        assertEquals("audio/mpeg", result.mimeType());
        assertEquals(3.5, result.durationSeconds());
    }
}