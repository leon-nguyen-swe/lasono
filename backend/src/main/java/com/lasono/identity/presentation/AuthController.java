package com.lasono.identity.presentation;

import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.lasono.identity.application.usecase.LoginCommand;
import com.lasono.identity.application.usecase.LoginResult;
import com.lasono.identity.application.usecase.LoginUseCase;
import com.lasono.identity.application.usecase.RegisterUserCommand;
import com.lasono.identity.application.usecase.RegisterUserResult;
import com.lasono.identity.application.usecase.RegisterUserUseCase;

@RestController
public class AuthController {

    private final RegisterUserUseCase registerUserUseCase;
    private final LoginUseCase loginUseCase;

    public AuthController(RegisterUserUseCase registerUserUseCase, LoginUseCase loginUseCase) {
        this.registerUserUseCase = registerUserUseCase;
        this.loginUseCase = loginUseCase;
    }

    @PostMapping("/api/v1/auth/login")
    public ResponseEntity<LoginResult> login(@RequestBody LoginCommand command) {
        LoginResult result = loginUseCase.execute(command);

        // RFC 6749: a response that carries a token must not be stored by browsers or proxies.
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(result);
    }

    @PostMapping("/api/v1/auth/register")
    public ResponseEntity<RegisterUserResult> register(@RequestBody RegisterUserCommand command) {
        RegisterUserResult result = registerUserUseCase.execute(command);

        return ResponseEntity.status(HttpStatus.CREATED).body(result);
    }
}
