package com.lasono.config;

import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import com.jayway.jsonpath.JsonPath;

/**
 * Runs the whole application (on H2) behind the real security filter chain. The other controller tests
 * build a bare MockMvc without it, so only this class can show who may call what.
 */
@SpringBootTest
@AutoConfigureMockMvc
class SecurityConfigTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JwtEncoder jwtEncoder;

    private static String sign(JwtEncoder encoder, Instant issuedAt, Instant expiresAt) {
        JwtClaimsSet claims = JwtClaimsSet.builder()
            .issuer(JwtConfig.ISSUER)
            .subject(UUID.randomUUID().toString())
            .issuedAt(issuedAt)
            .expiresAt(expiresAt)
            .build();
        return encoder.encode(JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), claims))
            .getTokenValue();
    }

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
    void meWithoutATokenAsksForOneInAProblemJsonAnswer() throws Exception {
        mockMvc.perform(get("/api/v1/users/me"))
            .andExpect(status().isUnauthorized())
            .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
            .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, "Bearer"));
    }

    @Test
    void meWithATokenThatIsNotAJwtIsRefused() throws Exception {
        mockMvc.perform(get("/api/v1/users/me").header(HttpHeaders.AUTHORIZATION, "Bearer not.a.jwt"))
            .andExpect(status().isUnauthorized())
            .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
            .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, containsString("error=\"invalid_token\"")));
    }

    @Test
    void meWithAnExpiredTokenIsRefused() throws Exception {
        String token = sign(jwtEncoder, Instant.now().minus(2, ChronoUnit.HOURS), Instant.now().minus(1, ChronoUnit.HOURS));

        mockMvc.perform(get("/api/v1/users/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
            .andExpect(status().isUnauthorized())
            .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, containsString("error=\"invalid_token\"")));
    }

    @Test
    void meWithATokenSignedByAnotherSecretIsRefused() throws Exception {
        JwtEncoder strangersEncoder = new JwtConfig().jwtEncoder("another-secret-with-at-least-32-bytes!");
        String token = sign(strangersEncoder, Instant.now(), Instant.now().plus(10, ChronoUnit.MINUTES));

        mockMvc.perform(get("/api/v1/users/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
            .andExpect(status().isUnauthorized())
            .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, containsString("error=\"invalid_token\"")));
    }

    @Test
    void aRegisteredUserCanLogInAndReadTheirOwnProfile() throws Exception {
        String email = UUID.randomUUID() + "@example.com";
        mockMvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"displayName\":\"Alice\",\"password\":\"correct horse\"}"))
            .andExpect(status().isCreated());
        String login = mockMvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"password\":\"correct horse\"}"))
            .andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString();
        String token = JsonPath.read(login, "$.accessToken");

        mockMvc.perform(get("/api/v1/users/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.email").value(email))
            .andExpect(jsonPath("$.displayName").value("Alice"));
    }

    // The app keeps sending its old token. A login must not be refused because of it: the answer to a
    // wrong password has to be about the password.
    @Test
    void loginIsNotBlockedByAStaleTokenInTheHeader() throws Exception {
        String stale = sign(jwtEncoder, Instant.now().minus(2, ChronoUnit.HOURS), Instant.now().minus(1, ChronoUnit.HOURS));

        mockMvc.perform(post("/api/v1/auth/login")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + stale)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"nobody@example.com\",\"password\":\"wrong horse\"}"))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("Invalid email or password"));
    }

    @Test
    void theApiDocumentationStaysPublic() throws Exception {
        mockMvc.perform(get("/v3/api-docs"))
            .andExpect(status().isOk());
    }
}
