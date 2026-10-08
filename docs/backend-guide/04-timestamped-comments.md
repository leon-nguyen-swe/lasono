# Guide 04: Comment gắn vị trí trên waveform

> Phase 5 · Cần xong trước: [guide 01](01-domain-events.md), [02](02-likes.md) · (nên sau [03](03-follows.md) để quen khuôn) · Mở khoá: UI "comment nổi trên waveform"
> Khuôn như guide 02-03. Điểm **mới**: kiểm tra giá trị theo dữ liệu của module khác (`durationMs`), quyền xoá hai chiều, hai kiểu phân trang.

## 1. Mục tiêu và nghiệm thu

**Làm gì.** Người nghe viết bình luận *tại một thời điểm của bài* ("1:23 — đoạn này hay quá"). Bình luận hiện thành chấm nhỏ trên waveform
tại đúng vị trí; bấm vào thời gian trong danh sách thì nhảy tới đó. Theo [`api-contract.md` B3](../api-contract.md#b3-comments).

**Xong khi:**

- [ ] `POST /tracks/{id}/comments` → `201`; `positionMs` phải thoả `0 ≤ positionMs ≤ durationMs`; `text` 1-500 ký tự sau khi cắt khoảng trắng.
- [ ] `GET /tracks/{id}/comments?order=position|recent` phân trang keyset đúng cho cả hai thứ tự, kể cả khi nhiều comment trùng `positionMs`.
- [ ] `DELETE …/comments/{commentId}`: tác giả **hoặc** chủ track được xoá; người khác thấy track → `403`; track private của người khác → `404`.
- [ ] `commentCount` của track luôn bằng số dòng `comments` của nó (qua sự kiện, cùng transaction).
- [ ] Xoá track thì xoá luôn comment của nó (mở rộng `TrackDeleted` listener từ guide 02).
- [ ] Track chưa `READY` → `409` khi comment.
- [ ] App chạy với `FAKE_COMMENTS` tắt: comment hiện trên waveform, xoá được.

## 2. Kiến thức cần biết trước

| Khái niệm | Đọc ở đâu |
|-----------|-----------|
| Bất biến (invariant) và "factory method" trong DDD | `Track` và `Email` trong code: hàm tạo kiểm tra, `reconstitute` dựng lại |
| `CHECK`, độ dài `VARCHAR(n)` tính theo **ký tự** | [PostgreSQL: Character types](https://www.postgresql.org/docs/current/datatype-character.html) |
| `String.length()` đếm **đơn vị UTF-16**, không phải ký tự người đọc thấy | [Java: `String.codePointCount`](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/lang/String.html#codePointCount(int,int)) |
| Keyset với giá trị trùng (cần khoá phụ làm "tie-breaker") | `glossary.md` mục keyset; guide 03 trace 3 |
| `ProblemDetail` cho `400` có thông điệp rõ | `TrackExceptionHandler` trong code |

## 3. Quyết định thiết kế

### D1. Kiểm tra `positionMs ≤ durationMs` ở đâu?

| Phương án | Nhận xét |
|-----------|----------|
| Trong use case (`if (positionMs > facts.durationMs()) throw …`) | Dễ, nhưng bất biến nằm ngoài domain; quên ở một use case khác là mất. |
| **Trong domain: `Comment.post(..., trackDurationMs)`** *(khuyến nghị)* | Domain nhận độ dài (một con số) làm tham số; không cần biết `Track`. Mọi cách tạo `Comment` đều phải qua cửa này. Test domain nhanh, không Spring. |
| Chỉ ở DB | Không được: DB không biết độ dài track (module khác, không FK). |

### D2. Ai được xoá?

Quy tắc **thuộc về domain** vì nó là nghiệp vụ, không phải HTTP: `comment.canBeDeletedBy(requester, trackOwner)` trả `true` nếu `requester` là tác giả **hoặc** chủ track.
Use case lấy `trackOwner` từ `TrackFacts.ownerId()`, hỏi domain, và đổi `false` thành `403`.

### D3. Hai thứ tự, hai kiểu cursor

| `order` | Mục đích | Keyset | Điều kiện trang sau |
|---------|----------|--------|---------------------|
| `position` (mặc định) | marker trên waveform | `(position_ms, id)` tăng dần | `(position_ms, id) > (:pos, :id)` |
| `recent` | danh sách dưới waveform | `(created_at, id)` giảm dần | `(created_at, id) < (:createdAt, :id)` |

Cursor mã hoá thêm tiền tố thứ tự (`p:` hoặc `r:` trước phần số) để phát hiện dùng nhầm cursor của order này cho order kia → `400`.
`id` làm khoá phụ vì **nhiều người comment cùng một giây của bài** (cùng `position_ms`); thiếu khoá phụ thì ranh giới trang có thể cắt giữa hai comment trùng vị trí và mất một cái.

### D4. Văn bản thô hay làm sạch?

Lưu nguyên văn (sau `trim`). Chống XSS là việc của nơi **hiển thị**: Flutter `Text` không diễn giải HTML, nên an toàn. Nếu sau này có client web HTML, phải escape ở đó.
Đừng "làm sạch" ở backend rồi lưu: bạn sẽ mất dữ liệu gốc và vẫn chưa an toàn cho mọi nơi hiển thị.

### D5. Độ dài tính bằng gì?

Giới hạn "500 ký tự" nên tính theo **code point** (`text.codePointCount(0, text.length())`), khớp với `VARCHAR(500)` của PostgreSQL. `String.length()` coi mỗi emoji là 2 → người dùng chỉ được 250 emoji, hoặc tệ hơn, 500 emoji (1000 đơn vị) qua mặt kiểm tra `length() <= 500`.

## 4. Vị trí trong kiến trúc

```
com.lasono.engagement
├── domain/
│   ├── Comment, CommentId, CommentText (tuỳ chọn)  ── bất biến + canBeDeletedBy
│   ├── CommentRepository
│   └── exception/ CommentInvalidException (text/position sai)
├── application/
│   ├── port/out/ CommentReader (phân trang) ; TrackLookup (đã có)
│   └── usecase/  PostCommentUseCase, DeleteCommentUseCase, ListCommentsUseCase, CommentResult, CommentPage,
│                 CommentNotFoundException, CommentNotAllowedException, CommentOrder, CommentCursor
├── infrastructure/persistence/ CommentPersistenceAdapter, CommentReaderJdbc
└── presentation/ CommentController (+ EngagementExceptionHandler, PostCommentRequest)
com.lasono.track (thêm)  AdjustTrackCountersUseCase.commentAdded/commentRemoved + listener cho CommentPosted/CommentDeleted
```
Không có phụ thuộc mới giữa module (chỉ dùng `TrackLookup`, `EventPublisher` đã có). ArchUnit không cần quy tắc mới, chỉ cần các quy tắc cũ cho package mới.

## 5. Schema

```sql
-- V13__create_comments.sql
CREATE TABLE comments
(
    id UUID NOT NULL,
    track_id UUID NOT NULL,
    author_id UUID NOT NULL,
    -- Where in the track the comment points, in milliseconds. The upper bound (the length of the track) is checked in the domain.
    position_ms INT NOT NULL,
    -- Named "body" and not "text" so it is never mixed up with PostgreSQL's type of that name. The API calls it "text".
    body VARCHAR(500) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,

    CONSTRAINT pk_comments PRIMARY KEY (id),
    CONSTRAINT ck_comments_position_not_negative CHECK (position_ms >= 0),
    CONSTRAINT ck_comments_body_not_blank CHECK (length(btrim(body)) > 0)
);

-- Markers on the waveform: one track, ordered by position. (id) breaks ties between comments at the same millisecond.
CREATE INDEX idx_comments_track_position ON comments (track_id, position_ms, id);
-- The list under the waveform: one track, newest first.
CREATE INDEX idx_comments_track_created ON comments (track_id, created_at DESC, id DESC);
```

| Chi tiết | Lý do |
|----------|-------|
| Hai index với `track_id` đứng đầu | Cả hai truy vấn đều lọc `track_id = ?` rồi đọc theo thứ tự của index, không sort. Mỗi index phục vụ đúng một `order`. |
| `id` ở cuối mỗi index | Khoá phụ cho keyset, đồng thời cho phép **index-only scan** của điều kiện trang sau. |
| `position_ms INT` | Tối đa `2^31 - 1` ms ≈ 24 ngày > 50 MB MP3 128 kbps ≈ 52 phút. `BIGINT` là thừa. |
| `CHECK` ở DB | Lưới an toàn cuối; domain mới là nơi chặn chính. |
| `created_at` không có `DEFAULT` | Domain truyền thời điểm (từ `Clock`) để response trả đúng giá trị đã lưu. Cắt về micro giây trước khi lưu, như `TrackPersistenceAdapter`. |

Thêm `DELETE FROM comments` vào `cleanTestDatabase()`.

## 6. Các bước code theo thứ tự

### Bước 1. Migration + test hạ tầng
`CommentsMigrationPostgresTest`: `aNegativePositionIsRejected`, `aBlankBodyIsRejected`, `aBodyOver500CharactersIsRejected`.

### Bước 2. Domain (viết test trước, đây là phần giàu logic nhất)
```java
package com.lasono.engagement.domain;

public class Comment {

    public static final int MAX_TEXT_LENGTH = 500;

    // TODO: CommentId id, TrackRef track, UserRef author, int positionMs, String text, Instant createdAt

    /**
     * Creates a new comment.
     * @param trackDurationMs the length of the track, so the position can be checked against it
     * @throws CommentInvalidException when the text is blank or longer than 500 characters,
     *         or the position is negative or after the end of the track
     */
    public static Comment post(
        CommentId id, TrackRef track, UserRef author, int positionMs, String text, long trackDurationMs, Instant now
    ) {
        // TODO: trim the text; blank -> exception; count CODE POINTS (not length()); position in [0, trackDurationMs]
        //       The message of the exception becomes the "detail" of the 400: say the allowed range, e.g.
        //       "positionMs must be between 0 and 213400".
        throw new UnsupportedOperationException("TODO");
    }

    public static Comment reconstitute(/* all fields */) { /* TODO */ return null; }

    /** The author may delete their comment, and so may the owner of the track it is on. */
    public boolean canBeDeletedBy(UserRef requester, UserRef trackOwner) {
        // TODO
        return false;
    }
}
```
Test `CommentTest` (xem mục 8) — viết **hết** trước rồi mới thân `post`. Đây là chỗ tốt để luyện TDD thuần.

### Bước 3. Application
```java
public interface CommentRepository {
    void save(Comment comment);
    Optional<Comment> findById(CommentId id);
    /** True when a row was removed, false when it was already gone (two deletes at the same time). */
    boolean delete(CommentId id);
    int removeAllOfTrack(TrackRef track);
}

public interface CommentReader {
    List<Comment> byPosition(UUID trackId, CommentPosition after, int limit);   // (position_ms, id) ASC
    List<Comment> mostRecent(UUID trackId, RecentPosition after, int limit);   // (created_at, id) DESC
}
```
`PostCommentUseCase.execute(trackId, authorId, positionMs, text)`:
```java
@Transactional
public CommentResult execute(UUID trackId, UUID authorId, int positionMs, String text) {
    // TODO 1: TrackFacts facts = tracks.requireVisible(trackId, authorId);       // 404
    // TODO 2: if (!facts.ready()) throw new TrackNotReadyException(trackId);     // 409
    // TODO 3: Comment c = Comment.post(CommentId.newId(), …, facts.durationMs(), clock.instant().truncatedTo(ChronoUnit.MICROS));  // 400
    // TODO 4: comments.save(c); events.publish(new CommentPosted(…));
    // TODO 5: return CommentResult.from(c);
    throw new UnsupportedOperationException("TODO");
}
```
`DeleteCommentUseCase.execute(trackId, commentId, requesterId)`:
```java
@Transactional
public void execute(UUID trackId, UUID commentId, UUID requesterId) {
    // TODO 1: facts = tracks.requireVisible(trackId, requesterId);                       // 404 (cũng cho track private của người khác)
    // TODO 2: Comment c = comments.findById(...).filter(sameTrack).orElseThrow(CommentNotFoundException);   // 404; comment của track KHÁC cũng là 404
    // TODO 3: if (!c.canBeDeletedBy(requester, new UserRef(facts.ownerId()))) throw new CommentNotAllowedException();   // 403
    // TODO 4: if (comments.delete(c.id())) events.publish(new CommentDeleted(…));       // chỉ phát khi THẬT SỰ xoá được
}
```
Bước 2 có điều kiện `sameTrack`: nếu bỏ, người dùng có thể xoá comment của track khác bằng cách ghép sai `trackId` (một dạng IDOR). Có test cho nó.

`ListCommentsUseCase.execute(trackId, viewerId, orderParam, cursor, limit)`: `404` nếu không thấy track; `order` lạ → `400`; `limit` mặc định 50, tối đa **200**; `limit + 1` dòng; cursor sai order → `400`.
`CommentCursor` dùng lại ý của `TrackCursor`, thêm tiền tố order.

### Bước 4. Infrastructure
- `CommentPersistenceAdapter` (`JdbcTemplate`): `INSERT … (id, track_id, author_id, position_ms, body, created_at)`; `created_at` truyền bằng `OffsetDateTime`. `delete` = `DELETE … WHERE id = ?` trả `> 0`.
- `CommentReaderJdbc`:
  ```sql
  -- order=position, trang sau
  SELECT id, track_id, author_id, position_ms, body, created_at FROM comments
  WHERE track_id = ? AND (position_ms, id) > (?, ?)
  ORDER BY position_ms ASC, id ASC LIMIT ?
  -- order=recent, trang sau
  SELECT … FROM comments WHERE track_id = ? AND (created_at, id) < (?, ?)
  ORDER BY created_at DESC, id DESC LIMIT ?
  ```
  (trang đầu: bỏ điều kiện bộ giá trị).

### Bước 5. Track side + dọn dẹp
`AdjustTrackCountersUseCase.commentAdded/commentRemoved` → `TrackCounterRepository.addToCommentCount(trackId, ±1)` (đã có từ guide 02);
thêm hai `@EventListener` (`CommentPosted`, `CommentDeleted`) vào `TrackCounterListener`.
`RemoveEngagementOfTrackUseCase` (guide 02, bước 7) gọi thêm `comments.removeAllOfTrack(track)`.

### Bước 6. Presentation
```java
@PostMapping("/api/v1/tracks/{id}/comments")
public ResponseEntity<CommentResult> post(@PathVariable("id") UUID id, @RequestBody PostCommentRequest request, Principal principal) {
    // TODO: 201 + body
}
public record PostCommentRequest(Integer positionMs, String text) {}     // Integer, không phải int: thiếu field -> null -> 400 rõ ràng

@GetMapping("/api/v1/tracks/{id}/comments")
public CommentPage list(@PathVariable UUID id, @RequestParam(defaultValue="position") String order, @RequestParam(required=false) String cursor, @RequestParam(required=false) Integer limit, Principal principal) { /* TODO */ }

@DeleteMapping("/api/v1/tracks/{id}/comments/{commentId}")  // 204
```
`EngagementExceptionHandler`: `CommentInvalidException` → `400` (detail = message), `CommentNotAllowedException` → `403`, `CommentNotFoundException` → `404`.
`GET /tracks/**` đã `permitAll` nên route đọc không cần sửa `SecurityConfig` (nhưng viết `SecurityConfigTest.readingCommentsNeedsNoLogin`, `postingNeedsALogin` để khoá). Body thiếu / JSON hỏng → `400` (kiểm tra `HttpMessageNotReadableException`; thêm test).

### Bước 7. ArchUnit, chạy toàn bộ, commit
Commit gợi ý: `feat: comments migration`, `feat: comment domain checks its text and position`, `feat: post comment use case`, `feat: delete comment use case`, `feat: list comments use case`,
`feat: comment persistence`, `feat: comment counter on tracks`, `feat: comment endpoints`, `feat: remove comments when a track is deleted`.

## 7. Trace-through cụ thể

**Dữ liệu:** track `T` có `durationSeconds = 213.4` → `durationMs = 213400`. Chủ track là `Owner`; người comment là `A`, `B`.

### Trace 1. Kiểm tra vị trí

| Request (A) | Kết quả |
|-------------|---------|
| `{"positionMs": 83000, "text": "  Đoạn này hay quá!  "}` | `201`, `text` đã trim: `"Đoạn này hay quá!"`; `commentCount` 0→1 |
| `{"positionMs": 213400, "text": "hết bài"}` | `201` (bằng đúng `durationMs` là hợp lệ) |
| `{"positionMs": 213401, "text": "x"}` | `400 "positionMs must be between 0 and 213400"` |
| `{"positionMs": -1, "text": "x"}` | `400` |
| `{"positionMs": 5000, "text": "   "}` | `400` |
| `{"positionMs": 5000}` (thiếu `text`) | `400` |
| text 500 emoji 😀 | `201` (500 code point). Với 501 emoji → `400`. Dùng `length()` thì 500 emoji = 1000 → bị từ chối nhầm. |

### Trace 2. Keyset theo `position` khi trùng vị trí

Track có 4 comment (id rút gọn để dễ đọc):

| id | position_ms |
|----|-------------|
| `c1` | 0 |
| `c2` | 12000 |
| `c3` | 12000 |
| `c4` | 83000 |

`limit = 2`, `order=position`:
```
Trang 1: WHERE track_id=T ORDER BY position_ms, id LIMIT 3 → c1, c2, c3   → trả [c1, c2] ; nextCursor = p:(12000, c2)
Trang 2: WHERE track_id=T AND (position_ms, id) > (12000, c2) ORDER BY position_ms, id LIMIT 3 → c3, c4
          → trả [c3, c4] ; nextCursor = null
```
Nếu chỉ dùng `position_ms > 12000` (thiếu khoá phụ), `c3` **biến mất** (cùng vị trí với `c2` nhưng không "lớn hơn" 12000). So sánh cả bộ `(position_ms, id)` là lý do cần `id`.

### Trace 3. Ai được xoá?

Track công khai của `Owner`; comment `c9` do `A` viết.

| Người gọi `DELETE …/comments/c9` | Kết quả | Lý do |
|----------------------------------|---------|-------|
| `A` | `204` | tác giả |
| `Owner` | `204` | chủ track |
| `B` (thấy track, không liên quan) | `403` | thấy được nhưng không có quyền |
| `B`, khi `Owner` vừa đổi track sang PRIVATE | `404` | không còn thấy track → không được biết nó tồn tại |
| `A` gọi lần hai | `404` | comment đã hết |
| `A` với `trackId` của **track khác** | `404` | `findById(...).filter(sameTrack)` |

### Trace 4. Hai người xoá cùng comment cùng lúc

`A` và `Owner` cùng gọi `DELETE c9`. Cả hai qua kiểm tra quyền. `DELETE FROM comments WHERE id = c9`: một transaction xoá được (1 dòng), cái kia thấy 0 dòng.
`delete` trả `true` chỉ cho một bên → chỉ một `CommentDeleted` → `comment_count` giảm đúng **một** lần. Bên kia nhận `404`. (Nếu use case phát sự kiện không điều kiện, count sẽ giảm hai lần và CHECK `>= 0` có thể nổ.)

## 8. Test cần viết

| Loại | Test | Ca biên |
|------|------|---------|
| Domain | `CommentTest.post_shouldTrimTheText` | khoảng trắng hai đầu |
| | `...aBlankTextIsRejected` (tham số: `""`, `"   "`, `"\n\t"`) | |
| | `...textOf500CodePointsIsAcceptedAnd501IsNot` | ranh giới 500/501 |
| | `...500EmojiAreAcceptedBecauseTheyAreCountedAsCodePoints` | `length()` vs code point |
| | `...positionEqualToTheDurationIsAccepted`, `...positionAfterTheDurationIsRejected`, `...aNegativePositionIsRejected`, `...positionZeroIsAccepted` | biên [0, duration] |
| | `...theMessageNamesTheAllowedRange` | thông điệp cho 400 |
| | `canBeDeletedBy_theAuthorTheTrackOwnerYesAStrangerNo` | bảng 3 ca |
| Use case | `PostCommentUseCaseTest.execute_shouldStoreAndPublishCommentPosted` | |
| | `...onAnInvisibleTrack_shouldBeNotFound`, `...onATrackThatIsNotReady_shouldBeConflict` | 404, 409 |
| | `...shouldUseTheDurationOfTheTrack` | fake `TrackLookup` trả duration khác nhau |
| | `DeleteCommentUseCaseTest` — tác giả / chủ track / người lạ (403) / comment của track khác (404) / comment không tồn tại (404) / `delete` trả `false` ⇒ không phát sự kiện | |
| | `ListCommentsUseCaseTest` — order mặc định, order lạ → 400, `limit` > 200 bị cắt, cursor của order kia → 400, trang cuối | |
| Cursor | `CommentCursorTest` — round-trip cả hai kiểu, tiền tố sai, base64 hỏng | khớp `TrackCursorTest` |
| postgres | `CommentReaderJdbcPostgresTest.byPositionKeepsCommentsAtTheSamePositionWhenPagingBetweenThem` | **trace 2** (4 comment, limit 2) |
| | `...mostRecentIsNewestFirst` | |
| | `CommentCountPostgresTest.theCounterMatchesTheRowsAfterPostsAndDeletes` | `comment_count == COUNT(*)` |
| | `...twoDeletesOfTheSameCommentDecreaseTheCounterOnce` | **trace 4** |
| | `...deletingATrackRemovesItsComments` | dọn dẹp |
| | `...aBodyOver500CharactersIsRejectedByTheDatabase` | VARCHAR(500) |
| HTTP | `CommentOverHttpPostgresTest` — luồng đầy đủ: đăng nhập 2 user, upload, đợi READY, post, list cả 2 order, 403/404/204, 401 | |
| Security | `readingCommentsNeedsNoLogin`, `postingAndDeletingNeedALogin` | |

## 9. Lỗi thường gặp

| Lỗi | Dấu hiệu | Sửa |
|-----|----------|-----|
| Dùng `String.length()` để giới hạn 500 | Emoji bị đếm 2, qua mặt hoặc bị chặn nhầm | `codePointCount`. |
| `int positionMs` trong request record | Thiếu field cho ra `0` (comment ở giây 0!) | Dùng `Integer`; `null` → `400`. |
| Xoá comment của track khác | Người dùng ghép `trackId` này với `commentId` kia | Lọc `sameTrack`; test. |
| Mất comment ở ranh giới trang | Hai comment cùng vị trí, chỉ thấy một | Keyset phải so sánh cả `(position_ms, id)`. |
| `comment_count` giảm hai lần | `CHECK` đỏ, hoặc count thấp hơn số dòng | Chỉ phát `CommentDeleted` khi `delete` trả `true`. |
| `403` cho track private | Lộ sự tồn tại | `requireVisible` trước mọi kiểm tra quyền. |
| Cột tên `text` | Lỗi cú pháp lạ trong vài truy vấn | Đặt tên `body`. |
| `durationMs` lệch 1 | Comment ở cuối bài bị từ chối | `Math.round(durationSeconds * 1000)`, không `(long)`. |
| Comment trên track `PROCESSING` | Không có `durationMs` để kiểm | `409` trước khi gọi domain. |
| Trả `createdAt` khác giá trị đã lưu | Test so sánh lệch micro giây | `clock.instant().truncatedTo(MICROS)` trước khi lưu và trả. |

## 10. Kiểm tra thủ công

Dùng lại biến của guide 02; `ID` là track đã `READY` (nhớ `durationSeconds`). Lấy `DUR_MS=$(curl -s $BASE/tracks/$ID | python3 -c "import sys,json;print(round(json.load(sys.stdin)['durationSeconds']*1000))")`.

| # | Lệnh | Kỳ vọng |
|---|------|---------|
| 1 | `curl -s -X POST $BASE/tracks/$ID/comments -H "Authorization: Bearer $TOKEN_B" -H 'Content-Type: application/json' -d '{"positionMs":1000,"text":"  Mở đầu hay  "}'` | `201`, `text:"Mở đầu hay"`, `authorId` của B |
| 2 | cùng lệnh với `"positionMs": '$((DUR_MS+1))` | `400` nêu khoảng hợp lệ |
| 3 | `-d '{"positionMs":1000}'` | `400` |
| 4 | không token | `401` |
| 5 | `curl -s "$BASE/tracks/$ID/comments"` (không token) | `{"items":[…],"nextCursor":null}` sắp theo `positionMs` |
| 6 | `curl -s "$BASE/tracks/$ID/comments?order=recent&limit=1"` | một item, `nextCursor` khác `null` nếu có ≥ 2 comment |
| 7 | dùng cursor của `order=recent` với `order=position` | `400` |
| 8 | `curl -s "$BASE/tracks/$ID" \| json "['commentCount']"` | bằng số comment |
| 9 | A (không phải tác giả, không phải chủ) `DELETE …/comments/$CID` | `403`; chủ track hoặc tác giả → `204`; gọi lại → `404` |
| 10 | Đổi track sang `PRIVATE` rồi người lạ `GET …/comments` | `404` |
| 11 | SQL: `SELECT comment_count, (SELECT count(*) FROM comments WHERE track_id=t.id) FROM tracks t WHERE id='$ID'` | hai số bằng nhau |

**Kịch bản UI** (tắt `FAKE_COMMENTS`): phát một track, tới 0:12 bấm ô comment (hiện "Bình luận tại 0:12"), gõ nội dung, gửi → một avatar nhỏ xuất hiện dưới waveform tại
đúng vị trí, rê chuột/phát tới đó thì nội dung nổi lên; bấm thời gian trong danh sách → nhảy tới; xoá comment của mình → avatar biến mất và số comment giảm;
đăng nhập user khác → không có nút xoá comment của người khác (trừ khi là chủ track).

## 11. Câu hỏi tự kiểm tra

<details><summary>Hiện đáp án gợi ý sau khi tự trả lời</summary>

1. **Vì sao kiểm tra `positionMs ≤ durationMs` nằm trong domain mà `durationMs` đến từ module khác?** Domain nhận con số làm tham số, nên vẫn thuần; bất biến được chặn ở một cửa duy nhất.
2. **Vì sao keyset theo `position` cần `id`?** Nhiều comment cùng `position_ms`; so sánh bộ `(position_ms, id)` mới không bỏ sót.
3. **Hai người xoá cùng một comment. Bộ đếm giảm mấy lần? Vì sao?** Một; chỉ bên `delete` trả `true` mới phát sự kiện.
4. **Vì sao `403` cho người lạ nhưng `404` khi track private?** Track public ai cũng thấy nên không có gì để giấu; track private thì `403` lộ sự tồn tại.
5. **Vì sao đếm bằng code point?** Khớp cách PostgreSQL đếm `VARCHAR(n)` và cách người dùng nhìn thấy; `length()` đếm đơn vị UTF-16.
6. **IDOR là gì và `sameTrack` chống nó thế nào?** Truy cập đối tượng bằng id mà không kiểm tra quyền sở hữu/phạm vi; ta kiểm tra comment thuộc đúng track đã được kiểm tra quyền.
7. **Vì sao request dùng `Integer` thay vì `int`?** `int` biến thiếu field thành `0` im lặng.
8. **Nếu track có 5000 comment thì UI làm gì?** Chỉ tải 200 comment đầu theo vị trí cho marker (giới hạn đã ghi); danh sách bên dưới tải thêm theo `order=recent`.

</details>

## 12. Bài tập mở rộng

1. **Trả lời comment (thread):** thêm `parent_id`; quyết định giới hạn một cấp hay nhiều cấp và ảnh hưởng đến `commentCount` và keyset.
2. **Giới hạn tần suất:** tối đa 5 comment mỗi phút mỗi user. Thử bằng truy vấn đếm trong cùng transaction rồi so với bucket token (chuẩn bị cho Phase 8).
