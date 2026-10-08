package com.lasono.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.InsufficientAuthenticationException;
import org.springframework.security.oauth2.server.resource.InvalidBearerTokenException;

import com.jayway.jsonpath.JsonPath;

class ProblemDetailSecurityHandlerTest {

    private final ProblemDetailSecurityHandler handler = new ProblemDetailSecurityHandler();
    private final MockHttpServletRequest request = new MockHttpServletRequest();
    private final MockHttpServletResponse response = new MockHttpServletResponse();

    @Test
    void commence_answers401WithAProblemDetailBody() throws Exception {
        handler.commence(request, response, new InsufficientAuthenticationException("no token"));

        assertThat(response.getStatus()).isEqualTo(401);
        assertThat(response.getContentType()).startsWith("application/problem+json");
        assertThat(JsonPath.<Integer>read(response.getContentAsString(), "$.status")).isEqualTo(401);
        assertThat(JsonPath.<String>read(response.getContentAsString(), "$.title")).isEqualTo("Unauthorized");
        assertThat(JsonPath.<String>read(response.getContentAsString(), "$.detail"))
            .isEqualTo("Authentication is required to access this resource");
    }

    @Test
    void commence_tellsAClientWithoutATokenThatBearerIsTheWayToLogIn() throws Exception {
        handler.commence(request, response, new InsufficientAuthenticationException("no token"));

        assertThat(response.getHeader("WWW-Authenticate")).isEqualTo("Bearer");
    }

    @Test
    void commence_marksARejectedTokenAsInvalidTokenButNeverSaysWhy() throws Exception {
        handler.commence(request, response, new InvalidBearerTokenException("Jwt expired at 2026-01-01T00:00:00Z"));

        assertThat(response.getHeader("WWW-Authenticate")).startsWith("Bearer").contains("error=\"invalid_token\"");
        assertThat(response.getContentAsString()).doesNotContain("expired").doesNotContain("2026");
    }

    @Test
    void handle_answers403WithAProblemDetailBody() throws Exception {
        handler.handle(request, response, new AccessDeniedException("not yours"));

        assertThat(response.getStatus()).isEqualTo(403);
        assertThat(response.getContentType()).startsWith("application/problem+json");
        assertThat(JsonPath.<Integer>read(response.getContentAsString(), "$.status")).isEqualTo(403);
        assertThat(JsonPath.<String>read(response.getContentAsString(), "$.detail"))
            .isEqualTo("You are not allowed to access this resource");
        assertThat(response.getContentAsString()).doesNotContain("not yours");
    }
}
