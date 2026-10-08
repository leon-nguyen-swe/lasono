package com.lasono.track.presentation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import com.jayway.jsonpath.JsonPath;
import com.lasono.PostgresIntegrationTest;
import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.application.port.out.StreamUrlSigner;
import com.lasono.track.domain.OwnerId;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;
import com.lasono.track.domain.model.Visibility;

/**
 * Who may see and play a track, through the real HTTP stack down to PostgreSQL and the audio storage: the
 * security filter, the token, the controllers, the signed address and the Range bytes that come back. The pieces
 * have their own tests; this shows that a private track really stays private and that its signed address works.
 */
@AutoConfigureMockMvc
class PrivateTracksOverHttpPostgresTest extends PostgresIntegrationTest {

    private static final String PASSWORD = "correct horse";
    private static final byte[] MP3 = "0123456789".getBytes(StandardCharsets.UTF_8);

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private TrackRepository trackRepository;

    @Autowired
    private AudioStorage audioStorage;

    @Autowired
    private StreamUrlSigner signer;

    private UUID aliceId;
    private String aliceToken;
    private String bobToken;

    @BeforeEach
    void twoUsers() throws Exception {
        aliceId = UUID.fromString(register("alice@example.com", "Alice"));
        register("bob@example.com", "Bob");
        aliceToken = login("alice@example.com");
        bobToken = login("bob@example.com");
    }

