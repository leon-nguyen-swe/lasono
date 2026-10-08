# Guide 05: Feed (và danh sách track đã like), module `discovery`

> Phase 6 · Cần xong trước: [guide 02](02-likes.md), [03](03-follows.md) · Mở khoá: UI Feed và tab Likes của Profile
> Guide này dựng module **chỉ đọc** `discovery` và dạy cách đọc một kế hoạch truy vấn (`EXPLAIN ANALYZE`).

## 1. Mục tiêu và nghiệm thu

**Làm gì.** `GET /feed`: các track mới của những người mình đang follow. `GET /users/{id}/likes`: các track một user đã like. Cả hai trả
**Track tóm tắt (mới)** của [`api-contract.md` B0](../api-contract.md#b0-các-kiểu-dùng-chung), phân trang keyset
([B4](../api-contract.md#b4-feed), [B1](../api-contract.md#b1-likes)).

**Xong khi:**

- [ ] Feed chỉ có track `READY` + `PUBLIC` của người mình follow; **không** có track của chính mình, của người không follow, track private hay đang xử lý.
- [ ] Không follow ai → `200 {"items":[],"nextCursor":null}`. Chưa đăng nhập → `401`.
- [ ] Phân trang không trùng/sót khi có track mới đăng giữa hai trang.
- [ ] `GET /users/{id}/likes` sắp theo **thời điểm like**, chỉ gồm track người xem được thấy; user lạ → `404`.
- [ ] Mỗi item có `likeCount`, `commentCount`, `isLikedByMe`, `createdAt` đúng.
- [ ] Có số đo `EXPLAIN ANALYZE` trước/sau index trên dữ liệu lớn, ghi lại trong PR (bạn tự viết).
- [ ] App chạy với `FAKE_FEED` tắt.

## 2. Kiến thức cần biết trước

| Khái niệm | Đọc ở đâu |
|-----------|-----------|
| Cách đọc `EXPLAIN (ANALYZE, BUFFERS)` | [PostgreSQL: Using EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html) |
| Index nhiều cột và thứ tự `ASC/DESC` | [PostgreSQL: Multicolumn indexes](https://www.postgresql.org/docs/current/indexes-multicolumn.html), [Indexes and ORDER BY](https://www.postgresql.org/docs/current/indexes-ordering.html) |
| Index riêng phần (partial index) | [PostgreSQL: Partial indexes](https://www.postgresql.org/docs/current/indexes-partial.html) |
| Các kiểu JOIN của planner (Nested Loop, Hash, Merge) | [PostgreSQL: Planner/Optimizer](https://www.postgresql.org/docs/current/planner-optimizer.html) |
| Keyset pagination | guide 03 trace 3; `TrackCursor` + `TrackJpaRepository` trong code |
| Fan-out on read / on write | `glossary.md` |
| CQRS-lite (tách mô hình ghi và mô hình đọc) | tìm "CQRS read model" |

## 3. Quyết định thiết kế

### D1. Feed: fan-out on read hay on write?

| | Fan-out **on read** *(khuyến nghị cho v1.0)* | Fan-out **on write** |
|---|---|---|
| Ý tưởng | Khi mở feed: JOIN `follows` với `tracks` và sắp theo thời gian | Khi đăng track: chép một dòng vào `feed_items` của **mỗi follower** |
| Đọc | Một truy vấn phức tạp hơn; chi phí ∝ số người follow × track của họ | Rất rẻ: đọc một bảng đã sắp sẵn của mình |
| Ghi | Không thêm | Đắt: 10 000 follower = 10 000 dòng mỗi lần đăng ("celebrity problem") |
| Nhất quán | Luôn đúng ngay (follow/unfollow, đổi private, xoá track) | Phải đồng bộ lại khi unfollow, đổi visibility, xoá; follow mới cần backfill |
| Độ phức tạp | Thấp | Cao (job nền, backfill, xử lý lỗi một phần) |

Dự án chưa có số đo cho thấy cần fan-out on write; PROJECT_STATUS cũng hoãn tối ưu cho đến Phase 8. **On read, đo, rồi quyết định.** Nếu Phase 7 (k6) cho thấy feed là điểm nghẽn, đó là lúc cân nhắc.
Phương án lai (on read cho người có nhiều follower, on write cho người ít follower) nằm ở bài tập mở rộng.

### D2. Truy vấn feed nằm ở đâu và có được JOIN chéo module không?

Feed cần dữ liệu của **ba** module (`follows` của engagement, `tracks` + `audio_resources` của track, `likes` của engagement). Nếu ghép trong Java (gọi use case từng module):
1. lấy danh sách followee (có thể hàng nghìn id),
2. lấy track của họ,
3. sắp, cắt trang…

thì không thể phân trang đúng và hiệu quả (lấy hết rồi cắt). Đây là bài toán điển hình cho **read model**: một mô hình đọc tối ưu cho một màn hình, tách khỏi mô hình ghi.

| Phương án | Nhận xét |
|-----------|----------|
| Ghép trong Java qua use case từng module | Giữ ranh giới tuyệt đối nhưng không phân trang được, N+1. |
| **Module `discovery` chỉ đọc, JOIN bảng bằng SQL** *(khuyến nghị)* | Một truy vấn, phân trang đúng. **Giá phải trả:** `discovery` phụ thuộc *schema* của các module khác (đổi tên cột ở `tracks` là gãy `discovery`), dù không import class nào. |
| Bảng phi chuẩn hoá `feed_items` | Chính là fan-out on write. |

Chấp nhận giá đó bằng **ba rào chắn**, và ghi chúng thành quy tắc dự án:
1. `discovery` **chỉ `SELECT`**, không bao giờ ghi vào bảng của module khác.
2. SQL chỉ nằm trong `discovery.infrastructure.persistence`; mỗi câu SQL có comment liệt kê bảng nó đọc.
3. Mỗi truy vấn có `postgresTest` với dữ liệu thật: nếu `track` đổi schema, test của `discovery` đỏ ngay.

### D3. Bộ lọc hiển thị nằm trong SQL

Giống Phase 4 (`TrackJpaRepository.findNewest`): điều kiện `visibility`, `status` nằm **trong câu SQL**, không lọc sau. Lọc sau làm trang thiếu phần tử và con trỏ trỏ sai chỗ.

### D4. Một record cho "Track tóm tắt (mới)"

`discovery` không import `TrackListItemResult` của `track` (quy tắc module), nên có record riêng `TrackItemResult` cùng hình dạng JSON. Hai bản sao là giá của việc tách module; hợp đồng ([B0](../api-contract.md#b0-các-kiểu-dùng-chung)) là thứ giữ chúng khớp nhau, và một `postgresTest` so sánh tên field của hai bên (bài tập 12.2).

## 4. Vị trí trong kiến trúc

```
com.lasono.discovery           (KHÔNG có lớp domain: không có quy tắc nghiệp vụ nào cần bảo vệ, chỉ đọc)
├── application/
│   ├── port/out/ FeedReader, LikedTracksReader
│   └── usecase/  GetFeedUseCase, ListLikedTracksUseCase, TrackItemResult, TrackPage, PagePosition, PageCursor,
│                 InvalidPageRequestException, UserNotFoundException
├── infrastructure/persistence/ FeedReaderJdbc, LikedTracksReaderJdbc
└── presentation/ FeedController, LikedTracksController, DiscoveryExceptionHandler
```
Phụ thuộc: `discovery` **không import** `track`, `identity`, `engagement`, `shared` (cũng không cần `EventPublisher`). Ngược lại không module nào import `discovery`.

**ArchUnit.** Đăng ký `DISCOVERY = "com.lasono.discovery"` và bốn cặp:
`moduleDoesNotDependOn(DISCOVERY, TRACK|IDENTITY|ENGAGEMENT)` và `moduleDoesNotDependOn(TRACK|IDENTITY|ENGAGEMENT, DISCOVERY)`.
Lưu ý: các quy tắc `domainIsFrameworkFree(root)`, `domainDoesNotDependOnOtherLayers(root)` chọn các lớp trong `root..domain..`; `discovery` không có lớp nào ở đó. ArchUnit mặc định **báo lỗi khi quy tắc không kiểm tra được lớp nào** ("failed to check any classes").
Chỉ áp dụng cho `discovery` các quy tắc `applicationDoesNotDependOnPresentation` và `onlyInfrastructureUsesInfrastructure`; ghi lý do trong comment test.

## 5. Schema

Không có bảng mới. Có thể cần **một index**; đừng tạo trước khi đo (mục 6, bước 6).

```sql
-- V14__index_public_ready_tracks_for_feed.sql  (CHỈ tạo nếu EXPLAIN ANALYZE cho thấy lợi ích)
-- The feed reads only public tracks that are ready, newest first, for a set of owners.
CREATE INDEX idx_tracks_feed ON tracks (owner_id, created_at DESC, id DESC)
    WHERE visibility = 'PUBLIC' AND status = 'READY';
```
`idx_tracks_owner_created` (V12, guide 03) đã phục vụ "track của một owner theo thứ tự"; index riêng phần này **nhỏ hơn** và đã loại sẵn track private/đang xử lý, nên mỗi lần quét ít trang đĩa hơn. Bạn sẽ tự xác nhận bằng số đo.
Index cho `likes` (`idx_likes_user_created`) đã có từ guide 02.

## 6. Các bước code theo thứ tự

### Bước 1. Khung module và ArchUnit (RED trước)
Thêm `DISCOVERY` vào `ArchitectureTest.importPackages(...)` và các quy tắc ở mục 4; chạy → RED vì chưa có lớp nào (`discoveryClassesAreImported`); tạo khung package và lớp rỗng đầu tiên → GREEN.

### Bước 2. Cursor và phân trang
`PagePosition(Instant createdAt, UUID id)` và `PageCursor.encode/decode` — **lần thứ ba** bạn chép `TrackCursor` (track, engagement, discovery). Đây là lúc rút ra `com.lasono.shared.paging`:
làm một commit refactor riêng "đưa cursor dùng chung vào shared", giữ `TrackCursorTest` xanh. (Nếu ngại động vào `track`, vẫn có thể chép lần này và ghi TODO.)

### Bước 3. Port và SQL
```java
public interface FeedReader {
    /** Tracks of the people {@code viewerId} follows, newest first, strictly after {@code after} (null = from the newest). */
    List<TrackItemResult> feedOf(UUID viewerId, PagePosition after, int limit);
}

public interface LikedTracksReader {
    boolean userExists(UUID userId);
    /** Tracks {@code subjectId} liked, most recently liked first. Only tracks {@code viewerId} may see (viewerId may be null). */
    List<LikedTrack> likedBy(UUID subjectId, UUID viewerId, PagePosition after, int limit);
}
public record LikedTrack(TrackItemResult track, Instant likedAt) {}
```
SQL của feed (đọc: `follows`, `tracks`, `audio_resources`, `likes`):
```sql
-- Reads: follows (engagement), tracks and audio_resources (track), likes (engagement).
SELECT t.id, t.owner_id, t.title, t.description, t.visibility, t.status, t.created_at,
       t.like_count, t.comment_count, ar.duration_ms,
       EXISTS (SELECT 1 FROM likes l WHERE l.user_id = :viewer AND l.track_id = t.id) AS liked_by_me
FROM follows f
JOIN tracks t          ON t.owner_id = f.followee_id
JOIN audio_resources ar ON ar.track_id = t.id
WHERE f.follower_id = :viewer
  AND t.visibility = 'PUBLIC' AND t.status = 'READY'
  AND (t.created_at, t.id) < (:createdAt, :id)           -- bỏ dòng này ở trang đầu
ORDER BY t.created_at DESC, t.id DESC
LIMIT :limit
```
SQL của danh sách like (đọc: `likes`, `tracks`, `audio_resources`, `users`):
```sql
SELECT t.id, t.owner_id, t.title, t.description, t.visibility, t.status, t.created_at,
       t.like_count, t.comment_count, ar.duration_ms,
       EXISTS (SELECT 1 FROM likes m WHERE m.user_id = :viewer AND m.track_id = t.id) AS liked_by_me,
       l.created_at AS liked_at
FROM likes l
JOIN tracks t           ON t.id = l.track_id
JOIN audio_resources ar ON ar.track_id = t.id
WHERE l.user_id = :subject
  AND (t.visibility = 'PUBLIC' OR t.owner_id = :viewer)
  AND (l.created_at, l.track_id) < (:likedAt, :trackId)  -- bỏ ở trang đầu
ORDER BY l.created_at DESC, l.track_id DESC
LIMIT :limit
```
Người xem chưa đăng nhập: dùng `new UUID(0, 0)` như `TrackSummaryPersistenceAdapter.viewerOrNobody`.
Cursor của danh sách like mang `(liked_at, track_id)`, **không phải** `(created_at, id)` của track.
Dùng `NamedParameterJdbcTemplate`; đọc thời gian bằng `rs.getObject("created_at", OffsetDateTime.class).toInstant()`; truyền lại bằng `OffsetDateTime`.

### Bước 4. Use case
`GetFeedUseCase.execute(viewerId, cursor, limit)`: giải mã cursor (`400` nếu hỏng), `limit` mặc định 20 tối đa 50 (`< 1` → `400`), lấy `limit + 1`, cắt, `nextCursor` từ phần tử cuối **của trang**.
`ListLikedTracksUseCase`: thêm `userExists` → `404`. Khuôn y hệt `ListTracksUseCase.page` (mở ra đối chiếu). Test bằng fake `InMemoryFeedReader` (trả danh sách cố định), **không** Mockito.

### Bước 5. Presentation và Security
```java
@GetMapping("/api/v1/feed")
public TrackPage feed(@RequestParam(required = false) String cursor, @RequestParam(required = false) Integer limit, Principal principal) { /* TODO */ }

@GetMapping("/api/v1/users/{id}/likes")
public TrackPage likes(@PathVariable("id") UUID id, @RequestParam(required = false) String cursor,
                       @RequestParam(required = false) Integer limit, Principal principal) { /* TODO: principal may be null */ }
```
`SecurityConfig`: **không** thêm gì cho `/feed` (mặc định `authenticated()` → `401` cho khách; test để khoá);
thêm `.requestMatchers(HttpMethod.GET, "/api/v1/users/*/likes").permitAll()` (và test).

### Bước 6. Đo bằng `EXPLAIN ANALYZE` (đây là phần học chính)
Trong một database **tạm** (đừng dùng `lasono` hay `lasono_test`): `CREATE DATABASE lasono_perf TEMPLATE lasono;` rồi chạy bootRun với `--spring.datasource.url=…lasono_perf` một lần để Flyway tạo schema,
tắt backend, và nạp dữ liệu:

```sql
-- 1000 người dùng, 100 000 track, mỗi track có audio_resources, một viewer follow 50 người
INSERT INTO users (id, email, display_name, password_hash)
SELECT gen_random_uuid(), 'u'||g||'@perf.test', 'User '||g, '!' FROM generate_series(1, 1000) g;

CREATE TEMP TABLE u AS SELECT row_number() OVER (ORDER BY id) AS n, id FROM users;

INSERT INTO tracks (id, owner_id, title, description, visibility, status, created_at)
SELECT gen_random_uuid(), u.id, 'Track '||g, '', CASE WHEN g % 10 = 0 THEN 'PRIVATE' ELSE 'PUBLIC' END,
       'READY', now() - (g * 30 || ' seconds')::interval
FROM generate_series(1, 100000) g JOIN u ON u.n = 1 + (g % 1000);

INSERT INTO audio_resources (id, track_id, status, duration_ms)
SELECT gen_random_uuid(), id, 'READY', 180000 FROM tracks;

-- viewer = người dùng số 1; follow 50 người dùng số 2..51
INSERT INTO follows (follower_id, followee_id)
SELECT (SELECT id FROM u WHERE n = 1), id FROM u WHERE n BETWEEN 2 AND 51;

ANALYZE;
```
Rồi chạy truy vấn feed (thay `:viewer`, bỏ điều kiện cursor) với `EXPLAIN (ANALYZE, BUFFERS)`:
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.id, ... (như trên) ... LIMIT 21;
```
**Thí nghiệm gợi ý** (ghi lại thời gian thực thi, loại quét, `Rows Removed by Filter`, `Sort Method` mỗi lần):
1. Chỉ có `idx_tracks_created_at_id` (xoá tạm các index V12/V14: `DROP INDEX …` trong DB tạm).
2. Thêm `idx_tracks_owner_created` (V12).
3. Thêm `idx_tracks_feed` (V14).
4. Cho viewer follow 1 người (thay vì 50) và follow 900 người: kế hoạch có đổi không?
5. `SET enable_seqscan = off;` chỉ để xem planner *có thể* dùng index nào; đừng đưa vào code.

Câu hỏi cần trả lời: Nested Loop từ `follows` hay quét ngược `idx_tracks_created_at_id` rồi lọc? Có `Sort` toàn bộ hay `top-N heapsort`? Chi phí tăng thế nào theo số followee?
Viết kết luận 5 dòng vào mô tả PR (khớp quy ước dự án: RED/GREEN ≤ 5 dòng trong PR, không tạo file riêng).

### Bước 7. Chạy toàn bộ, commit
Commit gợi ý: `feat: discovery module skeleton and architecture rules`, `feat: keyset cursor shared by the modules`, `feat: feed reader`, `feat: feed endpoint`, `feat: liked tracks reader and endpoint`, `feat: index for the feed` (nếu có).

## 7. Trace-through cụ thể

**Dữ liệu:** `V` follow `U1`, `U2`; không follow `U3`. `limit = 2`. Các track (mới → cũ):

| Track | Chủ | Thời điểm | Trạng thái | Vào feed của V? |
|-------|-----|-----------|------------|-----------------|
| `T5` | U3 | 2026-10-08T12:50:00Z | READY, PUBLIC | Không (không follow U3) |
| `T1` (`0c1f2a3b-…`) | U1 | 2026-10-08T12:34:56.789012Z | READY, PUBLIC | **Có** |
| `T6` | U1 | 2026-10-08T12:00:00Z | READY, **PRIVATE** | Không |
| `T7` | U2 | 2026-10-08T11:30:00Z | **PROCESSING**, PUBLIC | Không |
| `T2` (`5a4b3c2d-…`) | U2 | 2026-10-08T11:00:00Z | READY, PUBLIC | **Có** |
| `T3` (`7e6d5c4b-…`) | U1 | 2026-10-07T09:15:00Z | READY, PUBLIC | **Có** |
| `T4` | U2 | 2026-10-07T08:00:00Z | READY, PUBLIC | **Có** |

```
GET /feed?limit=2
  SQL (LIMIT 3): các dòng qua bộ lọc, sắp theo (created_at DESC, id DESC): T1, T2, T3
  → trả [T1, T2] ; T3 chỉ để biết còn trang sau
  nextCursor = Base64URL("1791457200000000:5a4b3c2d-1e0f-4a9b-8c7d-6e5f4a3b2c1d")
             = MTc5MTQ1NzIwMDAwMDAwMDo1YTRiM2MyZC0xZTBmLTRhOWItOGM3ZC02ZTVmNGEzYjJjMWQ
             (1791457200000000 = 11:00:00 UTC tính bằng micro giây từ 1970; phần sau dấu ':' là id của T2)

-- Giữa hai trang, U1 đăng T8 lúc 12:40 (mới nhất).
GET /feed?limit=2&cursor=MTc5MTQ1NzIw…
  SQL: … AND (t.created_at, t.id) < ('2026-10-08 11:00:00', '5a4b3c2d-…') LIMIT 3 → T3, T4
  → trả [T3, T4] ; nextCursor = null (chỉ 2 dòng < LIMIT 3)
  T8 không xuất hiện ở trang này (mới hơn con trỏ) — đúng: người dùng sẽ thấy T8 khi làm mới feed từ đầu.
```
Với `OFFSET 2`, trang hai sẽ tính trên danh sách `[T8, T1, T2, T3, T4]` và bỏ 2 dòng đầu → `T2, T3`: **T2 trùng**. Keyset không bị.

**Trace nhỏ cho `isLikedByMe`:** V đã like `T2`. Cột `liked_by_me` của dòng `T2` là `true`, các dòng khác `false`, trong cùng một truy vấn (subquery `EXISTS` dùng PK `(user_id, track_id)`).

## 8. Test cần viết

| Loại | Test | Kiểm tra / ca biên |
|------|------|--------------------|
| Cursor | `PageCursorTest` — round-trip, hỏng, thiếu `:`, uuid sai | khớp `TrackCursorTest` |
| Use case | `GetFeedUseCaseTest` — trang đầu, trang cuối, đúng `limit+1`, `limit<1`, `limit>50`, cursor hỏng | |
| | `ListLikedTracksUseCaseTest` — user lạ → `UserNotFoundException` | |
| postgres | `FeedReaderJdbcPostgresTest.onlyReadyPublicTracksOfFollowedUsersAppear` | dữ liệu của bảng mục 7: kỳ vọng đúng `[T1,T2,T3,T4]` |
| | `...yourOwnTracksAreNotInYourFeed` | |
| | `...aPrivateTrackOfAFollowedUserNeverAppears` | kể cả khi viewer là… (không bao giờ) |
| | `...unfollowingRemovesTheTracksFromTheFeed` | |
| | `...pagesDoNotOverlapAndNothingIsMissingWhenANewTrackArrives` | trace 7 |
| | `...tracksWithTheSameCreationTimeAreSplitByIdAcrossPages` | tie-breaker; cố định 2 track cùng `created_at` ở ranh giới trang |
| | `...isLikedByMeIsTrueOnlyForTracksTheViewerLiked` | |
| | `LikedTracksReaderJdbcPostgresTest.likesAreOrderedByWhenTheyWereLikedNotByTrackAge` | cursor `(liked_at, track_id)` |
| | `...aPrivateTrackOfSomeoneElseIsHiddenButYourOwnPrivateTrackIsShown` | |
| HTTP | `FeedOverHttpPostgresTest` — luồng: 3 user, follow, đăng, feed; `401` không token; feed rỗng khi không follow | |
| | `LikesOfAUserOverHttpPostgresTest` — user lạ `404`, khách xem được | |
| Security | `feedNeedsALogin`, `likesOfAUserArePublic` | |
| Schema | `DiscoverySchemaContractPostgresTest.theColumnsTheQueriesReadStillExist` | chạy từng truy vấn với `LIMIT 0`: nếu `track` đổi cột, test này đỏ ngay |
| Arch | như mục 4 | |

## 9. Lỗi thường gặp

| Lỗi | Dấu hiệu | Sửa |
|-----|----------|-----|
| Lọc `visibility` trong Java sau khi lấy trang | Trang có 12 thay vì 20 phần tử, `nextCursor` sai | Bộ lọc trong SQL. |
| Cursor dùng `created_at` của track cho danh sách like | Trang hai lặp/mất like | Cursor của like là `(liked_at, track_id)`. |
| `Instant` làm tham số | `Can't infer the SQL type…` | `OffsetDateTime` (hoặc `Timestamp`). |
| Mất độ chính xác micro giây ở cursor | Phần tử cuối trang trước lại xuất hiện | Lưu `micros`, không dùng `toString()`/mili giây. |
| `ORDER BY` thiếu khoá phụ | Thứ tự hai track cùng giây không ổn định giữa các lần gọi | Luôn `ORDER BY created_at DESC, id DESC`. |
| ArchUnit "failed to check any classes" | `discovery` không có lớp domain | Chỉ áp các quy tắc phù hợp (mục 4). |
| Tạo index "cho chắc" | Ghi chậm hơn, không lợi gì | Chỉ tạo khi `EXPLAIN ANALYZE` chứng minh. |
| Chạy dữ liệu perf trên `lasono_test` | `cleanTestDatabase()` xoá mất, hoặc làm chậm mọi test | Dùng database tạm riêng. |
| Quên `ANALYZE` sau khi nạp dữ liệu | Planner chọn kế hoạch tệ vì thống kê cũ | `ANALYZE;` trước khi đo. |
| `EXISTS` subquery gọi cho từng dòng | Chậm khi trang lớn | Với 20-50 dòng và PK, chấp nhận được; đo trước khi tối ưu. |
| `403` thay vì `401` cho feed | Khách thấy lỗi sai | Chưa đăng nhập luôn `401`. |

## 10. Kiểm tra thủ công

Dùng biến của guide 02-03. Chuẩn bị: `A` upload hai track `READY` (đợi vài giây). `B` follow `A` (`PUT /users/$ID_A/follow`).

| # | Lệnh | Kỳ vọng |
|---|------|---------|
| 1 | `curl -i $BASE/feed` | `401` |
| 2 | `curl -s $BASE/feed -H "Authorization: Bearer $TOKEN_B"` | track của A, mới nhất trước, có `likeCount`, `isLikedByMe`, `createdAt` |
| 3 | `curl -s $BASE/feed -H "Authorization: Bearer $TOKEN_A"` | `{"items":[],"nextCursor":null}` (A không follow ai; track của chính mình không có) |
| 4 | `curl -s "$BASE/feed?limit=1" -H "Authorization: Bearer $TOKEN_B"` | 1 item + `nextCursor`; gọi tiếp với cursor đó → item còn lại, `nextCursor:null` |
| 5 | A đổi một track sang PRIVATE; chạy lại 2 | track đó biến mất |
| 6 | B bỏ follow A; chạy lại 2 | `items: []` |
| 7 | B like một track của A, rồi `curl -s "$BASE/users/$ID_B/likes"` | track đó, `isLikedByMe` (không token) = `false`; thêm token B → `true` |
| 8 | `curl -i "$BASE/users/00000000-0000-0000-0000-000000000000/likes"` | `404` |
| 9 | `curl -i "$BASE/feed?cursor=abc" -H "Authorization: Bearer $TOKEN_B"` | `400` |

**Kịch bản UI** (tắt `FAKE_FEED`): đăng nhập B → mở *Feed*: thấy track của A; đăng nhập user mới chưa follow ai → màn hình trống với lời gợi ý "Tìm người để theo dõi" dẫn về Home;
profile của B → tab *Likes* hiện track đã like; cuộn xuống cuối feed khi có > 20 track để thấy tải thêm.

## 11. Câu hỏi tự kiểm tra

<details><summary>Hiện đáp án gợi ý sau khi tự trả lời</summary>

1. **Fan-out on read khác on write ở đâu? Vì sao chọn on read?** On read tính khi đọc (JOIN), on write chép trước cho từng follower. On read đơn giản và luôn đúng; chưa có số đo cho thấy cần on write.
2. **"Celebrity problem" là gì?** Người có hàng triệu follower: mỗi lần đăng phải ghi hàng triệu dòng.
3. **Vì sao `discovery` được JOIN bảng của module khác?** Nó là read model, không có bất biến cần bảo vệ; đổi lại bị ràng buộc theo schema, giảm bằng ba rào chắn.
4. **Vì sao bộ lọc nằm trong SQL?** Để trang luôn đầy và con trỏ đúng; lọc sau làm thiếu phần tử.
5. **`OFFSET` hỏng thế nào khi có dữ liệu mới?** Vị trí dịch chuyển nên trùng/sót; keyset neo vào giá trị.
6. **Cursor của danh sách like khác cursor của feed ở điểm nào?** Mang thời điểm like và id track, không phải thời điểm tạo track.
7. **Khi nào `Sort` trong `EXPLAIN` là vấn đề?** Khi sắp toàn bộ tập lớn; `top-N heapsort` với `LIMIT` nhỏ thì rẻ hơn nhiều. Nếu index cho đúng thứ tự thì không cần sort.
8. **Vì sao đo trước khi tạo index?** Index làm chậm ghi và tốn bộ nhớ; chỉ đáng khi có bằng chứng.

</details>

## 12. Bài tập mở rộng

1. **Phương án lai:** người có > N follower thì dùng on read, còn lại on write; mô tả (không bắt buộc cài) schema `feed_items` và job backfill khi follow.
2. **Hợp đồng không trôi:** viết `postgresTest` gọi `GET /tracks` và `GET /feed` rồi kiểm tra hai JSON có **cùng tập tên field** (cách rẻ nhất để giữ hai record `TrackListItemResult` và `TrackItemResult` khớp nhau).
