package com.lasono.identity.presentation;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.lasono.identity.application.usecase.CurrentUserResult;
import com.lasono.identity.application.usecase.GetCurrentUserUseCase;
import com.lasono.identity.application.usecase.GetProfileUseCase;
import com.lasono.identity.application.usecase.ProfileNotFoundException;
import com.lasono.identity.application.usecase.ProfileResult;
import com.lasono.identity.application.usecase.UpdateProfileUseCase;
import com.lasono.identity.domain.exception.DisplayNameInvalidException;
import com.lasono.identity.application.usecase.UserNotFoundException;

@ExtendWith(MockitoExtension.class)
class UserControllerTest {

    private static final String USER_ID = "5b0c2d4e-1111-4222-8333-944455566677";

    @Mock
    private GetCurrentUserUseCase getCurrentUserUseCase;

    @Mock
    private GetProfileUseCase getProfileUseCase;

    @Mock
    private UpdateProfileUseCase updateProfileUseCase;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(new UserController(getCurrentUserUseCase, getProfileUseCase, updateProfileUseCase))
            .setControllerAdvice(new IdentityExceptionHandler())
            .build();
    }

    // Spring Security puts the "sub" of the token into the request's principal; the test plays that part.
    @Test
    void me_returnsTheUserOfThePrincipalAndNoPasswordOrHash() throws Exception {
        when(getCurrentUserUseCase.execute(USER_ID))
            .thenReturn(new CurrentUserResult(USER_ID, "alice@example.com", "Alice"));

        mockMvc.perform(get("/api/v1/users/me").principal(() -> USER_ID))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.userId").value(USER_ID))
            .andExpect(jsonPath("$.email").value("alice@example.com"))
            .andExpect(jsonPath("$.displayName").value("Alice"))
            .andExpect(jsonPath("$.password").doesNotExist())
            .andExpect(jsonPath("$.passwordHash").doesNotExist());
    }

    @Test
    void me_asksTheUseCaseForTheNameOfThePrincipal() throws Exception {
        when(getCurrentUserUseCase.execute(USER_ID))
            .thenReturn(new CurrentUserResult(USER_ID, "alice@example.com", "Alice"));

        mockMvc.perform(get("/api/v1/users/me").principal(() -> USER_ID));

        verify(getCurrentUserUseCase).execute(USER_ID);
    }

    @Test
    void me_returns401WhenTheAccountOfTheTokenIsGone() throws Exception {
        when(getCurrentUserUseCase.execute(USER_ID)).thenThrow(new UserNotFoundException());

        mockMvc.perform(get("/api/v1/users/me").principal(() -> USER_ID))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.detail").value("The account of this token no longer exists"));
    }

    // --- the public profile and the change of the display name ---

    @Test
    void profile_returnsTheIdAndTheNameAndNothingPrivate() throws Exception {
        when(getProfileUseCase.execute(UUID.fromString(USER_ID))).thenReturn(new ProfileResult(USER_ID, "Alice"));

        mockMvc.perform(get("/api/v1/users/{id}", USER_ID))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.userId").value(USER_ID))
            .andExpect(jsonPath("$.displayName").value("Alice"))
            .andExpect(jsonPath("$.email").doesNotExist())
            .andExpect(jsonPath("$.passwordHash").doesNotExist());
    }

    @Test
    void profile_returns404WhenNobodyHasThatId() throws Exception {
        UUID id = UUID.randomUUID();
        when(getProfileUseCase.execute(id)).thenThrow(new ProfileNotFoundException(id));

        mockMvc.perform(get("/api/v1/users/{id}", id))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.detail").value("No user with id " + id));
    }

    @Test
    void profile_returns400ForAnIdThatIsNotAUuid() throws Exception {
        mockMvc.perform(get("/api/v1/users/{id}", "not-a-uuid"))
            .andExpect(status().isBadRequest());

        verifyNoInteractions(getProfileUseCase);
    }

    // "me" must keep meaning the caller, not a user called "me".
    @Test
    void me_isNotTakenForAProfileId() throws Exception {
        when(getCurrentUserUseCase.execute(USER_ID))
            .thenReturn(new CurrentUserResult(USER_ID, "alice@example.com", "Alice"));

        mockMvc.perform(get("/api/v1/users/me").principal(() -> USER_ID))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.email").value("alice@example.com"));

        verifyNoInteractions(getProfileUseCase);
    }

    @Test
    void updateMe_changesTheNameOfThePrincipalAndReturnsTheAccount() throws Exception {
        when(updateProfileUseCase.execute(UUID.fromString(USER_ID), "Alice B."))
            .thenReturn(new CurrentUserResult(USER_ID, "alice@example.com", "Alice B."));

        mockMvc.perform(patch("/api/v1/users/me")
                .principal(() -> USER_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"displayName\":\"Alice B.\"}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.displayName").value("Alice B."))
            .andExpect(jsonPath("$.email").value("alice@example.com"));
    }

    @Test
    void updateMe_returns400ForAnInvalidName() throws Exception {
        when(updateProfileUseCase.execute(UUID.fromString(USER_ID), "  "))
            .thenThrow(new DisplayNameInvalidException("Display name must not be blank"));

        mockMvc.perform(patch("/api/v1/users/me")
                .principal(() -> USER_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"displayName\":\"  \"}"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.detail").value("Display name must not be blank"));
    }

    @Test
    void updateMe_returns400ForMalformedJsonAndSkipsTheUseCase() throws Exception {
        mockMvc.perform(patch("/api/v1/users/me")
                .principal(() -> USER_ID).contentType(MediaType.APPLICATION_JSON).content("{not json"))
            .andExpect(status().isBadRequest());

        verifyNoInteractions(updateProfileUseCase);
    }

    @Test
    void updateMe_returns401WhenTheAccountOfTheTokenIsGone() throws Exception {
        when(updateProfileUseCase.execute(UUID.fromString(USER_ID), "Alice B.")).thenThrow(new UserNotFoundException());

        mockMvc.perform(patch("/api/v1/users/me")
                .principal(() -> USER_ID)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"displayName\":\"Alice B.\"}"))
            .andExpect(status().isUnauthorized());
    }
}
