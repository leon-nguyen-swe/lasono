package com.lasono.config;

import static org.hamcrest.Matchers.allOf;
import static org.hamcrest.Matchers.containsString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.lasono.track.application.usecase.GetTrackUseCase;
import com.lasono.track.application.usecase.ListTracksResult;
import com.lasono.track.application.usecase.ListTracksUseCase;
import com.lasono.track.application.usecase.StreamTrackUseCase;
import com.lasono.track.application.usecase.TrackNotFoundException;
import com.lasono.track.application.usecase.UploadTrackUseCase;
import com.lasono.track.presentation.TrackController;
import com.lasono.track.presentation.TrackExceptionHandler;

@ExtendWith(MockitoExtension.class)
class CorsConfigTest {

    private static final String FLUTTER_ORIGIN = "http://localhost:3000";
    private static final String FLUTTER_ORIGIN_IP = "http://127.0.0.1:3000";
    private static final String UNKNOWN_ORIGIN = "http://evil.example";

    @Mock
    private UploadTrackUseCase uploadTrackUseCase;

    @Mock
    private GetTrackUseCase getTrackUseCase;

    @Mock
    private StreamTrackUseCase streamTrackUseCase;

    @Mock
    private ListTracksUseCase listTracksUseCase;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        TrackController controller =
            new TrackController(uploadTrackUseCase, getTrackUseCase, streamTrackUseCase, listTracksUseCase);
        mockMvc = MockMvcBuilders.standaloneSetup(controller)
            .setControllerAdvice(new TrackExceptionHandler())
            .addFilters(new CorsConfig().corsFilter(List.of(FLUTTER_ORIGIN, FLUTTER_ORIGIN_IP)))
            .build();
    }

    @Test
    void givenAllowedOrigin_get_returnsAllowOriginHeader() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.ORIGIN, FLUTTER_ORIGIN))
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, FLUTTER_ORIGIN));
    }

    @Test
    void givenAllowedOrigin_listTracks_returnsAllowOriginHeader() throws Exception {
        when(listTracksUseCase.execute(null, null)).thenReturn(new ListTracksResult(List.of(), null));

        mockMvc.perform(get("/api/v1/tracks").header(HttpHeaders.ORIGIN, FLUTTER_ORIGIN))
            .andExpect(status().isOk())
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, FLUTTER_ORIGIN));
    }

    @Test
    void givenAllowedIpOrigin_get_returnsAllowOriginHeader() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.ORIGIN, FLUTTER_ORIGIN_IP))
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, FLUTTER_ORIGIN_IP));
    }

    @Test
    void givenAllowedOrigin_errorResponse_stillCarriesAllowOriginHeader() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.ORIGIN, FLUTTER_ORIGIN))
            .andExpect(status().isNotFound())
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, FLUTTER_ORIGIN));
    }

    @Test
    void givenAllowedOrigin_streamResponse_exposesRangeHeaders() throws Exception {
        UUID id = UUID.randomUUID();
        when(streamTrackUseCase.execute(id, null)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id).header(HttpHeaders.ORIGIN, FLUTTER_ORIGIN))
            .andExpect(header().string(
                HttpHeaders.ACCESS_CONTROL_EXPOSE_HEADERS,
                allOf(
                    containsString(HttpHeaders.CONTENT_RANGE),
                    containsString(HttpHeaders.ACCEPT_RANGES),
                    containsString(HttpHeaders.CONTENT_LENGTH)
                )
            ));
    }

    @Test
    void givenAllowedOrigin_multipartPost_returnsAllowOriginHeader() throws Exception {
        MockMultipartFile file = new MockMultipartFile("file", "song.mp3", "audio/mpeg", "x".getBytes());

        // title is missing on purpose: we only care that the CORS header is present on the 400
        mockMvc.perform(multipart("/api/v1/tracks").file(file).header(HttpHeaders.ORIGIN, FLUTTER_ORIGIN))
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, FLUTTER_ORIGIN));
    }

    // Without this header the browser throws away the response cookie of /auth/refresh and does not send
    // the cookie back, even though the server did its part.
    @Test
    void givenAllowedOrigin_get_allowsCredentials() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.ORIGIN, FLUTTER_ORIGIN))
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_CREDENTIALS, "true"));
    }

    @Test
    void givenAllowedOrigin_preflight_allowsCredentials() throws Exception {
        mockMvc.perform(options("/api/v1/tracks")
                .header(HttpHeaders.ORIGIN, FLUTTER_ORIGIN)
                .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST"))
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_CREDENTIALS, "true"));
    }

    @Test
    void givenUnknownOrigin_get_isRejectedWithoutAllowOriginHeader() throws Exception {
        UUID id = UUID.randomUUID();

        mockMvc.perform(get("/api/v1/tracks/{id}", id).header(HttpHeaders.ORIGIN, UNKNOWN_ORIGIN))
            .andExpect(status().isForbidden())
            .andExpect(header().doesNotExist(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN));
    }

    @Test
    void givenAllowedOrigin_preflight_allowsPost() throws Exception {
        mockMvc.perform(options("/api/v1/tracks")
                .header(HttpHeaders.ORIGIN, FLUTTER_ORIGIN)
                .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST"))
            .andExpect(status().isOk())
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, FLUTTER_ORIGIN))
            .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_METHODS, containsString("POST")));
    }

    @Test
    void givenUnknownOrigin_preflight_isRejected() throws Exception {
        mockMvc.perform(options("/api/v1/tracks")
                .header(HttpHeaders.ORIGIN, UNKNOWN_ORIGIN)
                .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST"))
            .andExpect(status().isForbidden())
            .andExpect(header().doesNotExist(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN));
    }
}
