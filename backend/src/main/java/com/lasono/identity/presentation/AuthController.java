package com.lasono.identity.presentation;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.lasono.identity.application.usecase.RegisterUserCommand;
import com.lasono.identity.application.usecase.RegisterUserResult;
import com.lasono.identity.application.usecase.RegisterUserUseCase;

@RestController
public class AuthController {

    private final RegisterUserUseCase registerUserUseCase;

    public AuthController(RegisterUserUseCase registerUserUseCase) {
        this.registerUserUseCase = registerUserUseCase;
    }

    @PostMapping("/api/v1/auth/register")
    public ResponseEntity<RegisterUserResult> register(@RequestBody RegisterUserCommand command) {
        RegisterUserResult result = registerUserUseCase.execute(command);

        return ResponseEntity.status(HttpStatus.CREATED).body(result);
    }
}
