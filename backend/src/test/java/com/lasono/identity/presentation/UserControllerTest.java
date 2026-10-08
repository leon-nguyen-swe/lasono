package com.lasono.identity.presentation;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.lasono.identity.application.usecase.CurrentUserResult;
import com.lasono.identity.application.usecase.GetCurrentUserUseCase;
import com.lasono.identity.application.usecase.UserNotFoundException;

@ExtendWith(MockitoExtension.class)
class UserControllerTest {

    private static final String USER_ID = "5b0c2d4e-1111-4222-8333-944455566677";

    @Mock
    private GetCurrentUserUseCase getCurrentUserUseCase;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(new UserController(getCurrentUserUseCase))
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
}
