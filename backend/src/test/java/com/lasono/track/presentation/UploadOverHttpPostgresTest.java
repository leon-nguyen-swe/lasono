package com.lasono.track.presentation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import com.jayway.jsonpath.JsonPath;
import com.lasono.PostgresIntegrationTest;

/**
 * Registers, logs in and uploads a track through the real HTTP stack down to PostgreSQL, then reads
 * {@code tracks.owner_id}. The pieces are tested one by one elsewhere; this shows that the id in the token ends
 * up in the column, and that nobody can put another user's id there.
 */
@AutoConfigureMockMvc
class UploadOverHttpPostgresTest extends PostgresIntegrationTest {

    private static final String PASSWORD = "correct horse";

    @Autowired
    private MockMvc mockMvc;

    @Test
    void aTrackIsStoredWithTheIdOfTheUserWhoUploadedIt() throws Exception {
        String aliceId = register("alice@example.com", "Alice");
        String token = loginAndGetToken("alice@example.com");

        upload(token, "My Song", null).andExpect(status().isCreated());

        assertThat(jdbcTemplate.queryForList("SELECT title, owner_id FROM tracks"))
            .singleElement()
            .satisfies(track -> {
                assertThat(track.get("title")).isEqualTo("My Song");
                assertThat(track.get("owner_id")).isEqualTo(UUID.fromString(aliceId));
            });
    }

    // The owner comes from the token. A form field cannot name someone else as the owner.
    @Test
    void anOwnerIdSentInTheFormIsIgnored() throws Exception {
        String aliceId = register("alice@example.com", "Alice");
        String bobId = register("bob@example.com", "Bob");
        String bobsToken = loginAndGetToken("bob@example.com");

        upload(bobsToken, "Bob's song", aliceId).andExpect(status().isCreated());

        UUID owner = jdbcTemplate.queryForObject("SELECT owner_id FROM tracks", UUID.class);
        assertThat(owner).isEqualTo(UUID.fromString(bobId)).isNotEqualTo(UUID.fromString(aliceId));
    }

    @Test
    void anUploadWithoutALoginIsRefusedAndStoresNothing() throws Exception {
        upload(null, "My Song", null).andExpect(status().isUnauthorized());

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM tracks", Integer.class)).isZero();
        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM processing_jobs", Integer.class)).isZero();
    }

    private ResultActions upload(String token, String title, String ownerIdField) throws Exception {
        var request = multipart("/api/v1/tracks")
            .file(new MockMultipartFile("file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes()))
            .param("title", title);
        if (ownerIdField != null) {
            request.param("ownerId", ownerIdField);
        }
        if (token != null) {
            request.header(HttpHeaders.AUTHORIZATION, "Bearer " + token);
        }
        return mockMvc.perform(request);
    }

    private String register(String email, String displayName) throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"displayName\":\"" + displayName
                    + "\",\"password\":\"" + PASSWORD + "\"}"))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.userId");
    }

    private String loginAndGetToken(String email) throws Exception {
        String body = mockMvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"password\":\"" + PASSWORD + "\"}"))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.accessToken");
    }
}
