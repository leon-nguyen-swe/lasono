package com.lasono.track.application.port.out;

/** The audio could not be analysed or converted (corrupt file, tool failure, timeout). */
public class AudioProcessingException extends RuntimeException {

    public AudioProcessingException(String message) {
        super(message);
    }

    public AudioProcessingException(String message, Throwable cause) {
        super(message, cause);
    }
}
