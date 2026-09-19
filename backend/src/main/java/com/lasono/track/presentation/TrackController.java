package com.lasono.track.presentation;

import java.io.IOException;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.lasono.track.application.usecase.UploadTrackCommand;
import com.lasono.track.application.usecase.UploadTrackResult;
import com.lasono.track.application.usecase.UploadTrackUseCase;

@RestController 
public class TrackController {

    private final UploadTrackUseCase uploadTrackUseCase;

    public TrackController(UploadTrackUseCase uploadTrackUseCase) {
        this.uploadTrackUseCase = uploadTrackUseCase;
    }

    @PostMapping("/api/v1/tracks")
    public ResponseEntity<UploadTrackResult> uploadTrack(
        @RequestParam("title") String title,
        @RequestParam(value = "description", required = false, defaultValue = "") String description,
        @RequestParam("file") MultipartFile file
    ) throws IOException {
        UploadTrackCommand command = new UploadTrackCommand(
            title,
            description,
            file.getInputStream(),
            file.getOriginalFilename(),
            file.getSize(),
            file.getContentType()
        );

        UploadTrackResult result = uploadTrackUseCase.execute(command);

        return ResponseEntity.status(HttpStatus.CREATED).body(result);
    }
}
