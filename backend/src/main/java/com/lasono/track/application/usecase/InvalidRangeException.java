package com.lasono.track.application.usecase;

public class InvalidRangeException extends RuntimeException {

    private final long fileSize;

    public InvalidRangeException(long fileSize) {
        super("Requested range is not satisfiable for file size " + fileSize);
        this.fileSize = fileSize;
    }

    public long getFileSize() {
        return fileSize;
    }
}
