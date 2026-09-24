package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * Unit tests for {@link RangeHeaderParser#parse(String, long)}.
 *
 * <p>Pure-function tests — no I/O, no @TempDir needed.
 * Every branch in the parser is exercised below.
 */
class RangeHeaderParserTest {

    private static final long FILE_SIZE = 1000L;

    // -----------------------------------------------------------------------
    // null header — return full-file sentinel
    // -----------------------------------------------------------------------

    @Test
    void givenNullHeader_returnsFullFileRange() {
        // null Range header means "serve the whole file": [0, fileSize-1]
        long[] result = RangeHeaderParser.parse(null, FILE_SIZE);

        assertArrayEquals(new long[]{0, FILE_SIZE - 1}, result);
    }

    @Test
    void givenNullHeaderWithCustomSize_endIsCustomFileSizeMinusOne() {
        long customSize = 99999L;

        long[] result = RangeHeaderParser.parse(null, customSize);

        assertEquals(customSize - 1, result[1]);
    }

    // -----------------------------------------------------------------------
    // bytes=<start>-<end>  — normal range
    // -----------------------------------------------------------------------

    @Test
    void givenStartAndEnd_returnsExactRange() {
        long[] result = RangeHeaderParser.parse("bytes=0-499", FILE_SIZE);

        assertArrayEquals(new long[]{0, 499}, result);
    }

    @Test
    void givenStartAndEndBothZero_returnsFirstByteOnly() {
        long[] result = RangeHeaderParser.parse("bytes=0-0", FILE_SIZE);

        assertArrayEquals(new long[]{0, 0}, result);
    }

    @Test
    void givenStartAndEndBothLastIndex_returnsLastByteOnly() {
        // bytes=999-999 for a 1000-byte file
        long[] result = RangeHeaderParser.parse("bytes=999-999", FILE_SIZE);

        assertArrayEquals(new long[]{999, 999}, result);
    }

    @Test
    void givenStartAndEndInMiddle_returnsMidRange() {
        long[] result = RangeHeaderParser.parse("bytes=200-599", FILE_SIZE);

        assertArrayEquals(new long[]{200, 599}, result);
    }

    @Test
    void givenEndBeyondFileSize_endIsClampedToLastByte() {
        // end 9999 is beyond fileSize, must be clamped to 999
        long[] result = RangeHeaderParser.parse("bytes=0-9999", FILE_SIZE);

        assertArrayEquals(new long[]{0, FILE_SIZE - 1}, result);
    }

    @Test
    void givenEndExactlyAtLastByte_returnsUnchanged() {
        long[] result = RangeHeaderParser.parse("bytes=0-999", FILE_SIZE);

        assertArrayEquals(new long[]{0, 999}, result);
    }

    // -----------------------------------------------------------------------
    // bytes=<start>-  — open-ended range (from start to EOF)
    // -----------------------------------------------------------------------

    @Test
    void givenOpenEndFromBeginning_returnsEntireFile() {
        long[] result = RangeHeaderParser.parse("bytes=0-", FILE_SIZE);

        assertArrayEquals(new long[]{0, FILE_SIZE - 1}, result);
    }

    @Test
    void givenOpenEndFromMiddle_returnsSecondHalf() {
        long[] result = RangeHeaderParser.parse("bytes=500-", FILE_SIZE);

        assertArrayEquals(new long[]{500, FILE_SIZE - 1}, result);
    }

    @Test
    void givenOpenEndFromLastByte_returnsSingleByte() {
        long[] result = RangeHeaderParser.parse("bytes=999-", FILE_SIZE);

        assertArrayEquals(new long[]{999, FILE_SIZE - 1}, result);
    }

    // -----------------------------------------------------------------------
    // bytes=-<N>  — suffix range (last N bytes)
    // -----------------------------------------------------------------------

    @Test
    void givenSuffixRange_returnsLastNBytes() {
        long[] result = RangeHeaderParser.parse("bytes=-500", FILE_SIZE);

        // last 500 bytes of a 1000-byte file → [500, 999]
        assertArrayEquals(new long[]{500, FILE_SIZE - 1}, result);
    }

    @Test
    void givenSuffixLongerThanFile_startIsClampedToZero() {
        // requesting last 5000 bytes of 1000-byte file → entire file
        long[] result = RangeHeaderParser.parse("bytes=-5000", FILE_SIZE);

        assertArrayEquals(new long[]{0, FILE_SIZE - 1}, result);
    }

    @Test
    void givenSuffixEqualToFileSize_returnsEntireFile() {
        // requesting last 1000 bytes of 1000-byte file → entire file
        long[] result = RangeHeaderParser.parse("bytes=-1000", FILE_SIZE);

        assertArrayEquals(new long[]{0, FILE_SIZE - 1}, result);
    }

    @Test
    void givenSuffixOfOneByte_returnsLastByte() {
        long[] result = RangeHeaderParser.parse("bytes=-1", FILE_SIZE);

        assertArrayEquals(new long[]{FILE_SIZE - 1, FILE_SIZE - 1}, result);
    }

    // -----------------------------------------------------------------------
    // InvalidRangeException — bad prefix / format
    // -----------------------------------------------------------------------

    @Test
    void givenMissingBytesPrefix_throwsInvalidRangeException() {
        assertThrowsInvalidRange("0-499");
    }

    @Test
    void givenWrongPrefix_throwsInvalidRangeException() {
        assertThrowsInvalidRange("units=0-499");
    }

    @Test
    void givenEmptyString_throwsInvalidRangeException() {
        assertThrowsInvalidRange("");
    }

    @Test
    void givenMultiRange_throwsInvalidRangeException() {
        // RFC 9110 multi-range — not supported
        assertThrowsInvalidRange("bytes=0-499,500-999");
    }

    @Test
    void givenNoDash_throwsInvalidRangeException() {
        assertThrowsInvalidRange("bytes=0499");
    }

    // -----------------------------------------------------------------------
    // InvalidRangeException — both parts empty  (bytes=-)
    // -----------------------------------------------------------------------

    @Test
    void givenBothPartsEmpty_throwsInvalidRangeException() {
        assertThrowsInvalidRange("bytes=-");
    }

    // -----------------------------------------------------------------------
    // InvalidRangeException — end < start
    // -----------------------------------------------------------------------

    @Test
    void givenEndBeforeStart_throwsInvalidRangeException() {
        assertThrowsInvalidRange("bytes=500-100");
    }

    @Test
    void givenEndJustBelowStart_throwsInvalidRangeException() {
        assertThrowsInvalidRange("bytes=1-0");
    }

    // -----------------------------------------------------------------------
    // InvalidRangeException — start >= fileSize
    // -----------------------------------------------------------------------

    @Test
    void givenStartEqualsFileSize_throwsInvalidRangeException() {
        assertThrowsInvalidRange("bytes=1000-1999");   // fileSize = 1000, valid range [0..999]
    }

    @Test
    void givenStartFarBeyondFileSize_throwsInvalidRangeException() {
        assertThrowsInvalidRange("bytes=99999-");
    }

    // -----------------------------------------------------------------------
    // InvalidRangeException — non-numeric values
    // -----------------------------------------------------------------------

    @ParameterizedTest
    @ValueSource(strings = {
        "bytes=abc-499",
        "bytes=0-xyz",
        "bytes=abc-xyz",
        "bytes= -499",      // leading space in number
        "bytes=1.5-499"     // decimal
    })
    void givenNonNumericParts_throwsInvalidRangeException(String header) {
        assertThrowsInvalidRange(header);
    }

    // -----------------------------------------------------------------------
    // InvalidRangeException — negative numbers in parts
    // -----------------------------------------------------------------------

    @Test
    void givenNegativeStartValue_throwsInvalidRangeException() {
        // parseLong rejects negatives explicitly
        assertThrowsInvalidRange("bytes=-10-499");
    }

    // -----------------------------------------------------------------------
    // InvalidRangeException — fileSize details preserved
    // -----------------------------------------------------------------------

    @Test
    void givenOutOfRangeHeader_exceptionCarriesFileSize() {
        InvalidRangeException ex = assertThrows(InvalidRangeException.class,
                () -> RangeHeaderParser.parse("bytes=9999-", FILE_SIZE));

        assertEquals(FILE_SIZE, ex.getFileSize());
    }

    // -----------------------------------------------------------------------
    // Helper
    // -----------------------------------------------------------------------

    private static void assertThrowsInvalidRange(String header) {
        assertThrows(InvalidRangeException.class,
                () -> RangeHeaderParser.parse(header, FILE_SIZE));
    }
}
