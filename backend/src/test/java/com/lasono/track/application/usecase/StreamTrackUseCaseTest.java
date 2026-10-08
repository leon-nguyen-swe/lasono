package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.ZoneOffset;
import java.time.Instant;
import java.time.Clock;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.InMemoryTrackRepository;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;
import com.lasono.track.domain.model.Visibility;

class StreamTrackUseCaseTest {

    private static final Instant NOW = Instant.parse("2026-10-08T10:00:00Z");
    private static final byte[] ORIGINAL = "original wav".getBytes(StandardCharsets.UTF_8);
    private static final byte[] MP3 = "0123456789".getBytes(StandardCharsets.UTF_8);

    private InMemoryTrackRepository trackRepository;
    private InMemoryAudioStorage storage;
    private StreamTrackUseCase useCase;

    @BeforeEach
    void setUp() {
        trackRepository = new InMemoryTrackRepository();
        storage = new InMemoryAudioStorage();
        useCase = new StreamTrackUseCase(
            trackRepository, storage, new FakeStreamUrlSigner(), Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void execute_shouldStreamTheConvertedMp3OfAReadyTrack() throws Exception {
        UUID id = aReadyTrack();

        StreamTrackResult result = useCase.execute(id, null, null, null);

        assertEquals("audio/mpeg", result.mimeType());
        assertEquals(MP3.length, result.fileSize());
        assertArrayEquals(MP3, result.stream().readAllBytes());
    }

    @Test
    void execute_shouldStreamOnlyTheRequestedRange() throws Exception {
        UUID id = aReadyTrack();

        StreamTrackResult result = useCase.execute(id, "bytes=2-5", null, null);

        assertTrue(result.partial());
        assertArrayEquals("2345".getBytes(StandardCharsets.UTF_8), result.stream().readAllBytes());
    }

    @Test
    void execute_shouldRefuseATrackThatIsStillProcessing() {
        UUID id = anUploadedTrack();

        assertThrows(TrackNotReadyException.class, () -> useCase.execute(id, null, null, null));
    }

    @Test
    void execute_shouldRefuseATrackWhoseProcessingFailed() {
        UUID id = anUploadedTrack();
        Track track = trackRepository.findById(new TrackId(id)).orElseThrow();
        track.startProcessing();
        track.processingFailed();
        trackRepository.save(track);

        assertThrows(TrackNotReadyException.class, () -> useCase.execute(id, null, null, null));
    }

    @Test
    void execute_shouldThrowWhenTheTrackDoesNotExist() {
        UUID missing = UUID.randomUUID();

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(missing, null, null, null));
    }

    private UUID anUploadedTrack() {
        return anUploadedTrack(Visibility.PUBLIC);
    }

    private UUID anUploadedTrack(Visibility visibility) {
        StorageKey key = storage.store(new ByteArrayInputStream(ORIGINAL), AudioFormat.WAV);
        Track track = new Track(new TrackId(UUID.randomUUID()), TrackFixtures.OWNER, "My Song", "desc", visibility);
        track.uploadCompleted(new OriginalAudio(key.value(), AudioFormat.WAV, ORIGINAL.length, "audio/wav"));
        trackRepository.save(track);
        return track.getId().getValue();
    }

    private UUID aReadyTrack() {
        return aReadyTrack(Visibility.PUBLIC);
    }

    private UUID aReadyTrack(Visibility visibility) {
        UUID id = anUploadedTrack(visibility);
        Track track = trackRepository.findById(new TrackId(id)).orElseThrow();
        StorageKey mp3Key = storage.store(new ByteArrayInputStream(MP3), AudioFormat.MP3);
        track.startProcessing();
        track.processingCompleted(
            new StreamingAudio(mp3Key.value(), AudioFormat.MP3, MP3.length, "audio/mpeg"),
            new AudioDuration(3000L),
            new Waveform(List.of(0.1f, 0.5f)));
        trackRepository.save(track);
        return id;
    }

    private static final UUID STRANGER = UUID.fromString("00000000-0000-0000-0000-0000000000b2");

    @Test
    void execute_shouldHideAPrivateTrackFromAStrangerAndFromSomeoneNotLoggedIn() {
        UUID id = aReadyTrack(Visibility.PRIVATE);

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id, null, STRANGER, null));
        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id, null, null, null));
    }

    // "Not ready" (409) would tell a stranger that the private track exists, so "not found" must come first.
    @Test
    void execute_shouldAnswerNotFoundNotNotReadyForAPrivateTrackOfSomeoneElse() {
        UUID id = anUploadedTrack(Visibility.PRIVATE);

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id, null, STRANGER, null));
    }

    @Test
    void execute_shouldStreamAPrivateTrackToItsOwner() throws Exception {
        UUID id = aReadyTrack(Visibility.PRIVATE);

        StreamTrackResult result = useCase.execute(id, null, TrackFixtures.OWNER.getValue(), null);

        assertArrayEquals(MP3, result.stream().readAllBytes());
    }

    @Test
    void execute_shouldStreamAPublicTrackToSomeoneNotLoggedIn() throws Exception {
        UUID id = aReadyTrack(Visibility.PUBLIC);

        assertArrayEquals(MP3, useCase.execute(id, null, null, null).stream().readAllBytes());
    }

    // --- permission carried by the address (D4): the audio player cannot send a login header ---

    private static StreamSignature signedFor(UUID trackId, long expiresAt) {
        return new StreamSignature(expiresAt, new FakeStreamUrlSigner().sign(trackId, expiresAt));
    }

    private static final long IN_THE_FUTURE = NOW.getEpochSecond() + 3600;

    @Test
    void execute_shouldStreamAPrivateTrackToAStrangerWhoHoldsAValidSignature() throws Exception {
        UUID id = aReadyTrack(Visibility.PRIVATE);

        StreamTrackResult result = useCase.execute(id, null, null, signedFor(id, IN_THE_FUTURE));

        assertArrayEquals(MP3, result.stream().readAllBytes());
    }

    @Test
    void execute_shouldRefuseASignatureMadeForAnotherTrack() {
        UUID id = aReadyTrack(Visibility.PRIVATE);
        UUID other = UUID.randomUUID();

        assertThrows(TrackNotFoundException.class,
            () -> useCase.execute(id, null, null, signedFor(other, IN_THE_FUTURE)));
    }

    @Test
    void execute_shouldRefuseATamperedOrForgedSignature() {
        UUID id = aReadyTrack(Visibility.PRIVATE);

        assertThrows(TrackNotFoundException.class,
            () -> useCase.execute(id, null, null, new StreamSignature(IN_THE_FUTURE, "forged")));
        // A valid signature for an earlier moment, with the expiry changed to a later one.
        StreamSignature stretched = new StreamSignature(IN_THE_FUTURE + 100, signedFor(id, IN_THE_FUTURE).value());
        assertThrows(TrackNotFoundException.class, () -> useCase.execute(id, null, null, stretched));
    }

    // Right at the expiry is already too late, so a signature never works one moment longer than it says.
    @Test
    void execute_shouldRefuseASignatureThatHasExpired() {
        UUID id = aReadyTrack(Visibility.PRIVATE);

        assertThrows(TrackNotFoundException.class,
            () -> useCase.execute(id, null, null, signedFor(id, NOW.getEpochSecond())));
        assertThrows(TrackNotFoundException.class,
            () -> useCase.execute(id, null, null, signedFor(id, NOW.getEpochSecond() - 60)));
    }

    @Test
    void execute_shouldAcceptASignatureUntilTheLastSecondBeforeItExpires() throws Exception {
        UUID id = aReadyTrack(Visibility.PRIVATE);

        StreamTrackResult result = useCase.execute(id, null, null, signedFor(id, NOW.getEpochSecond() + 1));

        assertArrayEquals(MP3, result.stream().readAllBytes());
    }

    @Test
    void execute_shouldStillSayNotReadyToAHolderOfAValidSignature() {
        UUID id = anUploadedTrack(Visibility.PRIVATE);

        assertThrows(TrackNotReadyException.class,
            () -> useCase.execute(id, null, null, signedFor(id, IN_THE_FUTURE)));
    }

    @Test
    void execute_shouldNotNeedASignatureForAPublicTrackAndIgnoreABadOne() throws Exception {
        UUID id = aReadyTrack(Visibility.PUBLIC);

        StreamTrackResult result = useCase.execute(id, null, null, new StreamSignature(1L, "forged"));

        assertArrayEquals(MP3, result.stream().readAllBytes());
    }
}
