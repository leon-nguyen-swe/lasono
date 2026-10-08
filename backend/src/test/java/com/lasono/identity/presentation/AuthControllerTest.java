package com.lasono.identity.presentation;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Duration;

import jakarta.servlet.http.Cookie;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.lasono.identity.application.usecase.AuthSession;
import com.lasono.identity.application.usecase.InvalidCredentialsException;
import com.lasono.identity.application.usecase.InvalidRefreshTokenException;
import com.lasono.identity.application.usecase.LoginCommand;
import com.lasono.identity.application.usecase.LoginResult;
import com.lasono.identity.application.usecase.LoginUseCase;
import com.lasono.identity.application.usecase.LogoutUseCase;
import com.lasono.identity.application.usecase.PasswordInvalidException;
import com.lasono.identity.application.usecase.RefreshSessionUseCase;
import com.lasono.identity.application.usecase.RegisterUserCommand;
import com.lasono.identity.application.usecase.RegisterUserResult;
import com.lasono.identity.application.usecase.RegisterUserUseCase;
import com.lasono.identity.domain.Email;
import com.lasono.identity.domain.exception.DisplayNameInvalidException;
import com.lasono.identity.domain.exception.EmailAlreadyRegisteredException;
import com.lasono.identity.domain.exception.EmailInvalidException;

@ExtendWith(MockitoExtension.class)
class AuthControllerTest {

    private static final String REGISTER_BODY =
        "{\"email\":\"alice@example.com\",\"displayName\":\"Alice\",\"password\":\"correct horse\"}";

    private static final String LOGIN_BODY = "{\"email\":\"alice@example.com\",\"password\":\"correct horse\"}";

    @Mock
    private RegisterUserUseCase registerUserUseCase;

    @Mock
    private LoginUseCase loginUseCase;

    @Mock
    private RefreshSessionUseCase refreshSessionUseCase;

