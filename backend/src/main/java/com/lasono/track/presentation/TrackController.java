package com.lasono.track.presentation;

import java.io.IOException;
import java.io.InputStream;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;
import org.springframework.http.HttpHeaders;

import com.lasono.track.application.usecase.GetTrackResult;
import com.lasono.track.application.usecase.GetTrackUseCase;
import com.lasono.track.application.usecase.StreamTrackResult;
import com.lasono.track.application.usecase.StreamTrackUseCase;
import com.lasono.track.application.usecase.UploadTrackCommand;
import com.lasono.track.application.usecase.UploadTrackResult;
import com.lasono.track.application.usecase.UploadTrackUseCase;

@RestController 
public class TrackController {

    private final UploadTrackUseCase uploadTrackUseCase;
    private final GetTrackUseCase getTrackUseCase;
    private final StreamTrackUseCase streamTrackUsecase;

    public TrackController(
        UploadTrackUseCase uploadTrackUseCase,
        GetTrackUseCase getTrackUseCase,
        StreamTrackUseCase streamTrackUsecase
    ) {
        this.uploadTrackUseCase = uploadTrackUseCase;
        this.getTrackUseCase = getTrackUseCase;
        this.streamTrackUsecase = streamTrackUsecase;
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

    @GetMapping("/api/v1/tracks/{id}")
    public GetTrackResult getTrack(@PathVariable("id") UUID id) {
        return getTrackUseCase.execute(id);
    }

    @GetMapping("/api/v1/tracks/{id}/stream")
    public ResponseEntity<StreamingResponseBody> streamTrack(
        @PathVariable("id") UUID id,
        @RequestHeader(value = HttpHeaders.RANGE, required = false) String rangeHeader
    ) {
        StreamTrackResult result = streamTrackUsecase.execute(id, rangeHeader);

        long contentLength = result.rangeEnd() - result.rangeStart() + 1;

        StreamingResponseBody body = outputStream -> {
            try (InputStream in = result.stream()) {
                in.transferTo(outputStream);
            }
        };

        ResponseEntity.BodyBuilder response = ResponseEntity
            .status(result.partial() ? HttpStatus.PARTIAL_CONTENT : HttpStatus.OK)
            .header(HttpHeaders.ACCEPT_RANGES, "bytes")
            .contentType(MediaType.parseMediaType(result.mimeType()))
            .contentLength(contentLength);

        if (result.partial()) {
            response.header(
                HttpHeaders.CONTENT_RANGE, 
                "bytes " + result.rangeStart() + "-" + result.rangeEnd() + "/" + result.fileSize()
            );
        }

        return response.body(body);
    }
}
