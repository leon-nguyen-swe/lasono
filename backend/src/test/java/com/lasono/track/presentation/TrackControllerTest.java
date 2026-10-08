package com.lasono.track.presentation;

import static org.hamcrest.Matchers.nullValue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.io.ByteArrayInputStream;
import java.util.List;
import java.security.Principal;
import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
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
import com.lasono.track.application.usecase.ListTracksResult;
import com.lasono.track.application.usecase.ListTracksUseCase;
import com.lasono.track.application.usecase.StreamTrackResult;
import com.lasono.track.application.usecase.StreamTrackUseCase;
import com.lasono.track.application.usecase.TrackListItemResult;
import com.lasono.track.application.usecase.TrackNotFoundException;
import com.lasono.track.application.usecase.UploadTrackCommand;
import com.lasono.track.application.usecase.UploadTrackResult;
import com.lasono.track.application.usecase.UploadTrackUseCase;
import com.lasono.track.application.usecase.GetStreamUrlUseCase;
import com.lasono.track.application.usecase.StreamSignature;
import com.lasono.track.application.usecase.StreamUrlResult;
import com.lasono.track.application.usecase.DeleteTrackUseCase;
import com.lasono.track.application.usecase.UpdateTrackUseCase;
import com.lasono.track.application.usecase.UpdateTrackCommand;

@ExtendWith(MockitoExtension.class)
class TrackControllerTest {

    private static final String OWNER_ID = "00000000-0000-0000-0000-0000000000a1";
    private static final UUID USER_ID = UUID.fromString("5b0c2d4e-1111-4222-8333-944455566677");

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

    @Mock
    private UpdateTrackUseCase updateTrackUseCase;

    @Mock
    private DeleteTrackUseCase deleteTrackUseCase;

    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        TrackController controller =
            new TrackController(
                uploadTrackUseCase, getTrackUseCase, streamTrackUseCase, listTracksUseCase, getStreamUrlUseCase,
                updateTrackUseCase, deleteTrackUseCase);
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
        when(getTrackUseCase.execute(id, null)).thenReturn(
            new GetTrackResult(id.toString(), OWNER_ID, "My song", "desc", "PUBLIC", "PROCESSING", "audio/mpeg", null, null)
        );

