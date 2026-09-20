package com.lasono.track.presentation;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.lasono.track.application.usecase.TrackNotFoundException;

@RestControllerAdvice 
public class TrackExceptionHandler {

    @ExceptionHandler(TrackNotFoundException.class)
    public ProblemDetail handleTrackNotFound(TrackNotFoundException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
    }
}
