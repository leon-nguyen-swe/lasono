# Phase 3, PR 1: Trạng thái `FAILED` cho Track và AudioResource

> Branch: `feat/track-processing-failed`. Làm theo TDD: mỗi task có một test RED, code tối thiểu, rồi GREEN.
> Lệnh chạy test: `cd backend && ./gradlew test --tests '<tên lớp test>'`.

## Vì sao cần `FAILED`?

Ở Phase 3, việc xử lý audio (đọc thời lượng, tạo waveform, transcode) chạy nền bằng worker. Việc này có thể thất bại: file hỏng, FFmpeg lỗi. Khi đã thử lại hết số lần cho phép, track không thể ở `PROCESSING` mãi mãi, vì người dùng sẽ thấy "đang xử lý" vô hạn. Ta cần một trạng thái cuối nói rõ "xử lý thất bại".

Vòng đời mong muốn của `AudioResource`:

```text
CREATED → UPLOADED → PROCESSING → READY
                          └──────→ FAILED
```

Đây là một **state machine** (máy trạng thái): chỉ một số chuyển trạng thái là hợp lệ, và quy tắc này nằm trong **Domain**, không nằm ở controller hay use case.

## Quyết định đã đổi so với kế hoạch

Kế hoạch ban đầu muốn `startProcessing()` chấp nhận cả `PROCESSING` để retry không bị lỗi. Nhưng test `shouldRejectStartingProcessingFromProcessing` đang khẳng định điều ngược lại, và chưa có use case nào cần. Theo YAGNI, mục này được dời sang PR 5 (worker), nơi nó thực sự cần.

---

## Task 1: `AudioResource` chuyển từ `PROCESSING` sang `FAILED`

**Hành vi kiểm tra.** Khi một audio resource đang `PROCESSING` mà xử lý thất bại, gọi `processingFailed()` thì status thành `FAILED`. Khi thất bại, resource vẫn giữ `originalAudio` nhưng **không có** `streamingAudio`, `audioDuration` và `waveform` (đều `null`), vì chúng chưa bao giờ được tạo.

**Test.** `AudioResourceTest.shouldTransitionFromProcessingToFailed`

**RED (lỗi biên dịch).** Chạy test trước khi có code:

```text
AudioResourceTest.java:137: error: cannot find symbol
    symbol:   variable FAILED     location: class AudioResourceStatus
AudioResourceTest.java:135: error: cannot find symbol
    symbol:   method processingFailed()   location: variable resource of type AudioResource
> Task :compileTestJava FAILED
```

Đây là *compile-time RED*: test dùng thứ chưa tồn tại, nên chưa chạy được. Lỗi đúng ý định (thiếu hành vi), không phải lỗi cú pháp hay cấu hình.

**Code tối thiểu.**
- `AudioResourceStatus`: thêm giá trị `FAILED`.
- `AudioResource`: thêm `void processingFailed() { this.status = AudioResourceStatus.FAILED; }` (package-private, như `startProcessing` và `processingCompleted`, nên chỉ `Track` gọi được).
- Chưa có kiểm tra "chỉ fail từ `PROCESSING`" vì chưa có test đòi nó. Việc đó thuộc Task 2.

**GREEN.** `AudioResourceTest`: 18 test, 0 lỗi, 0 bị bỏ qua, và test mới có trong báo cáo. 17 test cũ vẫn xanh.

**Được đảm bảo.** Có một đường đi hợp lệ tới `FAILED` và `FAILED` không chứa dữ liệu xử lý dở.

**Không cần migration.** Cột `audio_resources.status` là `VARCHAR(50)` lưu tên enum, nên `FAILED` lưu được ngay.

---

## Task 2: `AudioResource` từ chối `processingFailed()` khi không ở `PROCESSING`

**Hành vi kiểm tra.** Chỉ việc đang xử lý mới có thể thất bại. Gọi `processingFailed()` từ `CREATED`, `UPLOADED`, `READY` hoặc `FAILED` phải ném `AudioResourceInvalidStateException` và giữ nguyên status.

**Test.** Bốn test trong `AudioResourceTest`: `shouldRejectFailingProcessingFromCreated`, `...FromUploaded`, `...FromReady`, `...FromFailed`.

**RED (lỗi lúc chạy).** Code biên dịch được, test chạy, 4 test lỗi:

```text
22 tests completed, 4 failed
AssertionFailedError: Expected AudioResourceInvalidStateException to be thrown, but nothing was thrown.
```

Ý nghĩa: Task 1 chỉ đặt `FAILED` vô điều kiện, nên một resource `READY` bị đổi thành `FAILED` mà không có lỗi nào. Đó là lỗ hổng của state machine.

**Code tối thiểu.** Thêm guard clause đầu `processingFailed()`:

```java
if (this.status != AudioResourceStatus.PROCESSING) {
    throw new AudioResourceInvalidStateException("Expected state: PROCESSING\nActual state: " + this.status);
}
```

**GREEN.** `AudioResourceTest`: 22 test, 0 lỗi, 0 bị bỏ qua.

**Được đảm bảo.** `FAILED` chỉ đạt được từ `PROCESSING`, và là trạng thái cuối: không thể fail lần hai, và `READY` không thể đổi thành `FAILED`.

