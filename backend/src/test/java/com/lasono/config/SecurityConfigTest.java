package com.lasono.config;

import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import jakarta.servlet.http.Cookie;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
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

    // Reading stays open until tracks can be private (a later step); only changing something needs a login.
    @Test
    void theTrackListIsStillOpen() throws Exception {
        mockMvc.perform(get("/api/v1/tracks"))
            .andExpect(status().isOk());
    }

    @Test
    void aSingleTrackIsStillReadableWithoutALogin() throws Exception {
        mockMvc.perform(get("/api/v1/tracks/{id}", UUID.randomUUID()))
            .andExpect(status().isNotFound());
    }

    @Test
    void uploadingATrackNeedsALogin() throws Exception {
        MockMultipartFile file = new MockMultipartFile("file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes());

        mockMvc.perform(multipart("/api/v1/tracks").file(file).param("title", "My Song"))
            .andExpect(status().isUnauthorized())
            .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
    }

    // 400 (title missing) and not 401 shows the request got past security and reached the controller.
    @Test
    void uploadingATrackWithAValidTokenReachesTheController() throws Exception {
        String token = sign(jwtEncoder, Instant.now(), Instant.now().plus(10, ChronoUnit.MINUTES));
        MockMultipartFile file = new MockMultipartFile("file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes());

        mockMvc.perform(multipart("/api/v1/tracks").file(file).header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
            .andExpect(status().isBadRequest());
    }

    // The app sends the token in a header, so the browser first asks with an OPTIONS request that carries no
    // token at all. It must be answered even though the route itself now needs a login.
    @Test
    void aPreflightForAnUploadIsAnsweredWithoutAToken() throws Exception {
        mockMvc.perform(options("/api/v1/tracks")
                .header(HttpHeaders.ORIGIN, "http://localhost:3000")
                .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST")
                .header(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "authorization"))
            .andExpect(status().isOk())
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:3000"));
    }

    // Closed unless a route opens it: changing or deleting a track will get its own rules later.
    @Test
    void anyOtherWayOfChangingATrackNeedsALogin() throws Exception {
        mockMvc.perform(delete("/api/v1/tracks/{id}", UUID.randomUUID()))
            .andExpect(status().isUnauthorized());
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

    // localhost:3000 and localhost:8080 count as the same site, so SameSite=Strict alone would still send the
    // cookie from another page served on localhost. The Origin check is what refuses that request. The cookie
    // here is made up: 403 (not 401) proves the request was stopped before anything looked at it.
    @Test
    void refreshAndLogoutFromAnOriginThatIsNotAllowedAreRefusedBeforeTheCookieIsRead() throws Exception {
        for (String route : new String[] {"/api/v1/auth/refresh", "/api/v1/auth/logout"}) {
            mockMvc.perform(post(route)
                    .header(HttpHeaders.ORIGIN, "http://evil.example")
                    .cookie(new Cookie("lasono_refresh", "made-up")))
                .andExpect(status().isForbidden())
                .andExpect(header().doesNotExist(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN));
        }
    }

    @Test
    void refreshFromTheFlutterAppReachesTheControllerAndMayUseCookies() throws Exception {
        mockMvc.perform(post("/api/v1/auth/refresh")
                .header(HttpHeaders.ORIGIN, "http://localhost:3000")
                .cookie(new Cookie("lasono_refresh", "made-up")))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("Invalid refresh token"))
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, "http://localhost:3000"))
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_CREDENTIALS, "true"));
    }

    // Tools such as curl send no Origin. They are not the browser attack the check is for.
    @Test
    void refreshWithoutAnOriginHeaderReachesTheController() throws Exception {
        mockMvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("lasono_refresh", "made-up")))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("Invalid refresh token"));
    }

    // The access token has usually expired by the time the app refreshes, which is the very reason it refreshes.
    @Test
    void refreshIsNotBlockedByAStaleAccessTokenInTheHeader() throws Exception {
        String stale = sign(jwtEncoder, Instant.now().minus(2, ChronoUnit.HOURS), Instant.now().minus(1, ChronoUnit.HOURS));

        mockMvc.perform(post("/api/v1/auth/refresh")
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + stale)
                .cookie(new Cookie("lasono_refresh", "made-up")))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("Invalid refresh token"));
    }

    @Test
    void theApiDocumentationStaysPublic() throws Exception {
        mockMvc.perform(get("/v3/api-docs"))
            .andExpect(status().isOk());
    }
}
