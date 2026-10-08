package com.lasono.identity.presentation;

import java.security.Principal;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.lasono.identity.application.usecase.CurrentUserResult;
import com.lasono.identity.application.usecase.GetCurrentUserUseCase;

@RestController
public class UserController {

    private final GetCurrentUserUseCase getCurrentUserUseCase;

    public UserController(GetCurrentUserUseCase getCurrentUserUseCase) {
        this.getCurrentUserUseCase = getCurrentUserUseCase;
    }

    @GetMapping("/api/v1/users/me")
    public CurrentUserResult me(Principal principal) {
        // Spring Security puts the "sub" of the verified token here, which is the id of the user.
        return getCurrentUserUseCase.execute(principal.getName());
    }
}