    @Test
    void aPrivateTrackIsNotFoundForAStrangerAndForAnonymousUsersButShownToItsOwner() throws Exception {
        UUID id = aReadyTrack(Visibility.PRIVATE, "Secret song");

        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.AUTHORIZATION, bearer(bobToken)))
            .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}", id)).andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.title").value("Secret song"))
            .andExpect(jsonPath("$.visibility").value("PRIVATE"));
    }

    // D7: the same answer as for a track that was never there, so nobody learns that it exists.
    @Test
    void thePrivateTrackAnswerLooksLikeTheAnswerForAnUnknownTrack() throws Exception {
        UUID id = aReadyTrack(Visibility.PRIVATE, "Secret song");

        String unknown = mockMvc.perform(get("/api/v1/tracks/{id}", UUID.randomUUID())).andReturn()
            .getResponse().getContentAsString();
        String hidden = mockMvc.perform(get("/api/v1/tracks/{id}", id)).andReturn().getResponse().getContentAsString();

        assertThat(withoutIds(hidden)).isEqualTo(withoutIds(unknown));
    }

    @Test
    void theListShowsPublicTracksToEveryoneAndPrivateTracksOnlyToTheirOwner() throws Exception {
        aReadyTrack(Visibility.PUBLIC, "Public song");
        aReadyTrack(Visibility.PRIVATE, "Secret song");

        mockMvc.perform(get("/api/v1/tracks"))
            .andExpect(jsonPath("$.items.length()").value(1))
            .andExpect(jsonPath("$.items[0].title").value("Public song"));
        mockMvc.perform(get("/api/v1/tracks").header(HttpHeaders.AUTHORIZATION, bearer(bobToken)))
            .andExpect(jsonPath("$.items.length()").value(1));
        mockMvc.perform(get("/api/v1/tracks").header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
            .andExpect(jsonPath("$.items.length()").value(2));
    }

    @Test
    void aStrangerCannotStreamAPrivateTrackOrGetAnAddressForIt() throws Exception {
        UUID id = aReadyTrack(Visibility.PRIVATE, "Secret song");

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id)).andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id).header(HttpHeaders.AUTHORIZATION, bearer(bobToken)))
            .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}/stream-url", id).header(HttpHeaders.AUTHORIZATION, bearer(bobToken)))
            .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}/stream-url", id)).andExpect(status().isNotFound());
    }

    // The point of the signed address: an audio player holds no login header, yet it can play, with Range.
    @Test
    void theOwnersSignedAddressPlaysThePrivateTrackForAnAnonymousPlayerIncludingRanges() throws Exception {
        UUID id = aReadyTrack(Visibility.PRIVATE, "Secret song");
        MvcResult issued = mockMvc.perform(
                get("/api/v1/tracks/{id}/stream-url", id).header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
            .andExpect(status().isOk())
            .andExpect(header().string("Cache-Control", "no-store"))
            .andReturn();
        String url = JsonPath.read(issued.getResponse().getContentAsString(), "$.url");

        assertThat(streamed(get(url))).isEqualTo(MP3);
        MvcResult partial = mockMvc.perform(get(url).header(HttpHeaders.RANGE, "bytes=2-5"))
            .andExpect(request().asyncStarted()).andReturn();
        mockMvc.perform(asyncDispatch(partial))
            .andExpect(status().isPartialContent())
            .andExpect(header().string(HttpHeaders.CONTENT_RANGE, "bytes 2-5/10"))
            .andExpect(content().bytes("2345".getBytes(StandardCharsets.UTF_8)));
    }

    @Test
    void aSignedAddressDoesNotWorkWhenItIsTamperedWithExpiredOrForAnotherTrack() throws Exception {
        UUID id = aReadyTrack(Visibility.PRIVATE, "Secret song");
        UUID other = aReadyTrack(Visibility.PRIVATE, "Other secret");
        long future = Instant.now().getEpochSecond() + 3600;
        long past = Instant.now().getEpochSecond() - 10;
        String good = signer.sign(id, future);
        String tampered = (good.charAt(0) == 'A' ? "B" : "A") + good.substring(1);

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id)
                .param("expires", "" + future).param("signature", tampered))
            .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id)
                .param("expires", "" + (future + 60)).param("signature", good))
            .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id)
                .param("expires", "" + past).param("signature", signer.sign(id, past)))
            .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}/stream", other)
                .param("expires", "" + future).param("signature", good))
            .andExpect(status().isNotFound());
    }

    @Test
    void aPublicTrackPlaysWithoutAnySignature() throws Exception {
        UUID id = aReadyTrack(Visibility.PUBLIC, "Public song");

        assertThat(streamed(get("/api/v1/tracks/{id}/stream", id))).isEqualTo(MP3);
    }

    @Test
    void anUploadStoresTheVisibilityTheOwnerChose() throws Exception {
        upload(aliceToken, "Hidden", "PRIVATE").andExpect(status().isCreated());
        upload(aliceToken, "Shown", null).andExpect(status().isCreated());

        assertThat(jdbcTemplate.queryForObject("SELECT visibility FROM tracks WHERE title = 'Hidden'", String.class))
            .isEqualTo("PRIVATE");
        assertThat(jdbcTemplate.queryForObject("SELECT visibility FROM tracks WHERE title = 'Shown'", String.class))
            .isEqualTo("PUBLIC");
    }

    @Test
    void anUploadWithAnUnknownVisibilityIsRefusedAndStoresNothing() throws Exception {
        upload(aliceToken, "Typo", "privat").andExpect(status().isBadRequest());

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM tracks", Integer.class)).isZero();
    }

    // ---- helpers ----

    private UUID aReadyTrack(Visibility visibility, String title) {
        StorageKey key = audioStorage.store(new ByteArrayInputStream(MP3), AudioFormat.MP3);
        Track track = new Track(new TrackId(UUID.randomUUID()), new OwnerId(aliceId), title, null, visibility);
        track.uploadCompleted(new OriginalAudio(key.value(), AudioFormat.MP3, MP3.length, "audio/mpeg"));
        track.startProcessing();
        track.processingCompleted(
            new StreamingAudio(key.value(), AudioFormat.MP3, MP3.length, "audio/mpeg"),
            new AudioDuration(3000L),
            new Waveform(List.of(0.1f, 0.5f)));
        trackRepository.save(track);
        return track.getId().getValue();
    }

    /** The body of a streamed response, which is written on another thread and so needs an async dispatch. */
    private byte[] streamed(MockHttpServletRequestBuilder builder) throws Exception {
        MvcResult started = mockMvc.perform(builder).andExpect(request().asyncStarted()).andReturn();
        return mockMvc.perform(asyncDispatch(started)).andExpect(status().isOk()).andReturn().getResponse()
            .getContentAsByteArray();
    }

    private static String withoutIds(String body) {
        return body.replaceAll("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", "ID");
    }

    private ResultActions upload(String token, String title, String visibility) throws Exception {
        var builder = multipart("/api/v1/tracks")
            .file(new MockMultipartFile("file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes()))
            .param("title", title)
            .header(HttpHeaders.AUTHORIZATION, bearer(token));
        if (visibility != null) {
            builder.param("visibility", visibility);
        }
        return mockMvc.perform(builder);
    }

    private static String bearer(String token) {
        return "Bearer " + token;
    }

    private String register(String email, String displayName) throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"displayName\":\"" + displayName
                    + "\",\"password\":\"" + PASSWORD + "\"}"))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.userId");
    }

    private String login(String email) throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"password\":\"" + PASSWORD + "\"}"))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.accessToken");
    }
}
