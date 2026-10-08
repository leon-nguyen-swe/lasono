package com.lasono.config;

import java.io.IOException;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

public class ProblemDetailSecurityHandler implements AuthenticationEntryPoint, AccessDeniedHandler {


    @Override
    public void commence(
        HttpServletRequest request,
        HttpServletResponse response,
        AuthenticationException authException
    ) throws IOException {
        // RFC 6750: say which scheme to use, and add the error code when a token was sent and refused.
        // Spring's own BearerTokenAuthenticationEntryPoint is not used because it also adds a
        // resource_metadata hint (RFC 9728) pointing to a page this server does not publish.
        String challenge = "Bearer";
        if (authException instanceof OAuth2AuthenticationException oauth2Exception) {
            challenge += " error=\"" + oauth2Exception.getError().getErrorCode() + "\"";
        }
        response.setHeader("WWW-Authenticate", challenge);
        write(response, 401, "Unauthorized", "Authentication is required to access this resource");
    }

    @Override
    public void handle(
        HttpServletRequest request,
        HttpServletResponse response,
        AccessDeniedException accessDeniedException
    ) throws IOException {
        write(response, 403, "Forbidden", "You are not allowed to access this resource");
    }

    // The texts are fixed on purpose: repeating the reason a token was refused (expired, bad signature)
    // would help someone who is probing. The JSON is written by hand because nothing in it comes from the request.
    private static void write(HttpServletResponse response, int status, String title, String detail) throws IOException {
        response.setStatus(status);
        response.setContentType("application/problem+json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write(
            "{\"type\":\"about:blank\",\"title\":\"" + title + "\",\"status\":" + status
                + ",\"detail\":\"" + detail + "\"}");
    }
}
