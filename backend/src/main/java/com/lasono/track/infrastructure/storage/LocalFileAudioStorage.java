package com.lasono.track.infrastructure.storage;

import java.io.FilterInputStream;
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
import com.lasono.track.application.port.out.StorageKeyInvalidException;

@Component
public class LocalFileAudioStorage implements AudioStorage {

    private final Path rootDirectory;

    public LocalFileAudioStorage(@Value("${lasono.storage.root}") String rootPath) {
        this.rootDirectory = Paths.get(rootPath).toAbsolutePath().normalize();
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
    public InputStream retrieveRange(StorageKey key, long offset, long length) {
        if (offset < 0) {
            throw new IllegalArgumentException("Offset must not be negative");
        }
        if (length <= 0) {
            throw new IllegalArgumentException("Length must be greater than 0");
        }
        try {
            InputStream in = Files.newInputStream(resolveSafety(key));
            try {
                in.skipNBytes(offset);
            } catch (IOException | RuntimeException e) {
                in.close();
                throw e;
            }
            return new LimitedInputStream(in, length);
        } catch (IOException e) {
            throw new AudioStorageException("Failed to read audio range", e);
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

    private Path resolveSafety(StorageKey key) {
        Path resolved = rootDirectory.resolve(key.value()).normalize();
        if (!resolved.startsWith(rootDirectory)) {
            throw new StorageKeyInvalidException("Storage key escapes the storage root");
        }
        return resolved;
    }

    private static final class LimitedInputStream extends FilterInputStream {
        
        private long remaining;

        LimitedInputStream(
            InputStream in,
            long limit
        ) {
            super(in);
            this.remaining = limit;
        }

        @Override 
        public int read() throws IOException {
            if (remaining <= 0) {
                return -1;
            }
            int b = super.read();
            if (b != -1) {
                remaining--;
            }
            return b;
        }

        @Override 
        public int read(
            byte[] buffer,
            int off,
            int len
        ) throws IOException {
            if (remaining <= 0) {
                return -1;
            }
            int n = super.read(buffer, off, (int) Math.min(len, remaining));
            if (n > 0) {
                remaining -= n;
            }
            return n;
        }
        
        @Override 
        public boolean markSupported() {
            return false;
        }
    }
}