        mockMvc.perform(get("/api/v1/tracks/{id}", id))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.id").value(id.toString()))
            .andExpect(jsonPath("$.status").value("PROCESSING"));
    }

    @Test
    void givenReadyTrack_getTrack_returnsDurationAndWaveform() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id, null)).thenReturn(
            new GetTrackResult(id.toString(), OWNER_ID, "My song", "desc", "PUBLIC", "READY", "audio/mpeg", 3.5, List.of(0.1f, 0.5f))
        );

        mockMvc.perform(get("/api/v1/tracks/{id}", id))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.durationSeconds").value(3.5))
            .andExpect(jsonPath("$.waveform.length()").value(2))
            .andExpect(jsonPath("$.waveform[1]").value(0.5));
    }

    @Test
    void givenUnknownTrackId_getTrack_returns404() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id, null)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}", id))
            .andExpect(status().isNotFound());
    }

    @Test
    void givenNonUuidPathVariable_getTrack_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/tracks/{id}", "abc"))
            .andExpect(status().isBadRequest());
    }

    // -----------------------------------------------------------------------
    // GET /api/v1/tracks  — list, keyset pagination  — 4 tests
    // -----------------------------------------------------------------------

    @Test
    void givenTracks_listTracks_returns200WithItemsAndNextCursor() throws Exception {
        UUID id = UUID.randomUUID();
        when(listTracksUseCase.execute(null, null, null)).thenReturn(new ListTracksResult(
            List.of(new TrackListItemResult(id.toString(), OWNER_ID, "My song", "desc", "PUBLIC", "PROCESSING", null)),
            "next-cursor"
        ));

        mockMvc.perform(get("/api/v1/tracks"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.items.length()").value(1))
            .andExpect(jsonPath("$.items[0].id").value(id.toString()))
            .andExpect(jsonPath("$.items[0].title").value("My song"))
            .andExpect(jsonPath("$.items[0].description").value("desc"))
            .andExpect(jsonPath("$.items[0].status").value("PROCESSING"))
            .andExpect(jsonPath("$.nextCursor").value("next-cursor"));
    }

    @Test
    void givenLastPage_listTracks_returnsANullNextCursor() throws Exception {
        when(listTracksUseCase.execute(null, null, null)).thenReturn(new ListTracksResult(List.of(), null));

        mockMvc.perform(get("/api/v1/tracks"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.items.length()").value(0))
            .andExpect(jsonPath("$.nextCursor").value(nullValue()));
    }

    @Test
    void givenCursorAndLimit_listTracks_passesThemToTheUseCase() throws Exception {
        when(listTracksUseCase.execute("abc", 5, null)).thenReturn(new ListTracksResult(List.of(), null));

        mockMvc.perform(get("/api/v1/tracks").param("cursor", "abc").param("limit", "5"))
            .andExpect(status().isOk());

        verify(listTracksUseCase).execute("abc", 5, null);
    }

    @Test
    void givenNonNumericLimit_listTracks_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/tracks").param("limit", "many"))
            .andExpect(status().isBadRequest());

        verifyNoInteractions(listTracksUseCase);
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
                .param("description", "A great song")
                .principal(signedInAs(USER_ID)))
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
                .param("title", "My Song")
                .principal(signedInAs(USER_ID)))
            .andExpect(status().isCreated());
    }

    // The owner comes from the login, never from a field the caller could fill in with someone else's id.
    @Test
    void givenSignedInCaller_uploadTrack_passesTheCallerIdAsOwner() throws Exception {
        when(uploadTrackUseCase.execute(any())).thenReturn(
            new UploadTrackResult(UUID.randomUUID().toString(), "My Song", "PROCESSING")
        );
        MockMultipartFile file = new MockMultipartFile("file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes());

        mockMvc.perform(multipart("/api/v1/tracks")
                .file(file)
                .param("title", "My Song")
                .param("ownerId", UUID.randomUUID().toString())
                .principal(signedInAs(USER_ID)))
            .andExpect(status().isCreated());

        ArgumentCaptor<UploadTrackCommand> captor = ArgumentCaptor.forClass(UploadTrackCommand.class);
        verify(uploadTrackUseCase).execute(captor.capture());
        assertEquals(USER_ID, captor.getValue().ownerId());
    }

    @Test
    void givenVisibilityField_uploadTrack_passesItToTheUseCase() throws Exception {
        when(uploadTrackUseCase.execute(any())).thenReturn(
            new UploadTrackResult(UUID.randomUUID().toString(), "My Song", "PROCESSING")
        );
        MockMultipartFile file = new MockMultipartFile("file", "song.mp3", "audio/mpeg", "audio-bytes".getBytes());

        mockMvc.perform(multipart("/api/v1/tracks")
                .file(file)
                .param("title", "My Song")
                .param("visibility", "PRIVATE")
                .principal(signedInAs(USER_ID)))
            .andExpect(status().isCreated());

        ArgumentCaptor<UploadTrackCommand> captor = ArgumentCaptor.forClass(UploadTrackCommand.class);
        verify(uploadTrackUseCase).execute(captor.capture());
        assertEquals("PRIVATE", captor.getValue().visibility());
    }

    private static Principal signedInAs(UUID userId) {
        return userId::toString;
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
        when(streamTrackUseCase.execute(eq(id), isNull(), isNull(), isNull())).thenReturn(result);

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
        when(streamTrackUseCase.execute(eq(id), isNull(), isNull(), isNull())).thenReturn(result);

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
        when(streamTrackUseCase.execute(eq(id), eq("bytes=0-499"), isNull(), isNull())).thenReturn(result);

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
        when(streamTrackUseCase.execute(eq(id), eq("bytes=500-999"), isNull(), isNull())).thenReturn(result);

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
        when(streamTrackUseCase.execute(eq(id), eq("bytes=0-" + (slice.length - 1)), isNull(), isNull())).thenReturn(result);

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
        when(streamTrackUseCase.execute(eq(id), any(), isNull(), isNull())).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id))
            .andExpect(status().isNotFound());
    }

    @Test
    void givenInvalidRangeHeader_streamTrack_returns416WithContentRangeHeaderAndBody() throws Exception {
        UUID id = UUID.randomUUID();
        long fileSize = 1000L;
        when(streamTrackUseCase.execute(eq(id), eq("bytes=5000-9999"), isNull(), isNull()))
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

    // The viewer is the id in the token. Reading is open to everyone, so without a login it is null.
    @Test
    void givenSignedInCaller_getTrack_passesTheCallerIdAsViewer() throws Exception {
        UUID id = UUID.randomUUID();
        when(getTrackUseCase.execute(id, USER_ID)).thenReturn(
            new GetTrackResult(id.toString(), OWNER_ID, "My song", "desc", "PRIVATE", "READY", "audio/mpeg", 3.5, null));

        mockMvc.perform(get("/api/v1/tracks/{id}", id).principal(signedInAs(USER_ID)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.visibility").value("PRIVATE"));
    }

    @Test
    void givenSignedInCaller_listTracks_passesTheCallerIdAsViewer() throws Exception {
        when(listTracksUseCase.execute(null, null, USER_ID)).thenReturn(new ListTracksResult(List.of(), null));

        mockMvc.perform(get("/api/v1/tracks").principal(signedInAs(USER_ID)))
            .andExpect(status().isOk());

        verify(listTracksUseCase).execute(null, null, USER_ID);
    }

    @Test
    void givenSignedInCaller_streamTrack_passesTheCallerIdAsViewer() throws Exception {
        UUID id = UUID.randomUUID();
        when(streamTrackUseCase.execute(id, null, USER_ID, null)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id).principal(signedInAs(USER_ID)))
            .andExpect(status().isNotFound());

        verify(streamTrackUseCase).execute(id, null, USER_ID, null);
    }

    // --- stream-url and signed stream addresses ---

    @Test
    void givenVisibleTrack_streamUrl_returnsTheSignedAddressAndTellsCachesNotToKeepIt() throws Exception {
        UUID id = UUID.randomUUID();
        when(getStreamUrlUseCase.execute(id, USER_ID)).thenReturn(new StreamUrlResult(
            "/api/v1/tracks/" + id + "/stream?expires=1&signature=abc", Instant.parse("2026-10-08T11:00:00Z")));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream-url", id).principal(signedInAs(USER_ID)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.url").value("/api/v1/tracks/" + id + "/stream?expires=1&signature=abc"))
            .andExpect(jsonPath("$.expiresAt").value("2026-10-08T11:00:00Z"))
            .andExpect(header().string("Cache-Control", "no-store"));
    }

    @Test
    void givenNobodyLoggedIn_streamUrl_asksForAPublicViewer() throws Exception {
        UUID id = UUID.randomUUID();
        when(getStreamUrlUseCase.execute(id, null)).thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream-url", id))
            .andExpect(status().isNotFound());
    }

    @Test
    void givenSignatureParameters_streamTrack_passesThemToTheUseCase() throws Exception {
        UUID id = UUID.randomUUID();
        when(streamTrackUseCase.execute(eq(id), isNull(), isNull(), any()))
            .thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id).param("expires", "1800000000").param("signature", "abc"))
            .andExpect(status().isNotFound());

        ArgumentCaptor<StreamSignature> captor = ArgumentCaptor.forClass(StreamSignature.class);
        verify(streamTrackUseCase).execute(eq(id), isNull(), isNull(), captor.capture());
        assertEquals(new StreamSignature(1_800_000_000L, "abc"), captor.getValue());
    }

    // Half a signature proves nothing, so it is treated as none.
    @Test
    void givenOnlyOneOfTheSignatureParameters_streamTrack_passesNoSignature() throws Exception {
        UUID id = UUID.randomUUID();
        when(streamTrackUseCase.execute(eq(id), isNull(), isNull(), isNull()))
            .thenThrow(new TrackNotFoundException(id));

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id).param("signature", "abc"))
            .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id).param("expires", "1800000000"))
            .andExpect(status().isNotFound());
    }

    @Test
    void givenAnExpiryThatIsNotANumber_streamTrack_returns400() throws Exception {
        UUID id = UUID.randomUUID();

        mockMvc.perform(get("/api/v1/tracks/{id}/stream", id).param("expires", "soon").param("signature", "abc"))
            .andExpect(status().isBadRequest());

        verifyNoInteractions(streamTrackUseCase);
    }

    // --- PATCH and DELETE: the caller comes from the token, the rules live in the use cases ---

    @Test
    void givenJsonWithSomeFields_updateTrack_passesTheCallerAndOnlyThoseFieldsAndReturnsTheTrack() throws Exception {
        UUID id = UUID.randomUUID();
        when(updateTrackUseCase.execute(any())).thenReturn(
            new GetTrackResult(id.toString(), OWNER_ID, "New title", "desc", "PRIVATE", "READY", "audio/mpeg", 3.5, null));

        mockMvc.perform(patch("/api/v1/tracks/{id}", id)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"title\":\"New title\",\"visibility\":\"PRIVATE\"}")
                .principal(signedInAs(USER_ID)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.title").value("New title"))
            .andExpect(jsonPath("$.visibility").value("PRIVATE"));

        ArgumentCaptor<UpdateTrackCommand> captor = ArgumentCaptor.forClass(UpdateTrackCommand.class);
        verify(updateTrackUseCase).execute(captor.capture());
        assertEquals(new UpdateTrackCommand(id, USER_ID, "New title", null, "PRIVATE"), captor.getValue());
    }

    @Test
    void givenMalformedJson_updateTrack_returns400AndSkipsTheUseCase() throws Exception {
        mockMvc.perform(patch("/api/v1/tracks/{id}", UUID.randomUUID())
                .contentType(MediaType.APPLICATION_JSON)
                .content("{not json")
                .principal(signedInAs(USER_ID)))
            .andExpect(status().isBadRequest());

        verifyNoInteractions(updateTrackUseCase);
    }

    @Test
    void givenSignedInOwner_deleteTrack_returns204AndPassesTheCaller() throws Exception {
        UUID id = UUID.randomUUID();

        mockMvc.perform(delete("/api/v1/tracks/{id}", id).principal(signedInAs(USER_ID)))
            .andExpect(status().isNoContent());

        verify(deleteTrackUseCase).execute(id, USER_ID);
    }

    @Test
    void givenATrackIdThatIsNotAUuid_deleteTrack_returns400() throws Exception {
        mockMvc.perform(delete("/api/v1/tracks/{id}", "not-a-uuid").principal(signedInAs(USER_ID)))
            .andExpect(status().isBadRequest());

        verifyNoInteractions(deleteTrackUseCase);
    }

    // --- the tracks of one user (a profile page) ---

    @Test
    void givenAUserId_listUserTracks_returnsTheirTracksWithTheOwner() throws Exception {
        UUID owner = UUID.randomUUID();
        UUID track = UUID.randomUUID();
        when(listTracksUseCase.executeForOwner(owner, null, null, null)).thenReturn(new ListTracksResult(
            List.of(new TrackListItemResult(track.toString(), owner.toString(), "Song", "", "PUBLIC", "READY", 3.5)),
            "next-cursor"));

        mockMvc.perform(get("/api/v1/users/{id}/tracks", owner))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.items.length()").value(1))
            .andExpect(jsonPath("$.items[0].id").value(track.toString()))
            .andExpect(jsonPath("$.items[0].ownerId").value(owner.toString()))
            .andExpect(jsonPath("$.nextCursor").value("next-cursor"));
    }

    @Test
    void givenCursorAndLimitAndASignedInViewer_listUserTracks_passesThemAllToTheUseCase() throws Exception {
        UUID owner = UUID.randomUUID();
        when(listTracksUseCase.executeForOwner(owner, "abc", 5, USER_ID))
            .thenReturn(new ListTracksResult(List.of(), null));

        mockMvc.perform(get("/api/v1/users/{id}/tracks", owner)
                .param("cursor", "abc").param("limit", "5").principal(signedInAs(USER_ID)))
            .andExpect(status().isOk());

        verify(listTracksUseCase).executeForOwner(owner, "abc", 5, USER_ID);
    }

    @Test
    void givenAnIdThatIsNotAUuid_listUserTracks_returns400() throws Exception {
        mockMvc.perform(get("/api/v1/users/{id}/tracks", "not-a-uuid"))
            .andExpect(status().isBadRequest());

        verifyNoInteractions(listTracksUseCase);
    }
}
