package com.lasono.identity.presentation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import com.jayway.jsonpath.JsonPath;
import com.lasono.PostgresIntegrationTest;

/**
 * Registers, logs in and reads the profile through the real HTTP stack down to PostgreSQL: security filter,
 * controllers, use cases, BCrypt, the token and the users table. Each piece has its own test; this one shows
 * they fit together.
 */
@AutoConfigureMockMvc
class AuthenticationOverHttpPostgresTest extends PostgresIntegrationTest {

    private static final String PASSWORD = "correct horse";

    @Autowired
    private MockMvc mockMvc;

    @Test
    void aUserWhoRegisteredCanLogInAndReadTheirProfile() throws Exception {
        String userId = JsonPath.read(register("alice@example.com", "Alice"), "$.userId");

        String token = JsonPath.read(login("alice@example.com", PASSWORD).andReturn().getResponse().getContentAsString(),
            "$.accessToken");

        mockMvc.perform(get("/api/v1/users/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.userId").value(userId))
            .andExpect(jsonPath("$.email").value("alice@example.com"))
            .andExpect(jsonPath("$.displayName").value("Alice"));
    }

    @Test
    void theEmailMayBeTypedInAnotherCaseWithSpacesAroundIt() throws Exception {
        register("alice@example.com", "Alice");

        login("  ALICE@Example.com ", PASSWORD).andExpect(status().isOk());
    }

    @Test
    void aWrongPasswordAndAnUnknownEmailGetExactlyTheSameAnswer() throws Exception {
        register("alice@example.com", "Alice");

        String wrongPassword = login("alice@example.com", "wrong horse")
            .andExpect(status().isUnauthorized()).andReturn().getResponse().getContentAsString();
        String unknownEmail = login("nobody@example.com", PASSWORD)
            .andExpect(status().isUnauthorized()).andReturn().getResponse().getContentAsString();

        assertThat(wrongPassword).isEqualTo(unknownEmail);
    }

    @Test
    void aTokenStopsWorkingWhenItsAccountIsGone() throws Exception {
        register("alice@example.com", "Alice");
        String token = JsonPath.read(login("alice@example.com", PASSWORD).andReturn().getResponse().getContentAsString(),
            "$.accessToken");

        jdbcTemplate.update("DELETE FROM users");

        mockMvc.perform(get("/api/v1/users/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("The account of this token no longer exists"));
    }

    // A token is only signed, not encrypted, so anyone can read it. Nothing personal may be inside.
    @Test
    void theTokenCarriesNoEmailAndNoName() throws Exception {
        register("alice@example.com", "Alice");
        String token = JsonPath.read(login("alice@example.com", PASSWORD).andReturn().getResponse().getContentAsString(),
            "$.accessToken");

        String payload = new String(Base64.getUrlDecoder().decode(token.split("\\.")[1]), StandardCharsets.UTF_8);

        assertThat(payload).doesNotContain("alice@example.com").doesNotContain("Alice");
    }

    private String register(String email, String displayName) throws Exception {
        return mockMvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"displayName\":\"" + displayName
                    + "\",\"password\":\"" + PASSWORD + "\"}"))
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString();
    }

    private ResultActions login(String email, String password) throws Exception {
        return mockMvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
            .content("{\"email\":\"" + email + "\",\"password\":\"" + password + "\"}"));
    }
}
