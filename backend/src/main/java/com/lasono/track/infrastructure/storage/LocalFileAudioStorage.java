package com.lasono.track.infrastructure.storage;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.application.port.out.StorageKey;

@Component
public class LocalFileAudioStorage implements AudioStorage {

    private final Path rootDirectory;

    public LocalFileAudioStorage(@Value("${lasono.storage.root}") String rootPath) {
        this.rootDirectory = Paths.get(rootPath);
    }

    @Override 
    public StorageKey store(InputStream audioData, String originalFileName) {
        try {
            String key = UUID.randomUUID() + "-" + originalFileName;
            Path target = rootDirectory.resolve(key);
            Files.createDirectories(target.getParent());
            Files.copy(audioData, target, StandardCopyOption.REPLACE_EXISTING);
            return new StorageKey(key);
        } catch(IOException e) {
            throw new AudioStorageException("Failed to storage audio file", e);
        }
    }

    @Override 
    public InputStream retrieve(StorageKey key) {
        try {
            return Files.newInputStream(rootDirectory.resolve(key.value()));
        } catch(IOException e) {
            throw new AudioStorageException("Failed to read audio file", e);
        }
    }

    @Override 
    public void delete(StorageKey key) {
        try {
            Files.deleteIfExists(rootDirectory.resolve(key.value()));
        } catch(IOException e) {
            throw new AudioStorageException("Failed to delete audio file", e);
        }
    }
}