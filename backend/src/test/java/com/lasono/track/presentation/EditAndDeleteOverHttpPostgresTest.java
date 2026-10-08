package com.lasono.track.presentation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import com.jayway.jsonpath.JsonPath;
import com.lasono.PostgresIntegrationTest;
import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.application.port.out.StorageKey;
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
 * Edits and deletes a track through the real HTTP stack down to PostgreSQL and the audio storage: the security
 * filter, the token, the controller, the use cases and the files on disk. The rules (D7) are that someone who
 * cannot see a track gets 404, someone who can see it but does not own it gets 403, and only the owner may act.
 */
@AutoConfigureMockMvc
class EditAndDeleteOverHttpPostgresTest extends PostgresIntegrationTest {

    private static final String PASSWORD = "correct horse";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private TrackRepository trackRepository;

    @Autowired
    private ProcessingJobQueue jobQueue;

    @Autowired
    private AudioStorage audioStorage;

    @Value("${lasono.storage.root}")
    private String storageRoot;

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
    void theOwnerCanEditATrackAndEveryoneSeesTheChange() throws Exception {
        UUID id = aReadyTrack(Visibility.PUBLIC);

        editAs(aliceToken, id, "{\"title\":\"Renamed\",\"description\":\"\"}")
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.title").value("Renamed"))
            .andExpect(jsonPath("$.description").value(""))
            .andExpect(jsonPath("$.visibility").value("PUBLIC"));

        mockMvc.perform(get("/api/v1/tracks/{id}", id))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.title").value("Renamed"));
    }

