package com.lasono.track.presentation;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.lasono.track.application.usecase.GetTrackUseCase;
import com.lasono.track.application.usecase.StreamTrackUseCase;
import com.lasono.track.application.usecase.UploadTrackUseCase;
import com.lasono.track.domain.audio.exception.AudioFormatInvalidException;
import com.lasono.track.domain.audio.exception.OriginalAudioInvalidException;
import com.lasono.track.domain.exception.TrackTitleInvalidException;

@ExtendWith(MockitoExtension.class)
class TrackExceptionHandlerTest {

    @Mock
    private UploadTrackUseCase uploadTrackUseCase;

    @Mock
    private GetTrackUseCase getTrackUseCase;

    @Mock
    private StreamTrackUseCase streamTrackUseCase;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        TrackController controller = new TrackController(uploadTrackUseCase, getTrackUseCase, streamTrackUseCase);
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

        mockMvc.perform(multipart("/api/v1/tracks").file(audioFile()).param("title", "My Song"))
            .andExpect(status().isUnsupportedMediaType())
            .andExpect(jsonPath("$.status").value(415))
            .andExpect(jsonPath("$.detail").value("Unsupported MIME type: application/octet-stream"));
    }

    @Test
    void givenInvalidTitle_uploadTrack_returns400() throws Exception {
        when(uploadTrackUseCase.execute(any()))
            .thenThrow(new TrackTitleInvalidException("Track title must not be blank"));

        mockMvc.perform(multipart("/api/v1/tracks").file(audioFile()).param("title", "   "))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.status").value(400))
            .andExpect(jsonPath("$.detail").value("Track title must not be blank"));
    }

    @Test
    void givenEmptyAudioFile_uploadTrack_returns400() throws Exception {
        when(uploadTrackUseCase.execute(any()))
            .thenThrow(new OriginalAudioInvalidException("File size must be greater than 0"));

        mockMvc.perform(multipart("/api/v1/tracks").file(audioFile()).param("title", "My Song"))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.status").value(400))
            .andExpect(jsonPath("$.detail").value("File size must be greater than 0"));
    }
}
