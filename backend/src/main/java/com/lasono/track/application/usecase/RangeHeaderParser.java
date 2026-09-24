package com.lasono.track.application.usecase;

final class RangeHeaderParser {

    private RangeHeaderParser() {}

    static long[] parse(String rangeHeader, long fileSize) {
        if (rangeHeader == null) {
            return new long[] {0, fileSize -1};
        }
        if (!rangeHeader.startsWith("bytes=") || rangeHeader.contains(",")) {
            throw new InvalidRangeException(fileSize);
        }

        String spec = rangeHeader.substring("bytes=".length());
        int dash = spec.indexOf('-');
        if (dash < 0) {
            throw new InvalidRangeException(fileSize);
        }

        String startPart = spec.substring(0, dash);
        String endPart = spec.substring(dash + 1);

        long start;
        long end;
        if (startPart.isEmpty()) {
            if (endPart.isEmpty()) {
                throw new InvalidRangeException(fileSize);
            }
            long suffixLength = parseLong(endPart, fileSize);
            start = Math.max(0, fileSize - suffixLength);
            end = fileSize - 1;
        } else {
            start = parseLong(startPart, fileSize);
            end = endPart.isEmpty() ? fileSize - 1 : parseLong(endPart, fileSize);
        }

        if (start < 0 || end < start || start >= fileSize) {
            throw new InvalidRangeException(fileSize);
        }

        return new long[] {start, Math.min(end, fileSize - 1)};
    }

    private static long parseLong(String value, long fileSize) {
        try {
            long parsed = Long.parseLong(value);
            if (parsed < 0) {
                throw new InvalidRangeException(fileSize);
            }
            return parsed;
        } catch (NumberFormatException e) {
            throw new InvalidRangeException(fileSize);
        }
    }
}
