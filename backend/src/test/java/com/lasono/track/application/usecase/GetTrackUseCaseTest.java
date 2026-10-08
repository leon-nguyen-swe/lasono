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
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;
import com.lasono.track.domain.model.Visibility;

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
        Track track = new Track(new TrackId(id), TrackFixtures.OWNER, "My song", "Some description");
        track.uploadCompleted(new OriginalAudio(
            "abc.mp3", AudioFormat.fromMimeType("audio/mpeg"), 1024, "audio/mpeg"
        ));
        when(trackRepository.findById(new TrackId(id))).thenReturn(Optional.of(track));

        GetTrackResult result = useCase.execute(id, null);

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

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id, null));
    }

    @Test
    void returnsStreamingMimeTypeAndDurationWhenTrackIsReady() {
        UUID id = UUID.randomUUID();
        Track track = new Track(new TrackId(id), TrackFixtures.OWNER, "My song", "Some description");
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

        GetTrackResult result = useCase.execute(id, null);

        assertEquals("READY", result.status());
        assertEquals("audio/mpeg", result.mimeType());
        assertEquals(3.5, result.durationSeconds());
    }

    @Test
    void returnsTheWaveformWhenTrackIsReady() {
        UUID id = UUID.randomUUID();
        Track track = new Track(new TrackId(id), TrackFixtures.OWNER, "My song", "Some description");
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

        GetTrackResult result = useCase.execute(id, null);

        assertEquals(List.of(0.1f, 0.5f), result.waveform());
    }

    @Test
    void hasNoWaveformWhileTheTrackIsStillProcessing() {
        UUID id = UUID.randomUUID();
        Track track = new Track(new TrackId(id), TrackFixtures.OWNER, "My song", "Some description");
        track.uploadCompleted(new OriginalAudio(
            "abc.mp3", AudioFormat.fromMimeType("audio/mpeg"), 1024, "audio/mpeg"
        ));
        when(trackRepository.findById(new TrackId(id))).thenReturn(Optional.of(track));

        assertNull(useCase.execute(id, null).waveform());
    }

    private static final UUID STRANGER = UUID.fromString("00000000-0000-0000-0000-0000000000b2");

    private UUID aPrivateTrack() {
        UUID id = UUID.randomUUID();
        Track track = new Track(new TrackId(id), TrackFixtures.OWNER, "Secret song", null, Visibility.PRIVATE);
        when(trackRepository.findById(new TrackId(id))).thenReturn(Optional.of(track));
        return id;
    }

    // D7: "not found", not "forbidden", so nobody can tell that a private track exists.
    @Test
    void hidesAPrivateTrackFromAStrangerAsIfItDidNotExist() {
        UUID id = aPrivateTrack();

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id, STRANGER));
    }

    @Test
    void hidesAPrivateTrackFromSomeoneWhoIsNotLoggedIn() {
        UUID id = aPrivateTrack();

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id, null));
    }

    @Test
    void showsAPrivateTrackToItsOwner() {
        UUID id = aPrivateTrack();

        GetTrackResult result = useCase.execute(id, TrackFixtures.OWNER.getValue());

        assertEquals("Secret song", result.title());
        assertEquals("PRIVATE", result.visibility());
    }

    @Test
    void showsAPublicTrackToEveryoneWithItsVisibility() {
        UUID id = UUID.randomUUID();
        Track track = new Track(new TrackId(id), TrackFixtures.OWNER, "My song", null);
        when(trackRepository.findById(new TrackId(id))).thenReturn(Optional.of(track));

        assertEquals("PUBLIC", useCase.execute(id, null).visibility());
        assertEquals("PUBLIC", useCase.execute(id, STRANGER).visibility());
    }

    @Test
    void showsWhoOwnsTheTrack() {
        UUID id = UUID.randomUUID();
        when(trackRepository.findById(new TrackId(id))).thenReturn(
            Optional.of(new Track(new TrackId(id), TrackFixtures.OWNER, "My song", null)));

        assertEquals(TrackFixtures.OWNER.getValue().toString(), useCase.execute(id, null).ownerId());
    }
}
