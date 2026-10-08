package com.lasono.identity.presentation;

import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CookieValue;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.lasono.identity.application.usecase.AuthSession;
import com.lasono.identity.application.usecase.LoginCommand;
import com.lasono.identity.application.usecase.LoginResult;
import com.lasono.identity.application.usecase.LoginUseCase;
import com.lasono.identity.application.usecase.LogoutUseCase;
import com.lasono.identity.application.usecase.RefreshSessionUseCase;
import com.lasono.identity.application.usecase.RegisterUserCommand;
import com.lasono.identity.application.usecase.RegisterUserResult;
import com.lasono.identity.application.usecase.RegisterUserUseCase;

@RestController
public class AuthController {

    private final RegisterUserUseCase registerUserUseCase;
    private final LoginUseCase loginUseCase;
    private final RefreshSessionUseCase refreshSessionUseCase;
    private final LogoutUseCase logoutUseCase;
    private final RefreshCookies refreshCookies;

    public AuthController(
        RegisterUserUseCase registerUserUseCase,
        LoginUseCase loginUseCase,
        RefreshSessionUseCase refreshSessionUseCase,
        LogoutUseCase logoutUseCase,
        RefreshCookies refreshCookies
    ) {
        this.registerUserUseCase = registerUserUseCase;
        this.loginUseCase = loginUseCase;
        this.refreshSessionUseCase = refreshSessionUseCase;
        this.logoutUseCase = logoutUseCase;
        this.refreshCookies = refreshCookies;
    }

    @PostMapping("/api/v1/auth/login")
    public ResponseEntity<LoginResult> login(@RequestBody LoginCommand command) {
        return respondWith(loginUseCase.execute(command));
    }

    // The cookie is read only here. Its path keeps the browser from sending it anywhere but the auth routes.
    @PostMapping("/api/v1/auth/refresh")
    public ResponseEntity<LoginResult> refresh(
        @CookieValue(name = RefreshCookies.NAME, required = false) String refreshToken
    ) {
        return respondWith(refreshSessionUseCase.execute(refreshToken));
    }

    @PostMapping("/api/v1/auth/logout")
    public ResponseEntity<Void> logout(@CookieValue(name = RefreshCookies.NAME, required = false) String refreshToken) {
        logoutUseCase.execute(refreshToken);

        return ResponseEntity.noContent()
            .header(HttpHeaders.SET_COOKIE, refreshCookies.clear().toString())
            .build();
    }

    @PostMapping("/api/v1/auth/register")
    public ResponseEntity<RegisterUserResult> register(@RequestBody RegisterUserCommand command) {
        RegisterUserResult result = registerUserUseCase.execute(command);

        return ResponseEntity.status(HttpStatus.CREATED).body(result);
    }

    // The access token goes in the body for the app to keep in memory; the refresh token goes in the cookie
    // only, where a script cannot read it.
    private ResponseEntity<LoginResult> respondWith(AuthSession session) {
        return ResponseEntity.ok()
            .header(HttpHeaders.SET_COOKIE, refreshCookies.issue(session.refreshToken()).toString())
            // RFC 6749: a response that carries a token must not be stored by browsers or proxies.
            .cacheControl(CacheControl.noStore())
            .body(session.access());
    }
}
