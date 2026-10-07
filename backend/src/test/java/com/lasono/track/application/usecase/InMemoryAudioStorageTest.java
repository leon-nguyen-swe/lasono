package com.lasono.track.application.usecase;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.Test;

import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.audio.model.AudioFormat;

class InMemoryAudioStorageTest {

    private final InMemoryAudioStorage storage = new InMemoryAudioStorage();

    @Test
    void returnsTheBytesThatWereStored() throws Exception {
        StorageKey key = storage.store(
            new ByteArrayInputStream("some audio".getBytes(StandardCharsets.UTF_8)), AudioFormat.MP3);

        assertThat(storage.retrieve(key).readAllBytes()).isEqualTo("some audio".getBytes(StandardCharsets.UTF_8));
        assertThat(key.value()).endsWith(".mp3");
    }

    @Test
    void returnsOnlyTheRequestedRangeOfAFile() throws Exception {
        StorageKey key = storage.store(
            new ByteArrayInputStream("0123456789".getBytes(StandardCharsets.UTF_8)), AudioFormat.MP3);

        assertThat(storage.retrieveRange(key, 2, 4).readAllBytes()).isEqualTo("2345".getBytes(StandardCharsets.UTF_8));
    }

    @Test
    void forgetsAFileThatWasDeleted() {
        StorageKey key = storage.store(new ByteArrayInputStream(new byte[] {1}), AudioFormat.WAV);

        storage.delete(key);

        assertThat(storage.files).isEmpty();
        assertThatThrownBy(() -> storage.retrieve(key)).isInstanceOf(AudioStorageException.class);
    }

    @Test
    void neverGivesTheSameKeyTwice() {
        StorageKey first = storage.store(new ByteArrayInputStream(new byte[] {1}), AudioFormat.WAV);
        storage.delete(first);

        StorageKey second = storage.store(new ByteArrayInputStream(new byte[] {2}), AudioFormat.WAV);

        assertThat(second).isNotEqualTo(first);
    }
}
