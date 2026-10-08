package com.lasono.track.presentation;

import java.io.IOException;
import java.io.InputStream;
import java.security.Principal;
import java.util.UUID;

import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;
import org.springframework.http.HttpHeaders;

import com.lasono.track.application.usecase.DeleteTrackUseCase;
import com.lasono.track.application.usecase.GetStreamUrlUseCase;
import com.lasono.track.application.usecase.GetTrackResult;
import com.lasono.track.application.usecase.GetTrackUseCase;
import com.lasono.track.application.usecase.ListTracksResult;
import com.lasono.track.application.usecase.ListTracksUseCase;
import com.lasono.track.application.usecase.StreamSignature;
import com.lasono.track.application.usecase.StreamTrackResult;
import com.lasono.track.application.usecase.StreamTrackUseCase;
import com.lasono.track.application.usecase.StreamUrlResult;
import com.lasono.track.application.usecase.UpdateTrackCommand;
import com.lasono.track.application.usecase.UpdateTrackUseCase;
import com.lasono.track.application.usecase.UploadTrackCommand;
import com.lasono.track.application.usecase.UploadTrackResult;
import com.lasono.track.application.usecase.UploadTrackUseCase;

@RestController 
public class TrackController {

    private final UploadTrackUseCase uploadTrackUseCase;
    private final GetTrackUseCase getTrackUseCase;
    private final StreamTrackUseCase streamTrackUsecase;
    private final ListTracksUseCase listTracksUseCase;
    private final GetStreamUrlUseCase getStreamUrlUseCase;
    private final UpdateTrackUseCase updateTrackUseCase;
    private final DeleteTrackUseCase deleteTrackUseCase;

    public TrackController(
        UploadTrackUseCase uploadTrackUseCase,
        GetTrackUseCase getTrackUseCase,
        StreamTrackUseCase streamTrackUsecase,
        ListTracksUseCase listTracksUseCase,
        GetStreamUrlUseCase getStreamUrlUseCase,
        UpdateTrackUseCase updateTrackUseCase,
        DeleteTrackUseCase deleteTrackUseCase
    ) {
        this.uploadTrackUseCase = uploadTrackUseCase;
        this.getTrackUseCase = getTrackUseCase;
        this.streamTrackUsecase = streamTrackUsecase;
        this.listTracksUseCase = listTracksUseCase;
        this.getStreamUrlUseCase = getStreamUrlUseCase;
        this.updateTrackUseCase = updateTrackUseCase;
        this.deleteTrackUseCase = deleteTrackUseCase;
    }

    @PostMapping("/api/v1/tracks")
    public ResponseEntity<UploadTrackResult> uploadTrack(
        @RequestParam("title") String title,
        @RequestParam(value = "description", required = false, defaultValue = "") String description,
        @RequestParam("file") MultipartFile file,
        @RequestParam(value = "visibility", required = false) String visibility,
        Principal principal
    ) throws IOException {
        // The name of a logged-in caller is the "sub" of the token: the id of the user.
        UploadTrackCommand command = new UploadTrackCommand(
            UUID.fromString(principal.getName()),
            title,
            description,
            file.getInputStream(),
            file.getSize(),
            file.getContentType(),
            visibility
        );

        UploadTrackResult result = uploadTrackUseCase.execute(command);

        return ResponseEntity.status(HttpStatus.CREATED).body(result);
    }

    // The caller is the user in the token, never a field of the body. Who may change what is decided in the use case.
    @PatchMapping("/api/v1/tracks/{id}")
    public GetTrackResult updateTrack(
        @PathVariable("id") UUID id,
        @RequestBody UpdateTrackRequest request,
        Principal principal
    ) {
        return updateTrackUseCase.execute(new UpdateTrackCommand(
            id,
            UUID.fromString(principal.getName()),
            request.title(),
            request.description(),
            request.visibility()
        ));
    }

    @DeleteMapping("/api/v1/tracks/{id}")
    public ResponseEntity<Void> deleteTrack(@PathVariable("id") UUID id, Principal principal) {
        deleteTrackUseCase.execute(id, UUID.fromString(principal.getName()));

        return ResponseEntity.noContent().build();
    }

    @GetMapping("/api/v1/tracks")
    public ListTracksResult listTracks(
        @RequestParam(value = "cursor", required = false) String cursor,
        @RequestParam(value = "limit", required = false) Integer limit,
        Principal principal
    ) {
        return listTracksUseCase.execute(cursor, limit, viewerOf(principal));
    }

    // A profile page lists the tracks of one user. The track module only knows the owner's id, so the name and
    // the rest of the profile come from the identity module, and the app puts the two together.
    @GetMapping("/api/v1/users/{id}/tracks")
    public ListTracksResult listUserTracks(
        @PathVariable("id") UUID ownerId,
        @RequestParam(value = "cursor", required = false) String cursor,
        @RequestParam(value = "limit", required = false) Integer limit,
        Principal principal
    ) {
        return listTracksUseCase.executeForOwner(ownerId, cursor, limit, viewerOf(principal));
    }

    @GetMapping("/api/v1/tracks/{id}")
    public GetTrackResult getTrack(@PathVariable("id") UUID id, Principal principal) {
        return getTrackUseCase.execute(id, viewerOf(principal));
    }

    // An address the browser's audio player can use: it cannot send a login header, so the permission is signed
    // into the address. The address is a key, so nothing along the way may keep a copy of this answer.
    @GetMapping("/api/v1/tracks/{id}/stream-url")
    public ResponseEntity<StreamUrlResult> streamUrl(@PathVariable("id") UUID id, Principal principal) {
        StreamUrlResult result = getStreamUrlUseCase.execute(id, viewerOf(principal));

        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(result);
    }

    @GetMapping("/api/v1/tracks/{id}/stream")
    public ResponseEntity<StreamingResponseBody> streamTrack(
        @PathVariable("id") UUID id,
        @RequestHeader(value = HttpHeaders.RANGE, required = false) String rangeHeader,
        @RequestParam(value = "expires", required = false) Long expires,
        @RequestParam(value = "signature", required = false) String signature,
        Principal principal
    ) {
        // Half a signature proves nothing, so it counts as none.
        StreamSignature streamSignature =
            expires != null && signature != null ? new StreamSignature(expires, signature) : null;
        StreamTrackResult result =
            streamTrackUsecase.execute(id, rangeHeader, viewerOf(principal), streamSignature);

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

    // Reading is open to everyone, so there may be nobody logged in: then there is no principal.
    private static UUID viewerOf(Principal principal) {
        return principal == null ? null : UUID.fromString(principal.getName());
    }
}
