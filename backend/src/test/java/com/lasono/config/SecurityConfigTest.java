package com.lasono.config;

import static org.junit.jupiter.api.Assertions.assertNull;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

/**
 * Runs the whole application (on H2) behind the real security filter chain. The other controller tests
 * build a bare MockMvc without it, so only this class can show who may call what.
 */
@SpringBootTest
@AutoConfigureMockMvc
class SecurityConfigTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void registerIsOpenToAnonymousUsersAndNeedsNoCsrfToken() throws Exception {
        String body = "{\"email\":\"" + UUID.randomUUID() + "@example.com\","
            + "\"displayName\":\"Alice\",\"password\":\"correct horse\"}";

        mockMvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON).content(body))
            .andExpect(status().isCreated());
    }

    // Temporary: the track endpoints stay open until the upload requires a login.
    @Test
    void theTrackListIsStillOpen() throws Exception {
        mockMvc.perform(get("/api/v1/tracks"))
            .andExpect(status().isOk());
    }

    // Security runs before CorsFilter, so without cors() the browser's preflight would be refused.
    @Test
    void aPreflightFromTheFlutterAppIsAnswered() throws Exception {
        mockMvc.perform(options("/api/v1/auth/register")
                .header(HttpHeaders.ORIGIN, "http://localhost:3000")
                .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST")
                .header(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "content-type"))
            .andExpect(status().isOk())
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:3000"));
    }

    @Test
    void anyOtherPathNeedsAuthentication() throws Exception {
        mockMvc.perform(get("/api/v1/does-not-exist"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    void noSessionIsCreated() throws Exception {
        MvcResult result = mockMvc.perform(get("/api/v1/tracks"))
            .andExpect(header().doesNotExist(HttpHeaders.SET_COOKIE))
            .andReturn();

        assertNull(result.getRequest().getSession(false));
    }

    @Test
    void theApiDocumentationStaysPublic() throws Exception {
        mockMvc.perform(get("/v3/api-docs"))
            .andExpect(status().isOk());
    }
}
