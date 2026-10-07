package com.lasono.identity.presentation;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.lasono.identity.application.usecase.InvalidCredentialsException;
import com.lasono.identity.application.usecase.PasswordInvalidException;
import com.lasono.identity.domain.exception.DisplayNameInvalidException;
import com.lasono.identity.domain.exception.EmailAlreadyRegisteredException;
import com.lasono.identity.domain.exception.EmailInvalidException;

@RestControllerAdvice
public class IdentityExceptionHandler {

    @ExceptionHandler({EmailInvalidException.class, DisplayNameInvalidException.class, PasswordInvalidException.class})
    public ProblemDetail handleInvalidRegistration(RuntimeException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler(InvalidCredentialsException.class)
    public ProblemDetail handleInvalidCredentials(InvalidCredentialsException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, ex.getMessage());
    }

    @ExceptionHandler(EmailAlreadyRegisteredException.class)
    public ProblemDetail handleEmailAlreadyRegistered(EmailAlreadyRegisteredException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, ex.getMessage());
    }
}