    @Mock
    private LogoutUseCase logoutUseCase;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        AuthController controller = new AuthController(
            registerUserUseCase,
            loginUseCase,
            refreshSessionUseCase,
            logoutUseCase,
            new RefreshCookies(Duration.ofDays(30), true)
        );
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
            .setControllerAdvice(new IdentityExceptionHandler())
            .build();
    }

    @Test
    void register_returns201WithTheNewUserAndNeverThePasswordOrItsHash() throws Exception {
        when(registerUserUseCase.execute(any()))
            .thenReturn(new RegisterUserResult("5b0c2d4e-1111-4222-8333-944455566677", "alice@example.com", "Alice"));

        register(REGISTER_BODY)
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.userId").value("5b0c2d4e-1111-4222-8333-944455566677"))
            .andExpect(jsonPath("$.email").value("alice@example.com"))
            .andExpect(jsonPath("$.displayName").value("Alice"))
            .andExpect(jsonPath("$.password").doesNotExist())
            .andExpect(jsonPath("$.passwordHash").doesNotExist());
    }

    @Test
    void register_passesTheRequestFieldsToTheUseCase() throws Exception {
        when(registerUserUseCase.execute(any()))
            .thenReturn(new RegisterUserResult("5b0c2d4e-1111-4222-8333-944455566677", "alice@example.com", "Alice"));

        register(REGISTER_BODY);

        ArgumentCaptor<RegisterUserCommand> captor = ArgumentCaptor.forClass(RegisterUserCommand.class);
        verify(registerUserUseCase).execute(captor.capture());
        assertEquals("alice@example.com", captor.getValue().email());
        assertEquals("Alice", captor.getValue().displayName());
        assertEquals("correct horse", captor.getValue().password());
    }

    @Test
    void register_returns409WhenTheEmailIsTaken() throws Exception {
        when(registerUserUseCase.execute(any()))
            .thenThrow(new EmailAlreadyRegisteredException(new Email("alice@example.com")));

        register(REGISTER_BODY)
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.detail").value("Email already registered: alice@example.com"));
    }

    @Test
    void register_returns400ForAnInvalidEmail() throws Exception {
        when(registerUserUseCase.execute(any())).thenThrow(new EmailInvalidException("Email is not valid"));

        register(REGISTER_BODY)
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.detail").value("Email is not valid"));
    }

    @Test
    void register_returns400ForAnInvalidDisplayName() throws Exception {
        when(registerUserUseCase.execute(any()))
            .thenThrow(new DisplayNameInvalidException("Display name must not be blank"));

        register(REGISTER_BODY)
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.detail").value("Display name must not be blank"));
    }

    @Test
    void register_returns400ForAnInvalidPassword() throws Exception {
        when(registerUserUseCase.execute(any()))
            .thenThrow(new PasswordInvalidException("Password must be at least 8 characters"));

        register(REGISTER_BODY)
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.detail").value("Password must be at least 8 characters"));
    }

    @Test
    void register_returns400AndSkipsTheUseCaseForMalformedJson() throws Exception {
        register("{not json")
            .andExpect(status().isBadRequest());

        verifyNoInteractions(registerUserUseCase);
    }

    // Missing fields become null and the domain rejects them, so the controller needs no checks of its own.
    @Test
    void register_passesMissingFieldsAsNullToTheUseCase() throws Exception {
        when(registerUserUseCase.execute(any())).thenThrow(new EmailInvalidException("Email must not be null"));

        register("{}").andExpect(status().isBadRequest());

        ArgumentCaptor<RegisterUserCommand> captor = ArgumentCaptor.forClass(RegisterUserCommand.class);
        verify(registerUserUseCase).execute(captor.capture());
        assertNull(captor.getValue().email());
        assertNull(captor.getValue().displayName());
        assertNull(captor.getValue().password());
    }

    private static AuthSession aSession() {
        return new AuthSession(new LoginResult("a.jwt.token", "Bearer", 900), "a-refresh-token");
    }

    @Test
    void login_returns200WithTheAccessToken() throws Exception {
        when(loginUseCase.execute(any())).thenReturn(aSession());

        login(LOGIN_BODY)
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.accessToken").value("a.jwt.token"))
            .andExpect(jsonPath("$.tokenType").value("Bearer"))
            .andExpect(jsonPath("$.expiresIn").value(900));
    }

    // RFC 6749: a response that carries a token must not be stored by browsers or proxies.
    @Test
    void login_tellsEveryCacheNotToKeepTheToken() throws Exception {
        when(loginUseCase.execute(any())).thenReturn(aSession());

        login(LOGIN_BODY)
            .andExpect(header().string("Cache-Control", "no-store"));
    }

    @Test
    void login_passesTheRequestFieldsToTheUseCase() throws Exception {
        when(loginUseCase.execute(any())).thenReturn(aSession());

        login(LOGIN_BODY);

        ArgumentCaptor<LoginCommand> captor = ArgumentCaptor.forClass(LoginCommand.class);
        verify(loginUseCase).execute(captor.capture());
        assertEquals("alice@example.com", captor.getValue().email());
        assertEquals("correct horse", captor.getValue().password());
    }

    @Test
    void login_returns401WithOneNeutralMessageWhenTheCredentialsAreWrong() throws Exception {
        when(loginUseCase.execute(any())).thenThrow(new InvalidCredentialsException());

        login(LOGIN_BODY)
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("Invalid email or password"));
    }

    @Test
    void login_returns400AndSkipsTheUseCaseForMalformedJson() throws Exception {
        login("{not json")
            .andExpect(status().isBadRequest());

        verifyNoInteractions(loginUseCase);
    }

    // Missing fields become null; the use case treats them as wrong credentials.
    @Test
    void login_passesMissingFieldsAsNullToTheUseCase() throws Exception {
        when(loginUseCase.execute(any())).thenThrow(new InvalidCredentialsException());

        login("{}").andExpect(status().isUnauthorized());

        ArgumentCaptor<LoginCommand> captor = ArgumentCaptor.forClass(LoginCommand.class);
        verify(loginUseCase).execute(captor.capture());
        assertNull(captor.getValue().email());
        assertNull(captor.getValue().password());
    }

    // The refresh token must reach the browser only as an HttpOnly cookie, never in a body a script can read.
    @Test
    void login_setsTheRefreshTokenInACookieAndNotInTheBody() throws Exception {
        when(loginUseCase.execute(any())).thenReturn(aSession());

        login(LOGIN_BODY)
            .andExpect(header().string("Set-Cookie", containsString("lasono_refresh=a-refresh-token")))
            .andExpect(header().string("Set-Cookie", containsString("HttpOnly")))
            .andExpect(header().string("Set-Cookie", containsString("SameSite=Strict")))
            .andExpect(jsonPath("$.refreshToken").doesNotExist())
            .andExpect(content().string(not(containsString("a-refresh-token"))));
    }

    @Test
    void login_failureSetsNoCookie() throws Exception {
        when(loginUseCase.execute(any())).thenThrow(new InvalidCredentialsException());

        login(LOGIN_BODY).andExpect(header().doesNotExist("Set-Cookie"));
    }

    @Test
    void refresh_exchangesTheCookieForNewTokens() throws Exception {
        when(refreshSessionUseCase.execute("old-token"))
            .thenReturn(new AuthSession(new LoginResult("new.jwt.token", "Bearer", 900), "new-refresh-token"));

        refresh("old-token")
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.accessToken").value("new.jwt.token"))
            .andExpect(jsonPath("$.tokenType").value("Bearer"))
            .andExpect(jsonPath("$.expiresIn").value(900))
            .andExpect(jsonPath("$.refreshToken").doesNotExist())
            .andExpect(header().string("Set-Cookie", containsString("lasono_refresh=new-refresh-token")))
            .andExpect(header().string("Cache-Control", "no-store"));
    }

    @Test
    void refresh_returns401WithoutACookieAndPassesNullToTheUseCase() throws Exception {
        when(refreshSessionUseCase.execute(null)).thenThrow(new InvalidRefreshTokenException());

        mockMvc.perform(post("/api/v1/auth/refresh"))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("Invalid refresh token"));
    }

    @Test
    void refresh_returns401WithOneNeutralMessageAndSetsNoCookieForATokenThatCannotBeUsed() throws Exception {
        when(refreshSessionUseCase.execute("stale")).thenThrow(new InvalidRefreshTokenException());

        refresh("stale")
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("Invalid refresh token"))
            .andExpect(header().doesNotExist("Set-Cookie"));
    }

    @Test
    void logout_endsTheSessionAndAsksTheBrowserToDeleteTheCookie() throws Exception {
        mockMvc.perform(post("/api/v1/auth/logout").cookie(new Cookie("lasono_refresh", "the-token")))
            .andExpect(status().isNoContent())
            .andExpect(header().string("Set-Cookie", containsString("lasono_refresh=;")))
            .andExpect(header().string("Set-Cookie", containsString("Max-Age=0")))
            .andExpect(header().string("Set-Cookie", containsString("Path=/api/v1/auth")));

        verify(logoutUseCase).execute("the-token");
    }

    // A logout the browser sends twice, or after the cookie expired, must still be a success.
    @Test
    void logout_withoutACookieStillAnswers204AndClearsTheCookie() throws Exception {
        mockMvc.perform(post("/api/v1/auth/logout"))
            .andExpect(status().isNoContent())
            .andExpect(header().string("Set-Cookie", containsString("Max-Age=0")));

        verify(logoutUseCase).execute(null);
    }

    private ResultActions refresh(String refreshToken) throws Exception {
        return mockMvc.perform(post("/api/v1/auth/refresh").cookie(new Cookie("lasono_refresh", refreshToken)));
    }

    private ResultActions login(String body) throws Exception {
        return mockMvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(body));
    }

    private ResultActions register(String body) throws Exception {
        return mockMvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON).content(body));
    }
}
