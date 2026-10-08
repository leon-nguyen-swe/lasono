package com.lasono.track.presentation;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.lasono.track.application.usecase.InvalidPageRequestException;
import com.lasono.track.application.usecase.InvalidRangeException;
import com.lasono.track.application.usecase.TrackNotFoundException;
import com.lasono.track.application.usecase.TrackNotReadyException;
import com.lasono.track.domain.audio.exception.AudioFormatInvalidException;
import com.lasono.track.domain.audio.exception.OriginalAudioInvalidException;
import com.lasono.track.domain.exception.TrackTitleInvalidException;
import com.lasono.track.domain.exception.TrackVisibilityInvalidException;

@RestControllerAdvice
public class TrackExceptionHandler {

    @ExceptionHandler(AudioFormatInvalidException.class)
    public ProblemDetail handleUnsupportedAudioFormat(AudioFormatInvalidException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNSUPPORTED_MEDIA_TYPE, ex.getMessage());
    }

    @ExceptionHandler({TrackTitleInvalidException.class, OriginalAudioInvalidException.class})
    public ProblemDetail handleInvalidUpload(RuntimeException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler(InvalidPageRequestException.class)
    public ProblemDetail handleInvalidPageRequest(InvalidPageRequestException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler(TrackVisibilityInvalidException.class)
    public ProblemDetail handleInvalidVisibility(TrackVisibilityInvalidException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler(TrackNotFoundException.class)
    public ProblemDetail handleTrackNotFound(TrackNotFoundException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
    }

    @ExceptionHandler(TrackNotReadyException.class)
    public ProblemDetail handleTrackNotReady(TrackNotReadyException ex) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, ex.getMessage());
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
