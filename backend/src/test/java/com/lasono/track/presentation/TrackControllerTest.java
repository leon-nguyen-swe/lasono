package com.lasono.track.presentation;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.io.ByteArrayInputStream;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import com.lasono.track.application.usecase.GetTrackResult;
import com.lasono.track.application.usecase.GetTrackUseCase;
import com.lasono.track.application.usecase.InvalidRangeException;
import com.lasono.track.application.usecase.StreamTrackResult;
import com.lasono.track.application.usecase.StreamTrackUseCase;
import com.lasono.track.application.usecase.TrackNotFoundException;
import com.lasono.track.application.usecase.UploadTrackResult;
import com.lasono.track.application.usecase.UploadTrackUseCase;

@ExtendWith(MockitoExtension.class)
class TrackControllerTest {

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

    // -----------------------------------------------------------------------
    // GET /api/v1/tracks/{id}  — 3 tests
    // -----------------------------------------------------------------------

    @Test
    void givenExistingTrack_getTrack_returns200WithTrackInfo() throws Exception {
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
    void givenUnknownTrackId_getTrack_returns404() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}", id))
            .andExpect(status().isNotFound());
    }

    @Test
    void givenNonUuidPathVariable_getTrack_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/tracks/{id}", "abc"))
            .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // POST /api/v1/tracks  — upload  — 4 tests
    // -----------------------------------------------------------------------

    @Test
    void givenValidMultipartRequest_uploadTrack_returns201WithResult() throws Exception {
        UUID trackId = UUID.randomUUID();
        when(uploadTrackUseCase.execute(any())).thenReturn(
            new UploadTrackResult(trackId.toString(), "My Song", "PROCESSING")
        );

        MockMultipartFile file = new MockMultipartFile(
            "file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/v1/tracks")
                .file(file)
                .param("title", "My Song")
                .param("description", "A great song"))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.trackId").value(trackId.toString()))
            .andExpect(jsonPath("$.title").value("My Song"))
            .andExpect(jsonPath("$.status").value("PROCESSING"));
    }

    @Test
    void givenRequestWithoutDescription_uploadTrack_returns201() throws Exception {
        UUID trackId = UUID.randomUUID();
        when(uploadTrackUseCase.execute(any())).thenReturn(
            new UploadTrackResult(trackId.toString(), "My Song", "PROCESSING")
        );

        MockMultipartFile file = new MockMultipartFile(
            "file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes()
        );

        // description is optional — omitting it should still succeed
        mockMvc.perform(multipart("/api/v1/tracks")
                .file(file)
                .param("title", "My Song"))
            .andExpect(status().isCreated());
    }

    @Test
    void givenMissingTitleParam_uploadTrack_returns400() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
            "file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes()
        );

        mockMvc.perform(multipart("/api/v1/tracks")
                .file(file))
            .andExpect(status().isBadRequest());
    }

    @Test
    void givenMissingFilePart_uploadTrack_returns400() throws Exception {
        mockMvc.perform(multipart("/api/v1/tracks")
                .param("title", "My Song"))
            .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/tracks/{id}/stream — full response (no Range header) — 2 tests
    // -----------------------------------------------------------------------

    @Test
    void givenNoRangeHeader_streamTrack_returns200WithHeadersAndContentLength() throws Exception {
        UUID id = UUID.randomUUID();
        byte[] audioBytes = "audio-data".getBytes();
        StreamTrackResult result = new StreamTrackResult(
            new ByteArrayInputStream(audioBytes),
            "audio/mpeg",
            audioBytes.length,
            0,
            audioBytes.length - 1,
            false   // not partial
        );
        when(streamTrackUseCase.execute(eq(id), isNull())).thenReturn(result);

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id))
            .andExpect(status().isOk())
            .andExpect(header().string(HttpHeaders.ACCEPT_RANGES, "bytes"))
            .andExpect(header().doesNotExist(HttpHeaders.CONTENT_RANGE))
            .andExpect(header().longValue(HttpHeaders.CONTENT_LENGTH, audioBytes.length))
            .andExpect(content().contentTypeCompatibleWith(MediaType.parseMediaType("audio/mpeg")));
    }

    @Test
    void givenNoRangeHeader_streamTrack_writesCorrectBytesToResponse() throws Exception {
        UUID id = UUID.randomUUID();
        byte[] audioBytes = "audio-data".getBytes();
        StreamTrackResult result = new StreamTrackResult(
            new ByteArrayInputStream(audioBytes),
            "audio/mpeg",
            audioBytes.length,
            0,
            audioBytes.length - 1,
            false
        );
        when(streamTrackUseCase.execute(eq(id), isNull())).thenReturn(result);

        // StreamingResponseBody runs asynchronously — must use asyncDispatch to read body
        MvcResult asyncResult = mockMvc.perform(get("/api/v1/tracks/{id}/stream", id))
            .andExpect(request().asyncStarted())
            .andReturn();

        mockMvc.perform(asyncDispatch(asyncResult))
            .andExpect(status().isOk())
            .andExpect(content().bytes(audioBytes));
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/tracks/{id}/stream — partial response (Range header) — 3 tests
    // -----------------------------------------------------------------------

    @Test
    void givenRangeHeader_streamTrack_returns206WithContentRangeAndLength() throws Exception {
        UUID id = UUID.randomUUID();
        byte[] slice = new byte[500];
        long fileSize = 1000L;
        StreamTrackResult result = new StreamTrackResult(
            new ByteArrayInputStream(slice),
            "audio/mpeg",
            fileSize,
            0,
            499,
            true    // partial
        );
        when(streamTrackUseCase.execute(eq(id), eq("bytes=0-499"))).thenReturn(result);

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id)
                .header(HttpHeaders.RANGE, "bytes=0-499"))
            .andExpect(status().isPartialContent())
            .andExpect(header().string(HttpHeaders.CONTENT_RANGE, "bytes 0-499/1000"))
            .andExpect(header().string(HttpHeaders.ACCEPT_RANGES, "bytes"))
            .andExpect(header().longValue(HttpHeaders.CONTENT_LENGTH, 500));
    }

    @Test
    void givenRangeHeaderForSecondHalf_streamTrack_returnsCorrectContentRange() throws Exception {
        UUID id = UUID.randomUUID();
        long fileSize = 1000L;
        StreamTrackResult result = new StreamTrackResult(
            new ByteArrayInputStream(new byte[500]),
            "audio/mpeg",
            fileSize,
            500,
            999,
            true
        );
        when(streamTrackUseCase.execute(eq(id), eq("bytes=500-999"))).thenReturn(result);

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id)
                .header(HttpHeaders.RANGE, "bytes=500-999"))
            .andExpect(status().isPartialContent())
            .andExpect(header().string(HttpHeaders.CONTENT_RANGE, "bytes 500-999/1000"));
    }

    @Test
    void givenRangeHeader_streamTrack_writesCorrectSliceBytesToResponse() throws Exception {
        UUID id = UUID.randomUUID();
        byte[] slice = "partial-audio-bytes".getBytes();
        long fileSize = 1000L;
        StreamTrackResult result = new StreamTrackResult(
            new ByteArrayInputStream(slice),
            "audio/mpeg",
            fileSize,
            0,
            slice.length - 1,
            true
        );
        when(streamTrackUseCase.execute(eq(id), eq("bytes=0-" + (slice.length - 1)))).thenReturn(result);

        MvcResult asyncResult = mockMvc.perform(get("/api/v1/tracks/{id}/stream", id)
                .header(HttpHeaders.RANGE, "bytes=0-" + (slice.length - 1)))
            .andExpect(request().asyncStarted())
            .andReturn();

        mockMvc.perform(asyncDispatch(asyncResult))
            .andExpect(status().isPartialContent())
            .andExpect(content().bytes(slice));
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/tracks/{id}/stream — error paths  — 3 tests
    // -----------------------------------------------------------------------

    @Test
    void givenUnknownTrackId_streamTrack_returns404() throws Exception {
        UUID id = UUID.randomUUID();
        when(streamTrackUseCase.execute(eq(id), any())).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id))
            .andExpect(status().isNotFound());
    }

    @Test
    void givenInvalidRangeHeader_streamTrack_returns416WithContentRangeHeaderAndBody() throws Exception {
        UUID id = UUID.randomUUID();
        long fileSize = 1000L;
        when(streamTrackUseCase.execute(eq(id), eq("bytes=5000-9999")))
            .thenThrow(new InvalidRangeException(fileSize));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id)
                .header(HttpHeaders.RANGE, "bytes=5000-9999"))
            .andExpect(status().isRequestedRangeNotSatisfiable())
            .andExpect(header().string(HttpHeaders.CONTENT_RANGE, "bytes */" + fileSize))
            .andExpect(jsonPath("$.status").value(416));
    }

    @Test
    void givenNonUuidPathVariable_streamTrack_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/tracks/{id}/stream", "not-a-uuid"))
            .andExpect(status().isBadRequest());
    }
}