package com.lasono.identity.presentation;

import java.security.Principal;
import java.util.UUID;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.lasono.identity.application.usecase.CurrentUserResult;
import com.lasono.identity.application.usecase.GetCurrentUserUseCase;
import com.lasono.identity.application.usecase.GetProfileUseCase;
import com.lasono.identity.application.usecase.ProfileResult;
import com.lasono.identity.application.usecase.UpdateProfileUseCase;

@RestController
public class UserController {

    private final GetCurrentUserUseCase getCurrentUserUseCase;
    private final GetProfileUseCase getProfileUseCase;
    private final UpdateProfileUseCase updateProfileUseCase;

    public UserController(
        GetCurrentUserUseCase getCurrentUserUseCase,
        GetProfileUseCase getProfileUseCase,
        UpdateProfileUseCase updateProfileUseCase
    ) {
        this.getCurrentUserUseCase = getCurrentUserUseCase;
        this.getProfileUseCase = getProfileUseCase;
        this.updateProfileUseCase = updateProfileUseCase;
    }

    @GetMapping("/api/v1/users/me")
    public CurrentUserResult me(Principal principal) {
        // Spring Security puts the "sub" of the verified token here, which is the id of the user.
        return getCurrentUserUseCase.execute(principal.getName());
    }

    // Only the owner changes it, and the owner is the user in the token: there is no id in the path to forge.
    @PatchMapping("/api/v1/users/me")
    public CurrentUserResult updateMe(@RequestBody UpdateProfileRequest request, Principal principal) {
        return updateProfileUseCase.execute(UUID.fromString(principal.getName()), request.displayName());
    }

    // What anyone may see of a user: the id and the display name, never the email.
    @GetMapping("/api/v1/users/{id}")
    public ProfileResult profile(@PathVariable("id") UUID id) {
        return getProfileUseCase.execute(id);
    }
}
