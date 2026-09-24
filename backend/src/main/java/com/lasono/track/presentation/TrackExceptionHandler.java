package com.lasono.track.presentation;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.lasono.track.application.usecase.InvalidRangeException;
import com.lasono.track.application.usecase.TrackNotFoundException;

@RestControllerAdvice 
public class TrackExceptionHandler {

    @ExceptionHandler(TrackNotFoundException.class)
    public ProblemDetail handleTrackNotFound(TrackNotFoundException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(InvalidRangeException.class)
    public ResponseEntity<ProblemDetail> handleInvalidRange(InvalidRangeException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatusCode.valueOf(416), 
            ex.getMessage()
        );

        return ResponseEntity
            .status(416)
            .header(HttpHeaders.CONTENT_RANGE, "bytes */" + ex.getFileSize())
            .body(problem);
    }
}
