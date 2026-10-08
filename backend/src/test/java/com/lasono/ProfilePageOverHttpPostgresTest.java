package com.lasono;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import com.jayway.jsonpath.JsonPath;
import com.lasono.track.domain.OwnerId;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.model.Visibility;

/**
 * What a profile page needs, through the real HTTP stack down to PostgreSQL: the public profile and the tracks
 * of a user, which come from two modules, and the change of the display name. The app puts the two answers
 * together, so this test does the same.
 */
@AutoConfigureMockMvc
class ProfilePageOverHttpPostgresTest extends PostgresIntegrationTest {

    private static final String PASSWORD = "correct horse";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private TrackRepository trackRepository;

    private String aliceId;
    private String bobId;
    private String aliceToken;
    private String bobToken;

    @BeforeEach
    void twoUsers() throws Exception {
        aliceId = register("alice@example.com", "Alice");
        bobId = register("bob@example.com", "Bob");
        aliceToken = login("alice@example.com");
        bobToken = login("bob@example.com");
    }

    @Test
    void anyoneCanReadAProfileAndItHoldsNoEmail() throws Exception {
        mockMvc.perform(get("/api/v1/users/{id}", aliceId))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.userId").value(aliceId))
            .andExpect(jsonPath("$.displayName").value("Alice"))
            .andExpect(jsonPath("$.email").doesNotExist())
            .andExpect(jsonPath("$.password").doesNotExist())
            .andExpect(jsonPath("$.passwordHash").doesNotExist());
        mockMvc.perform(get("/api/v1/users/{id}", UUID.randomUUID())).andExpect(status().isNotFound());
    }

    @Test
    void theOwnerCanChangeTheDisplayNameAndNothingElseOfTheAccountChanges() throws Exception {
        Map<String, Object> before = jdbcTemplate.queryForMap(
            "SELECT email, password_hash FROM users WHERE id = ?", UUID.fromString(aliceId));
        OffsetDateTime createdBefore = jdbcTemplate.queryForObject(
            "SELECT created_at FROM users WHERE id = ?", OffsetDateTime.class, UUID.fromString(aliceId));

        rename(aliceToken, "  Alice B.  ")
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.displayName").value("Alice B."))
            .andExpect(jsonPath("$.email").value("alice@example.com"));

        mockMvc.perform(get("/api/v1/users/{id}", aliceId)).andExpect(jsonPath("$.displayName").value("Alice B."));
        Map<String, Object> after = jdbcTemplate.queryForMap(
            "SELECT email, password_hash FROM users WHERE id = ?", UUID.fromString(aliceId));
        assertThat(after).isEqualTo(before);
        assertThat(jdbcTemplate.queryForObject(
            "SELECT created_at FROM users WHERE id = ?", OffsetDateTime.class, UUID.fromString(aliceId)))
            .isEqualTo(createdBefore);
        // The password still works, because the hash was not touched.
        login("alice@example.com");
    }

    @Test
    void aChangeIsAlwaysToTheCallersOwnAccount() throws Exception {
        rename(aliceToken, "Alice B.").andExpect(status().isOk());

        mockMvc.perform(get("/api/v1/users/{id}", bobId)).andExpect(jsonPath("$.displayName").value("Bob"));
    }

    @Test
    void aBadNameIsRefusedAndChangesNothing() throws Exception {
        rename(aliceToken, "   ").andExpect(status().isBadRequest());
        rename(aliceToken, "x".repeat(51)).andExpect(status().isBadRequest());
        mockMvc.perform(patch("/api/v1/users/me")
                .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                .contentType(MediaType.APPLICATION_JSON).content("{}"))
            .andExpect(status().isBadRequest());

        mockMvc.perform(get("/api/v1/users/{id}", aliceId)).andExpect(jsonPath("$.displayName").value("Alice"));
    }

    @Test
    void withoutALoginNobodyCanChangeAName() throws Exception {
        mockMvc.perform(patch("/api/v1/users/me").contentType(MediaType.APPLICATION_JSON)
                .content("{\"displayName\":\"Mallory\"}"))
            .andExpect(status().isUnauthorized());

        mockMvc.perform(get("/api/v1/users/{id}", aliceId)).andExpect(jsonPath("$.displayName").value("Alice"));
    }

    @Test
    void theTracksOfAUserAreSeenByEveryoneExceptThePrivateOnesWhichOnlyTheOwnerSees() throws Exception {
        aTrack(aliceId, "Alice public", Visibility.PUBLIC);
        aTrack(aliceId, "Alice private", Visibility.PRIVATE);
        aTrack(bobId, "Bob public", Visibility.PUBLIC);

        mockMvc.perform(get("/api/v1/users/{id}/tracks", aliceId))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.items.length()").value(1))
            .andExpect(jsonPath("$.items[0].title").value("Alice public"))
            .andExpect(jsonPath("$.items[0].ownerId").value(aliceId));
        mockMvc.perform(get("/api/v1/users/{id}/tracks", aliceId).header(HttpHeaders.AUTHORIZATION, bearer(bobToken)))
            .andExpect(jsonPath("$.items.length()").value(1));
        mockMvc.perform(get("/api/v1/users/{id}/tracks", aliceId).header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
            .andExpect(jsonPath("$.items.length()").value(2));
        mockMvc.perform(get("/api/v1/users/{id}/tracks", bobId))
            .andExpect(jsonPath("$.items.length()").value(1))
            .andExpect(jsonPath("$.items[0].title").value("Bob public"));
        mockMvc.perform(get("/api/v1/users/{id}/tracks", UUID.randomUUID()))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.items.length()").value(0));
    }

    @Test
    void theTracksOfAUserCanBePagedThroughTheCursor() throws Exception {
        for (int i = 0; i < 3; i++) {
            aTrack(aliceId, "Alice " + i, Visibility.PUBLIC);
            aTrack(bobId, "Bob " + i, Visibility.PUBLIC);
        }

        String first = mockMvc.perform(get("/api/v1/users/{id}/tracks", aliceId).param("limit", "2"))
            .andExpect(jsonPath("$.items.length()").value(2))
            .andReturn().getResponse().getContentAsString();
        String cursor = JsonPath.read(first, "$.nextCursor");
        mockMvc.perform(get("/api/v1/users/{id}/tracks", aliceId).param("limit", "2").param("cursor", cursor))
            .andExpect(jsonPath("$.items.length()").value(1))
            .andExpect(jsonPath("$.nextCursor").doesNotExist());
    }

    // ---- helpers ----

    private void aTrack(String ownerId, String title, Visibility visibility) {
        trackRepository.save(new Track(
            new TrackId(UUID.randomUUID()), new OwnerId(UUID.fromString(ownerId)), title, null, visibility));
    }

    private ResultActions rename(String token, String displayName) throws Exception {
        return mockMvc.perform(patch("/api/v1/users/me")
            .header(HttpHeaders.AUTHORIZATION, bearer(token))
            .contentType(MediaType.APPLICATION_JSON)
            .content("{\"displayName\":\"" + displayName + "\"}"));
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
