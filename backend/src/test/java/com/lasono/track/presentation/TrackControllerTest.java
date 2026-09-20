package com.lasono.track.presentation;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.lasono.track.application.usecase.GetTrackResult;
import com.lasono.track.application.usecase.GetTrackUseCase;
import com.lasono.track.application.usecase.TrackNotFoundException;
import com.lasono.track.application.usecase.UploadTrackUseCase;

@ExtendWith(MockitoExtension.class)
class TrackControllerTest {

    @Mock
    private UploadTrackUseCase uploadTrackUseCase;

    @Mock
    private GetTrackUseCase getTrackUseCase;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        TrackController controller = new TrackController(uploadTrackUseCase, getTrackUseCase);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
            .setControllerAdvice(new TrackExceptionHandler())
            .build();
    }

    @Test
    void returns200WithTrackInfoWhenTrackExists() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id)).thenReturn(
            new GetTrackResult(id.toString(), "My song", "desc", "PROCESSING", "audio/mpeg", null)
        );

        mockMvc.perform(get("/api/v1/tracks/{id}", id))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.id").value(id.toString()))
            .andExpect(jsonPath("$.status").value("PROCESSING"));
    }

    @Test
    void returns404WhenTrackDoesNotExist() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}", id))
            .andExpect(status().isNotFound());
    }

    @Test
    void returns400WhenIdIsNotAUuid() throws Exception {
        mockMvc.perform(get("/api/v1/tracks/{id}", "abc"))
            .andExpect(status().isBadRequest());
    }
}