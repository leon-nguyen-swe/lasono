package com.lasono.track.presentation;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.security.Principal;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.lasono.track.application.usecase.GetTrackUseCase;
import com.lasono.track.application.usecase.InvalidPageRequestException;
import com.lasono.track.application.usecase.ListTracksUseCase;
import com.lasono.track.application.usecase.StreamTrackUseCase;
import com.lasono.track.application.usecase.TrackNotReadyException;
import com.lasono.track.application.usecase.UploadTrackUseCase;
import com.lasono.track.domain.audio.exception.AudioFormatInvalidException;
import com.lasono.track.domain.audio.exception.OriginalAudioInvalidException;
import com.lasono.track.domain.exception.TrackTitleInvalidException;
import com.lasono.track.domain.exception.TrackVisibilityInvalidException;
import com.lasono.track.application.usecase.GetStreamUrlUseCase;

@ExtendWith(MockitoExtension.class)
class TrackExceptionHandlerTest {

    @Mock
    private UploadTrackUseCase uploadTrackUseCase;

    @Mock
    private GetTrackUseCase getTrackUseCase;

    @Mock
    private StreamTrackUseCase streamTrackUseCase;

    @Mock
    private ListTracksUseCase listTracksUseCase;

    @Mock
    private GetStreamUrlUseCase getStreamUrlUseCase;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        TrackController controller =
            new TrackController(
                uploadTrackUseCase, getTrackUseCase, streamTrackUseCase, listTracksUseCase, getStreamUrlUseCase);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
            .setControllerAdvice(new TrackExceptionHandler())
            .build();
    }

    private MockMultipartFile audioFile() {
        return new MockMultipartFile("file", "song.mp3", "application/octet-stream", "x".getBytes());
    }

    @Test
    void givenUnsupportedAudioFormat_uploadTrack_returns415() throws Exception {
        when(uploadTrackUseCase.execute(any()))
            .thenThrow(new AudioFormatInvalidException("Unsupported MIME type: application/octet-stream"));

        mockMvc.perform(multipart("/api/v1/tracks").file(audioFile()).param("title", "My Song").principal(aCaller()))
            .andExpect(status().isUnsupportedMediaType())
            .andExpect(jsonPath("$.status").value(415))
            .andExpect(jsonPath("$.detail").value("Unsupported MIME type: application/octet-stream"));
    }

    @Test
    void givenInvalidTitle_uploadTrack_returns400() throws Exception {
        when(uploadTrackUseCase.execute(any()))
            .thenThrow(new TrackTitleInvalidException("Track title must not be blank"));

        mockMvc.perform(multipart("/api/v1/tracks").file(audioFile()).param("title", "   ").principal(aCaller()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.status").value(400))
            .andExpect(jsonPath("$.detail").value("Track title must not be blank"));
    }

    @Test
    void givenInvalidVisibility_uploadTrack_returns400() throws Exception {
        when(uploadTrackUseCase.execute(any()))
            .thenThrow(new TrackVisibilityInvalidException("Visibility must be PUBLIC or PRIVATE"));

        mockMvc.perform(multipart("/api/v1/tracks").file(audioFile()).param("title", "My Song")
                .param("visibility", "secret").principal(aCaller()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.detail").value("Visibility must be PUBLIC or PRIVATE"));
    }

    @Test
    void givenInvalidPageRequest_listTracks_returns400() throws Exception {
        when(listTracksUseCase.execute("garbage", null, null))
            .thenThrow(new InvalidPageRequestException("Invalid cursor"));

        mockMvc.perform(get("/api/v1/tracks").param("cursor", "garbage"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.status").value(400))
            .andExpect(jsonPath("$.detail").value("Invalid cursor"));
    }

    @Test
    void givenTrackThatIsNotReady_streamTrack_returns409() throws Exception {
        UUID id = UUID.randomUUID();
        when(streamTrackUseCase.execute(id, null, null, null)).thenThrow(new TrackNotReadyException(id, "PROCESSING"));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id))
            .andExpect(status().isConflict())
            .andExpect(jsonPath("$.status").value(409))
            .andExpect(jsonPath("$.detail").value("Track " + id + " is not ready to be played, its status is PROCESSING"));
    }

    @Test
    void givenEmptyAudioFile_uploadTrack_returns400() throws Exception {
        when(uploadTrackUseCase.execute(any()))
            .thenThrow(new OriginalAudioInvalidException("File size must be greater than 0"));

        mockMvc.perform(multipart("/api/v1/tracks").file(audioFile()).param("title", "My Song").principal(aCaller()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.status").value(400))
            .andExpect(jsonPath("$.detail").value("File size must be greater than 0"));
    }

    // Upload needs a signed-in caller; the id is only read, so any UUID will do for these tests.
    private static Principal aCaller() {
        return UUID.fromString("5b0c2d4e-1111-4222-8333-944455566677")::toString;
    }
}