    // Making a track private takes it away from everyone else at once.
    @Test
    void makingATrackPrivateHidesItFromEveryoneElse() throws Exception {
        UUID id = aReadyTrack(Visibility.PUBLIC);
        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.AUTHORIZATION, bearer(bobToken)))
            .andExpect(status().isOk());

        editAs(aliceToken, id, "{\"visibility\":\"PRIVATE\"}").andExpect(status().isOk());

        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.AUTHORIZATION, bearer(bobToken)))
            .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
            .andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/tracks")).andExpect(jsonPath("$.items.length()").value(0));
    }

    @Test
    void anEditWithABadTitleOrVisibilityIsRefusedAndChangesNothing() throws Exception {
        aReadyTrack(Visibility.PUBLIC);
        UUID id = jdbcTemplate.queryForObject("SELECT id FROM tracks", UUID.class);

        editAs(aliceToken, id, "{\"title\":\"   \",\"visibility\":\"PRIVATE\"}").andExpect(status().isBadRequest());
        editAs(aliceToken, id, "{\"title\":\"Renamed\",\"visibility\":\"secret\"}").andExpect(status().isBadRequest());

        assertThat(jdbcTemplate.queryForMap("SELECT title, visibility FROM tracks"))
            .containsEntry("title", "My Song").containsEntry("visibility", "PUBLIC");
    }

    // D7: Bob can see Alice's public track, so he is told it is not his (403) ...
    @Test
    void someoneElseCannotEditOrDeleteAPublicTrackAndGets403() throws Exception {
        UUID id = aReadyTrack(Visibility.PUBLIC);

        editAs(bobToken, id, "{\"title\":\"Hijacked\"}").andExpect(status().isForbidden());
        deleteAs(bobToken, id).andExpect(status().isForbidden());

        assertThat(jdbcTemplate.queryForMap("SELECT title, visibility FROM tracks"))
            .containsEntry("title", "My Song").containsEntry("visibility", "PUBLIC");
        assertThat(count("audio_resources")).isEqualTo(1);
    }

    // ... but cannot see her private track, so it looks like there is none (404).
    @Test
    void someoneElseCannotEditOrDeleteAPrivateTrackAndGets404() throws Exception {
        UUID id = aReadyTrack(Visibility.PRIVATE);

        editAs(bobToken, id, "{\"title\":\"Hijacked\"}").andExpect(status().isNotFound());
        deleteAs(bobToken, id).andExpect(status().isNotFound());

        assertThat(count("tracks")).isEqualTo(1);
    }

    @Test
    void withoutALoginNobodyCanEditOrDelete() throws Exception {
        UUID id = aReadyTrack(Visibility.PUBLIC);

        mockMvc.perform(patch("/api/v1/tracks/{id}", id).contentType(MediaType.APPLICATION_JSON).content("{}"))
            .andExpect(status().isUnauthorized());
        mockMvc.perform(delete("/api/v1/tracks/{id}", id)).andExpect(status().isUnauthorized());

        assertThat(count("tracks")).isEqualTo(1);
    }

    @Test
    void theOwnerCanDeleteATrackAndItsRowsAndFilesGoAway() throws Exception {
        UUID id = aReadyTrack(Visibility.PUBLIC);
        UUID other = aReadyTrack(Visibility.PUBLIC);
        List<StorageKey> files = filesOf(id);
        assertThat(files).hasSize(2).allMatch(this::onDisk);

        deleteAs(aliceToken, id).andExpect(status().isNoContent());

        mockMvc.perform(get("/api/v1/tracks/{id}", id)).andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}", other)).andExpect(status().isOk());
        assertThat(count("tracks")).isEqualTo(1);
        assertThat(count("audio_resources")).isEqualTo(1);
        assertThat(count("processing_jobs")).isEqualTo(1);
        assertThat(files).noneMatch(this::onDisk);
        deleteAs(aliceToken, id).andExpect(status().isNotFound());
    }

    @Test
    void aTrackThatIsStillBeingProcessedCannotBeDeletedYet() throws Exception {
        mockMvc.perform(multipart("/api/v1/tracks")
                .file(new MockMultipartFile("file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes()))
                .param("title", "Busy")
                .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
            .andExpect(status().isCreated());
        UUID id = jdbcTemplate.queryForObject("SELECT id FROM tracks", UUID.class);

        deleteAs(aliceToken, id).andExpect(status().isConflict());

        assertThat(count("tracks")).isEqualTo(1);
        assertThat(count("processing_jobs")).isEqualTo(1);
    }

    // ---- helpers ----

    private UUID aReadyTrack(Visibility visibility) {
        StorageKey original = audioStorage.store(new ByteArrayInputStream("original".getBytes()), AudioFormat.WAV);
        StorageKey mp3 = audioStorage.store(new ByteArrayInputStream("0123456789".getBytes()), AudioFormat.MP3);
        Track track = new Track(new TrackId(UUID.randomUUID()), new OwnerId(aliceId), "My Song", "desc", visibility);
        track.uploadCompleted(new OriginalAudio(original.value(), AudioFormat.WAV, 8, "audio/wav"));
        track.startProcessing();
        track.processingCompleted(
            new StreamingAudio(mp3.value(), AudioFormat.MP3, 10, "audio/mpeg"),
            new AudioDuration(3000L),
            new Waveform(List.of(0.1f, 0.5f)));
        trackRepository.save(track);
        jobQueue.enqueue(track.getId());
        return track.getId().getValue();
    }

    private List<StorageKey> filesOf(UUID id) {
        Track track = trackRepository.findById(new TrackId(id)).orElseThrow();
        return List.of(
            new StorageKey(track.toSnapshot().originalAudio().getStorageKey()),
            new StorageKey(track.toSnapshot().streamingAudio().getStorageKey()));
    }

    private boolean onDisk(StorageKey key) {
        return Files.exists(Path.of(storageRoot).resolve(key.value()));
    }

    private int count(String table) {
        return jdbcTemplate.queryForObject("SELECT count(*) FROM " + table, Integer.class);
    }

    private ResultActions editAs(String token, UUID id, String json) throws Exception {
        return mockMvc.perform(patch("/api/v1/tracks/{id}", id)
            .header(HttpHeaders.AUTHORIZATION, bearer(token))
            .contentType(MediaType.APPLICATION_JSON)
            .content(json));
    }

    private ResultActions deleteAs(String token, UUID id) throws Exception {
        return mockMvc.perform(delete("/api/v1/tracks/{id}", id).header(HttpHeaders.AUTHORIZATION, bearer(token)));
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
