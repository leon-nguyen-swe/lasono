package com.lasono.identity.presentation;

import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseCookie;
import org.springframework.stereotype.Component;

@Component
public class RefreshCookies {

    public static final String NAME = "lasono_refresh";
    public static final String PATH = "/api/v1/auth";

    private final Duration timeToLive;
    private final boolean secure;

    public RefreshCookies(
        @Value("${lasono.jwt.refresh-token-ttl:30d}") Duration timeToLive,
        @Value("${lasono.auth.refresh-cookie-secure:true}") boolean secure
    ) {
        this.timeToLive = timeToLive;
        this.secure = secure;
    }

    public ResponseCookie issue(String rawRefreshToken) {
        return base(rawRefreshToken).maxAge(timeToLive).build();
    }

    /** A cookie that is already out of date, which tells the browser to delete the one it holds. */
    public ResponseCookie clear() {
        return base("").maxAge(Duration.ZERO).build();
    }

    private ResponseCookie.ResponseCookieBuilder base(String value) {
        return ResponseCookie.from(NAME, value)
            .httpOnly(true)
            .secure(secure)
            .sameSite("Strict")
            .path(PATH);
    }
}