**Khái niệm: guard clause.** Kiểm tra điều kiện sai ở đầu method và ném lỗi ngay, thay vì lồng `if`. Cùng mẫu với `startProcessing` và `processingCompleted`. Giữ quy tắc state machine ngay trong entity nghĩa là không có chỗ nào khác có thể "lách" quy tắc.

---

## Task 3: `Track.processingFailed()` chuyển `PROCESSING → FAILED`

**Hành vi kiểm tra.** Khi xử lý thất bại, gọi `track.processingFailed()` thì cả `TrackStatus` (cái người dùng thấy) lẫn `AudioResourceStatus` (Task 1 và 2) cùng thành `FAILED`. Hai trạng thái luôn đi cùng nhau.

**Test.** `TrackTest.shouldMoveTrackAndAudioResourceToFailedWhenProcessingFails`

**RED (lỗi biên dịch).**

```text
TrackTest.java:90: error: cannot find symbol  symbol: method processingFailed()  location: variable track of type Track
TrackTest.java:92: error: cannot find symbol  symbol: variable FAILED             location: class TrackStatus
> Task :compileTestJava FAILED
```

`AudioResourceStatus.FAILED` không báo lỗi vì đã có từ Task 1.

**Code tối thiểu.**
- `TrackStatus`: thêm `FAILED`.
- `Track`: thêm `public void processingFailed() { audioResource.processingFailed(); this.status = TrackStatus.FAILED; }`.
- `Track` chưa tự kiểm tra trạng thái của chính nó trong method này. Việc đó thuộc Task 4.

**GREEN.** `TrackTest`: 5 test, `AudioResourceTest`: 22 test, đều 0 lỗi.

**Được đảm bảo.** Track và audio resource luôn cùng chuyển sang `FAILED`.

**Khái niệm: thứ tự các lệnh bảo vệ tính nhất quán.** `audioResource.processingFailed()` chạy **trước** khi đặt `this.status`. Nếu audio resource từ chối (sai trạng thái), exception thoát ra trước dòng gán status, nên track không bị đổi trạng thái một nửa.

**Không cần migration.** `tracks.status` là `VARCHAR(50)` lưu tên enum.

---

## Task 4: `Track` không cho `READY → FAILED` và không cho `FAILED → READY`

**Hành vi kiểm tra.** `READY` và `FAILED` là trạng thái cuối. Track phải ném `TrackInvalidStateException` (cùng loại với `processingCompleted`) khi:
1. đang `READY` mà gọi `processingFailed()`,
2. đã `FAILED` mà gọi `processingFailed()` lần nữa,
3. đã `FAILED` mà gọi `processingCompleted(...)`.

**Test.** `TrackTest`: `shouldRejectFailingProcessingWhenTrackIsReady`, `shouldRejectFailingProcessingWhenTrackIsAlreadyFailed`, `shouldRejectCompletingProcessingWhenTrackHasFailed`.

**RED (lỗi lúc chạy, 2 trong 3 test).**

```text
8 tests completed, 2 failed
expected: TrackInvalidStateException but was: AudioResourceInvalidStateException
```

Đây là RED tinh tế: track vẫn bị từ chối nhờ guard của `AudioResource` (Task 2), nhưng exception thuộc về tầng audio thay vì tầng `Track`. Hai method của cùng một class sẽ báo cùng một lỗi trạng thái bằng hai kiểu exception khác nhau, và tầng HTTP phải xử lý cả hai.

Test 3 **xanh ngay từ đầu** vì `processingCompleted` đã có guard `status != PROCESSING`. Nó là *test bảo vệ* (regression guard): khóa quy tắc "FAILED là trạng thái cuối" để sau này không ai vô tình mở lại. Một test xanh ngay không chứng minh code mới đúng, nên ở đây ta chỉ dựa vào test 1 và 2 làm bằng chứng cho code mới.

**Code tối thiểu.** Thêm guard của `Track` vào đầu `processingFailed()`:

```java
if (this.status != TrackStatus.PROCESSING) {
    throw new TrackInvalidStateException("Expected track state: PROCESSING\nActual track state: " + this.status);
}
```

**GREEN.** `./gradlew test`: 218 test, 0 lỗi, 0 bị bỏ qua (trước PR là 209; thêm 9 test: 1 + 4 + 1 + 3).

**Được đảm bảo.** `Track` báo lỗi trạng thái nhất quán bằng `TrackInvalidStateException`, và không có đường đi giữa `READY` và `FAILED`.

---

## Tổng kết PR 1

State machine của `Track` sau PR này (`AudioResource` đi song song với nó):

```text
Track:          PROCESSING ──→ READY
                    └───────→ FAILED
AudioResource:  CREATED → UPLOADED → PROCESSING → READY
                                          └─────→ FAILED
```

| Task | Test mới | Loại RED |
|---|---|---|
| 1 | 1 | lỗi biên dịch |
| 2 | 4 | lỗi lúc chạy: không ném exception |
| 3 | 1 | lỗi biên dịch |
| 4 | 3 (2 RED, 1 bảo vệ) | lỗi lúc chạy: sai loại exception |

**Việc dời sang PR 5:** cho phép `startProcessing()` chạy lại khi retry (xem phần "Quyết định đã đổi").

**Chưa làm ở PR này (có chủ đích):** lưu lý do thất bại (sẽ nằm ở `last_error` của bảng job, PR 2), hiển thị `FAILED` ở API và Flutter (PR 7 và 8).
