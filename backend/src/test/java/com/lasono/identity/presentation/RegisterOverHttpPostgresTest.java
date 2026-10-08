package com.lasono.identity.presentation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import com.lasono.PostgresIntegrationTest;

/**
 * Signs up through the real HTTP stack down to PostgreSQL: security filter, controller, use case,
 * BCrypt and the users table. Each piece has its own test; this one shows they fit together.
 */
@AutoConfigureMockMvc
class RegisterOverHttpPostgresTest extends PostgresIntegrationTest {

    private static final String PASSWORD = "correct horse";

    @Autowired
    private MockMvc mockMvc;

    @Test
    void aNewUserIsStoredWithABCryptHashAndTheResponseNeverShowsIt() throws Exception {
        String response = register("alice@example.com", "Alice", PASSWORD)
            .andExpect(status().isCreated())
            .andReturn().getResponse().getContentAsString();

        String storedHash = jdbcTemplate.queryForObject("SELECT password_hash FROM users", String.class);
        assertThat(storedHash).startsWith("$2a$10$").isNotEqualTo(PASSWORD);
        assertThat(response).doesNotContain(PASSWORD).doesNotContain(storedHash);
    }

    @Test
    void theSameEmailCannotRegisterTwiceEvenWithDifferentCase() throws Exception {
        register("alice@example.com", "Alice", PASSWORD).andExpect(status().isCreated());

        register("ALICE@Example.com", "Impostor", "another password").andExpect(status().isConflict());

        assertThat(jdbcTemplate.queryForList("SELECT display_name FROM users", String.class))
            .containsExactly("Alice");
    }

    @Test
    void aTooShortPasswordIsRefusedAndNothingIsStored() throws Exception {
        register("alice@example.com", "Alice", "short").andExpect(status().isBadRequest());

        assertThat(jdbcTemplate.queryForObject("SELECT count(*) FROM users", Integer.class)).isZero();
    }

    private ResultActions register(String email, String displayName, String password) throws Exception {
        String body = "{\"email\":\"" + email + "\",\"displayName\":\"" + displayName
            + "\",\"password\":\"" + password + "\"}";
        return mockMvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON).content(body));
    }
}
