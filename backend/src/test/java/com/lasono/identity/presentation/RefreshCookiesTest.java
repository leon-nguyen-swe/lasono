package com.lasono.identity.presentation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;

import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseCookie;

class RefreshCookiesTest {

    private static final Duration TTL = Duration.ofDays(30);

    @Test
    void issue_shouldHideTheTokenFromScriptsAndKeepItOnTheAuthRoutesOnly() {
        ResponseCookie cookie = new RefreshCookies(TTL, true).issue("the-token");

        assertEquals("lasono_refresh", cookie.getName());
        assertEquals("the-token", cookie.getValue());
        // HttpOnly: JavaScript cannot read it, so a script injected into the page cannot steal it.
        assertTrue(cookie.isHttpOnly());
        // Strict: the browser never sends it with a request that starts on another site.
        assertEquals("Strict", cookie.getSameSite());
        // Only the auth routes need it, so it is not sent along with every other request.
        assertEquals("/api/v1/auth", cookie.getPath());
        assertEquals(TTL, cookie.getMaxAge());
    }

    @Test
    void issue_shouldBeSecureUnlessTheConfigurationSaysOtherwise() {
        assertTrue(new RefreshCookies(TTL, true).issue("t").isSecure());
        assertFalse(new RefreshCookies(TTL, false).issue("t").isSecure());
    }

    // A browser removes a cookie only when name, path and the other identifying attributes match the one it
    // stored, so the cookie that ends the session must repeat them.
    @Test
    void clear_shouldEmptyTheCookieNowWithTheSameAttributes() {
        RefreshCookies cookies = new RefreshCookies(TTL, true);

        ResponseCookie cleared = cookies.clear();

        assertEquals("lasono_refresh", cleared.getName());
        assertEquals("", cleared.getValue());
        assertEquals(Duration.ZERO, cleared.getMaxAge());
        assertEquals(cookies.issue("t").getPath(), cleared.getPath());
        assertTrue(cleared.isHttpOnly());
        assertEquals("Strict", cleared.getSameSite());
        assertTrue(cleared.isSecure());
    }
}
