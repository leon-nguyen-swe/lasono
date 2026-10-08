# Guide 02: Likes (idempotent, bộ đếm nhất quán)

> Phase 5 · Cần xong trước: [guide 01](01-domain-events.md) · Mở khoá: guide 03, 04, 05
> Đây là guide dài nhất vì nó **dựng module `engagement`** và dạy các khái niệm khó nhất của Phase 5.
> Các guide 03 và 04 sẽ lặp lại khuôn này, chỉ khác chi tiết.

## 1. Mục tiêu và nghiệm thu

**Làm gì.** Người đăng nhập bấm like một track; bấm lần nữa không làm gì thêm; bỏ like thì số like giảm. Mọi track trả về
`likeCount`, `isLikedByMe`, `createdAt`. Số like **luôn khớp** số dòng trong bảng `likes`, kể cả khi nhiều người like cùng lúc.

Theo [`api-contract.md` B1](../api-contract.md#b1-likes): `PUT /tracks/{id}/like`, `DELETE /tracks/{id}/like`, và 4 field mới
(`createdAt`, `likeCount`, `commentCount`, `isLikedByMe`) trên `GET /tracks`, `GET /tracks/{id}`, `GET /users/{id}/tracks`,
`PATCH /tracks/{id}`. (Danh sách "track tôi đã like" `GET /users/{id}/likes` làm ở [guide 05](05-feed.md) vì dùng chung
read-model; `commentCount` luôn là 0 cho đến guide 04.)

**Xong khi:**

- [ ] `PUT`/`DELETE` hoạt động đúng bảng mã lỗi của hợp đồng (200 / 401 / 404 / 409), response `{trackId, liked, likeCount}`.
- [ ] Gọi `PUT` hai lần: `likeCount` chỉ tăng một lần; `DELETE` hai lần: chỉ giảm một lần.
- [ ] 20 request like đồng thời của 20 user khác nhau → `likeCount` đúng bằng 20 (test `postgresTest`).
- [ ] Hai request like đồng thời của **cùng một user** → đúng 1 dòng `likes`, count +1.
- [ ] Track private của người khác: like → `404`; không xuất hiện `isLikedByMe` của người khác.
- [ ] Lưu lại track (worker xong, `PATCH`) **không** làm mất bộ đếm.
- [ ] Xoá track thì dọn luôn các dòng `likes` của nó.
- [ ] Trình duyệt gọi được `PUT` (CORS preflight qua), app chạy với `FAKE_LIKES` tắt.

## 2. Kiến thức cần biết trước

| Khái niệm | Đọc ở đâu |
|-----------|-----------|
| Idempotency của `PUT`/`DELETE` trong HTTP | [RFC 9110 §9.2.2 Idempotent Methods](https://www.rfc-editor.org/rfc/rfc9110#name-idempotent-methods) |
| `INSERT ... ON CONFLICT DO NOTHING` | [PostgreSQL: INSERT, mục ON CONFLICT Clause](https://www.postgresql.org/docs/current/sql-insert.html#SQL-ON-CONFLICT) |
| Cách PostgreSQL xử lý ghi đồng thời, `READ COMMITTED` | [PostgreSQL: Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html) (đọc kỹ 13.2.1) |
| Khoá hàng (row lock) | [PostgreSQL: Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS) |
| `JdbcTemplate`, `NamedParameterJdbcTemplate` | [Spring: Data Access with JDBC](https://docs.spring.io/spring-framework/reference/data-access/jdbc/core.html) |
| `@Transactional` hoạt động qua proxy (gọi nội bộ không có tác dụng) | [Spring: Declarative transaction management](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html) |
| Cột chỉ-đọc trong JPA (`insertable`/`updatable = false`) | [Jakarta Persistence `@Column`](https://jakarta.ee/specifications/persistence/3.2/apidocs/jakarta.persistence/jakarta/persistence/column.html) |
| Lost update (ghi đè mất) | `glossary.md` |

Ba điều cần nắm chắc:

1. **Idempotent ≠ "không lỗi lần hai".** Idempotent nghĩa là *trạng thái cuối giống nhau* dù gọi 1 hay 5 lần. `PUT like` lần hai
   vẫn trả `200 liked:true`, nhưng bộ đếm không tăng nữa.
2. **Có sự kiện chỉ khi có thay đổi thật.** Nếu `INSERT ... ON CONFLICT DO NOTHING` ghi 0 dòng thì *không* phát `TrackLiked`;
   nếu không, bộ đếm sẽ tăng mỗi lần bấm.
3. **"Đọc rồi ghi" trong Java là sai khi đồng thời.** Phép tăng phải xảy ra *trong SQL*: `SET like_count = like_count + 1`.

## 3. Quyết định thiết kế

### D1. Likes sống ở đâu?

| Phương án | Ưu | Nhược |
|-----------|----|-------|
| A. Trong module `track` | JOIN trực tiếp, không cần cầu nối, `isLikedByMe` đơn giản. | `track` phình to; không có lý do dùng domain events (mục tiêu học tập của Phase 5). |
| **B. Module mới `engagement` + sự kiện** *(khuyến nghị)* | Ranh giới rõ: `track` biết "track là gì", `engagement` biết "người ta làm gì với track". Học được ACL, đảo phụ thuộc, sự kiện. | Nhiều class hơn; cần cầu nối (`TrackLookup`, `ViewerLikesReader`). |
| C. Trong `identity` | — | Like là quan hệ user↔track; đặt ở `identity` là sai chủ. |

### D2. Đếm like thế nào?

| Phương án | Chi phí đọc | Chi phí ghi | Đúng khi đồng thời? |
|-----------|-------------|-------------|---------------------|
| A. `SELECT COUNT(*) FROM likes WHERE track_id = ?` khi đọc | Cao: mỗi track trong danh sách một truy vấn đếm (hoặc `GROUP BY` lớn) | Thấp | Luôn đúng |
| **B. Cột `tracks.like_count` + `UPDATE SET like_count = like_count + 1` cùng transaction** *(khuyến nghị)* | Thấp: đã nằm trong dòng `tracks` | Thêm 1 `UPDATE` (khoá dòng track ngắn) | Đúng, nhờ phép cộng nguyên tử trong SQL |
| C. Đọc `like_count` vào Java, `+1`, `save()` | Thấp | Thấp | **Sai**: lost update |
| D. Redis counter | Rất thấp | Thấp | Cần đồng bộ lại với DB; **hoãn** theo chính sách dự án (Phase 8) |

Chọn B, **kèm** B-cũng-có-thể-lệch nếu ai đó sửa bảng bằng tay, nên có job đối soát (bài tập mở rộng). Phương án A vẫn dùng để
**kiểm chứng** B trong test (`COUNT(*)` phải bằng `like_count`).

### D3. Idempotent bằng cách nào?

| Phương án | Vấn đề |
|-----------|--------|
| A. `SELECT` xem đã like chưa, rồi `INSERT` | Race: hai request cùng thấy "chưa", cùng `INSERT` → một cái lỗi unique hoặc (nếu không có unique) hai dòng. |
| B. `INSERT` rồi bắt `DataIntegrityViolationException` | Chạy được, nhưng PostgreSQL đánh dấu **cả transaction đã hỏng** ("current transaction is aborted") sau lỗi unique, nên không làm gì tiếp trong transaction đó được. |
| **C. `INSERT ... ON CONFLICT DO NOTHING` và đọc số dòng ghi được** *(khuyến nghị)* | 1 câu SQL, không race, không lỗi, `1` = mới, `0` = đã có. |

### D4. `isLikedByMe` cho cả trang danh sách?

Một truy vấn cho cả trang: `SELECT track_id FROM likes WHERE user_id = :viewer AND track_id IN (:ids)` → `Set<UUID>`. Giống cách
`findDurationsByTrackIds` tránh N+1 ở Phase 3. Người xem chưa đăng nhập → không truy vấn, trả tập rỗng.

## 4. Vị trí trong kiến trúc

```
com.lasono.engagement
├── domain/
│   ├── UserRef, TrackRef            (value object: chỉ bọc UUID của thứ thuộc module khác)
│   ├── Like
│   └── LikeRepository               (interface)
├── application/
│   ├── port/out/
│   │   ├── EventPublisher           (guide 01)
│   │   ├── TrackLookup, TrackFacts  (cầu nối sang track)
│   └── usecase/
│       ├── LikeTrackUseCase, UnlikeTrackUseCase, LikeResult
│       ├── RemoveEngagementOfTrackUseCase           (dọn khi track bị xoá)
│       └── TrackNotFoundException, TrackNotReadyException
├── infrastructure/
│   ├── persistence/LikePersistenceAdapter           (JdbcTemplate, ON CONFLICT)
│   ├── persistence/ViewerLikesJdbcReader            (implements track.application.port.out.ViewerLikesReader)
│   ├── track/TrackLookupAdapter                     (ACL: gọi track.application.usecase.GetTrackUseCase)
│   └── event/SpringEventPublisher, TrackDeletedListener
└── presentation/
    ├── LikeController
    └── EngagementExceptionHandler

com.lasono.track  (thêm)
├── application/port/out/ViewerLikesReader, TrackStatsReader, TrackCounterRepository, EventPublisher
├── application/usecase/AdjustTrackCountersUseCase     (+ sửa ListTracksUseCase, GetTrackUseCase, UpdateTrackUseCase, DeleteTrackUseCase)
└── infrastructure/event/TrackCounterListener, infrastructure/persistence/TrackCounterPersistenceAdapter
```

**Sơ đồ phụ thuộc (mũi tên = "import"):**

```
engagement.presentation ─► engagement.application ─► engagement.domain
engagement.infrastructure ─► engagement.application (implements port)
engagement.infrastructure ─► track.application.usecase.GetTrackUseCase     ◄── CHỈ ở đây (ACL)
engagement.infrastructure ─► track.application.port.out.ViewerLikesReader   ◄── CHỈ ở đây (đảo phụ thuộc)
track.infrastructure.event ─► shared.event.TrackLiked                        (nghe sự kiện)
track  ✗─► engagement                                                         (ArchUnit)
```

Hai cầu nối khác hướng, cần hiểu:

- **`TrackLookup` (engagement cần dữ liệu của track):** port do `engagement` *định nghĩa* (nó cần gì thì tự mô tả), adapter trong
  `engagement.infrastructure` *dịch* tiếng của `track` sang tiếng của `engagement`. Đây là **anti-corruption layer (ACL)**.
- **`ViewerLikesReader` (track cần biết user đã like gì):** port do `track` định nghĩa, nhưng **engagement implement**. Đây là
  **đảo phụ thuộc xuyên module**: `track` chỉ biết một interface của chính nó; lúc chạy, Spring cắm implement của `engagement` vào.
  Kết quả: `track` không import `engagement`, còn `engagement` import một interface của `track`.

**ArchUnit cần đổi** (RED trước):

```java
// ArchitectureTest
private static final String ENGAGEMENT = "com.lasono.engagement";
// importPackages(TRACK, IDENTITY, ENGAGEMENT, "com.lasono.shared")
@Test void trackDoesNotDependOnEngagement()    { moduleDoesNotDependOn(TRACK, ENGAGEMENT).check(classes); }
@Test void identityDoesNotDependOnEngagement() { moduleDoesNotDependOn(IDENTITY, ENGAGEMENT).check(classes); }
// quy tắc mới trong ArchitectureRules: chỉ infrastructure của engagement được import module khác
public static ArchRule onlyInfrastructureMayUseOtherModules(String root, String otherRoot) {
    // TODO: noClasses().that().resideInAnyPackage(root+"..domain..", root+"..application..", root+"..presentation..")
    //       .should().dependOnClassesThat().resideInAPackage(otherRoot+"..")
    throw new UnsupportedOperationException("TODO");
}
```
Và nhớ gọi các quy tắc cũ (`domainIsFrameworkFree`, `applicationDoesNotDependOnPresentation`, ...) cho `ENGAGEMENT`, rồi thêm ca
"cố tình vi phạm" vào `ArchitectureRulesTest` với lớp mẫu ở `archfixture`.

## 5. Schema

Số `V8`, `V9` là gợi ý: dùng **số kế tiếp còn trống** của bạn. Không sửa migration đã chạy.

```sql
-- V8__add_counters_to_tracks.sql
-- Counters for what the engagement module records. They are written only by SQL like "like_count = like_count + 1".
ALTER TABLE tracks
    ADD COLUMN like_count INT NOT NULL DEFAULT 0,
    ADD COLUMN comment_count INT NOT NULL DEFAULT 0;

ALTER TABLE tracks
    ADD CONSTRAINT ck_tracks_like_count_not_negative CHECK (like_count >= 0),
    ADD CONSTRAINT ck_tracks_comment_count_not_negative CHECK (comment_count >= 0);
```
```sql
-- V9__create_likes.sql
-- No foreign keys: engagement holds ids of users and tracks as plain values (modules do not reference each other's tables).
CREATE TABLE likes
(
    user_id UUID NOT NULL,
    track_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- One like per (user, track). Also the index that answers "did this user like this track?".
    CONSTRAINT pk_likes PRIMARY KEY (user_id, track_id)
);

-- "The tracks a user liked, newest first" (guide 05): keyset order (created_at DESC, track_id DESC) for one user.
CREATE INDEX idx_likes_user_created ON likes (user_id, created_at DESC, track_id DESC);
-- Removing every like of a deleted track, and reconciling counters, look up by track.
CREATE INDEX idx_likes_track ON likes (track_id);
```

| Chi tiết | Lý do |
|----------|-------|
| `PRIMARY KEY (user_id, track_id)` | Là *unique constraint* chặn like đôi, đồng thời là index tra cứu "user này đã like track này chưa" (cột đầu `user_id` cũng hỗ trợ `WHERE user_id = ? AND track_id IN (...)`). |
| `idx_likes_user_created` | PK sắp theo `(user_id, track_id)` nên **không** giúp `ORDER BY created_at DESC`. Index này cho keyset "likes của user, mới nhất trước". Bỏ nó, truy vấn sẽ sort toàn bộ like của user. |
| `idx_likes_track` | Dọn like khi xoá track (`DELETE ... WHERE track_id = ?`) và đối soát. PK không dùng được vì `track_id` không phải cột đầu. |
| `CHECK (like_count >= 0)` | Tuyến phòng thủ cuối: một lỗi đếm không bao giờ âm im lặng, mà lỗi to (rollback). |
| `INT NOT NULL DEFAULT 0` | PostgreSQL ≥ 11 thêm cột với default hằng số chỉ sửa metadata, không viết lại bảng. |
| Không có khoá ngoại | Quy ước dự án (migration V4/V6): module chỉ giữ id của module khác. Hệ quả: **phải tự dọn** like khi track bị xoá (bước 8). |

Nhớ thêm vào `PostgresIntegrationTest.cleanTestDatabase()` (đặt **trước** các `DELETE` hiện có cũng được vì không có FK):
`jdbcTemplate.update("DELETE FROM likes");`.

## 6. Các bước code theo thứ tự

### Bước 0. Cấu hình route và CORS (RED trước)

1. `CorsConfigTest`: thêm test `putIsAnAllowedMethodForThePreflight` (xem `CorsConfigTest` dòng ~191 cho `PATCH`, `DELETE`).
   Chạy → RED (preflight `Access-Control-Request-Method: PUT` bị từ chối).
2. `CorsConfig`: thêm `"PUT"` vào `setAllowedMethods(...)`. GREEN.
3. `SecurityConfigTest`: `likingNeedsALogin` — `PUT /api/v1/tracks/{id}/like` không token → `401`. Nó **đã xanh** ngay (mọi route chưa
   mở đều `authenticated()`); test này để *khoá* hành vi, đừng thêm `permitAll` cho like.

> Route `GET /api/v1/tracks/**` là `permitAll` nhưng chỉ cho phương thức `GET`. `PUT`/`DELETE` rơi xuống `anyRequest().authenticated()`.

### Bước 1. Migration + test hạ tầng

Tạo `V8`, `V9`. Viết `postgresTest` `LikesMigrationPostgresTest`:
`likesTableRejectsTheSameLikeTwice`, `trackCountersStartAtZero`, `aNegativeLikeCountIsRejected` (kỳ vọng `DataIntegrityViolationException`).
Thêm `DELETE FROM likes` vào `cleanTestDatabase()`. Chạy `postgresTest` → mọi test xanh sau khi migration có.

### Bước 2. Domain của `engagement`

```java
package com.lasono.engagement.domain;

/** The id of a user. Only the id: the engagement module never imports the identity module. */
public class UserRef { /* TODO: giống OwnerId (requireNonNull, equals, hashCode, getValue) */ }

/** The id of a track. Same idea. */
public class TrackRef { /* TODO */ }

public class Like {
    // TODO: fields UserRef user, TrackRef track
    // TODO: constructor with requireNonNull; getters
}

public interface LikeRepository {
    /** Stores the like unless it is already there. True when a new like was stored, false when it already existed. */
    boolean addIfAbsent(Like like);

    /** Removes the like. True when a like was removed, false when there was none. */
    boolean remove(UserRef user, TrackRef track);

    /** Removes every like of a track (the track was deleted). Returns how many were removed. */
    int removeAllOfTrack(TrackRef track);
}
```
Test trước (`InMemoryLikeRepository` ở `src/test/.../domain/`, và **test lại chính fake**, như `InMemoryUserRepositoryTest`):
`InMemoryLikeRepositoryTest`: `addIfAbsentReturnsTrueTheFirstTimeAndFalseTheSecond`, `removeReturnsTrueOnlyWhenALikeWasThere`,
`removeAllOfTrackRemovesOnlyThatTracksLikes`. Fake này sẽ thật sự được dùng ở bước 3.

### Bước 3. Application: ports và use case

```java
package com.lasono.engagement.application.port.out;

/** What the engagement module needs to know about a track. The adapter asks the track module and translates. */
public interface TrackLookup {

    /**
     * The track as {@code viewerId} may see it.
     * @throws com.lasono.engagement.application.usecase.TrackNotFoundException when it does not exist or is private to someone else
     */
    TrackFacts requireVisible(UUID trackId, UUID viewerId);

    /** The number of likes the track shows right now (after the counter listener ran). */
    int likeCountOf(UUID trackId, UUID viewerId);
}

public record TrackFacts(UUID trackId, UUID ownerId, boolean ready, Long durationMs) {}
```

```java
package com.lasono.engagement.application.usecase;

@Component
public class LikeTrackUseCase {

    private final LikeRepository likes;
    private final TrackLookup tracks;
    private final EventPublisher events;
    private final Clock clock;

    // TODO: constructor

    // One transaction around everything: the like, the event and the listener's UPDATE commit or roll back together.
    @Transactional
    public LikeResult execute(UUID trackId, UUID userId) {
        // TODO 1: TrackFacts facts = tracks.requireVisible(trackId, userId);   // not visible -> TrackNotFoundException (404)
        // TODO 2: if (!facts.ready()) throw new TrackNotReadyException(trackId);   // 409
        // TODO 3: boolean added = likes.addIfAbsent(new Like(new UserRef(userId), new TrackRef(trackId)));
        // TODO 4: if (added) events.publish(new TrackLiked(trackId, userId, clock.instant()));
        //         ^ Only a real change is an event. Gợi ý: nếu bỏ điều kiện này, test "execute_twice_shouldPublishOnlyOnce" đỏ.
        // TODO 5: return new LikeResult(trackId.toString(), true, tracks.likeCountOf(trackId, userId));
        throw new UnsupportedOperationException("TODO");
    }
}

public record LikeResult(String trackId, boolean liked, int likeCount) {}
```
`UnlikeTrackUseCase` tương tự: kiểm tra track *nhìn thấy được* (404) nhưng **không** kiểm tra `ready`; `likes.remove(...)`; chỉ
phát `TrackUnliked` khi `remove` trả `true`; trả `LikeResult(.., false, count)`.

Test viết **trước**, bằng fake (không Mockito): `InMemoryLikeRepository`, `FakeTrackLookup` (map id → `TrackFacts`, tự đếm like
bằng số like trong fake repository, hoặc một `Map` đơn giản), `RecordingEventPublisher`, `Clock.fixed(...)`.
Danh sách test ở mục 8.

### Bước 4. Phía `track`: bộ đếm, `createdAt`, `isLikedByMe`

Làm theo thứ tự, mỗi mục là một cặp RED/GREEN riêng:

**4a. `TrackJpaEntity` — hai cột đếm, chỉ-đọc từ phía Java.**
```java
// TrackJpaEntity: thêm hai field, KHÔNG cho Hibernate ghi chúng
@Column(name = "like_count", nullable = false, insertable = false, updatable = false)
private int likeCount;

@Column(name = "comment_count", nullable = false, insertable = false, updatable = false)
private int commentCount;
```
Vì sao `insertable = false, updatable = false`? `TrackPersistenceAdapter.save` luôn dựng một `TrackJpaEntity` mới rồi
`saveAndFlush` (merge). Nếu bộ đếm là cột ghi được, mỗi lần worker đánh dấu `READY` hoặc owner `PATCH` sẽ **ghi đè bộ đếm bằng 0**.
Cột chỉ-đọc làm bộ đếm chỉ đổi qua SQL `+ 1`. (Cùng kỹ thuật với `created_at ... updatable = false`.)
`@AllArgsConstructor` sẽ đòi 2 đối số mới: sửa `TrackPersistenceAdapter.save` truyền `0, 0` (giá trị này không bao giờ được ghi).
**Test bắt buộc** (`postgresTest`): `savingATrackAgainDoesNotResetItsCounters`.

**4b. `TrackSummary`, `TrackListItemResult`.** Thêm `likeCount`, `commentCount` vào `TrackSummary` (lấy từ entity trong
`toSummary`), và `createdAt` (đã có trong `TrackSummary`), `likeCount`, `commentCount`, `isLikedByMe` vào `TrackListItemResult`
(`createdAt` là `Instant`; Jackson tự ra ISO-8601). Dùng **record**, để tên JSON đúng là `isLikedByMe`.

**4c. `ViewerLikesReader` (port của `track`).**
```java
package com.lasono.track.application.port.out;

public interface ViewerLikesReader {
    /** Of these tracks, the ones the viewer liked. Empty when nobody is logged in ({@code viewerId == null}). */
    Set<UUID> likedAmong(UUID viewerId, Collection<UUID> trackIds);
}
```
`ListTracksUseCase.page(...)`: sau khi có `page`, gọi `viewerLikesReader.likedAmong(viewerId, ids)` **một lần** rồi ghép vào `toItem`.
Cần truyền `viewerId` xuống `page(...)`. Test trước: sửa `ListTracksUseCaseTest` thêm `InMemoryViewerLikesReader` (fake trong test) và
thêm test `listingMarksTheTracksTheViewerLiked`, `nobodyLoggedInLikedNothing`, `theLikesOfOtherUsersAreNotShown`.

**4d. `TrackStatsReader` cho trang chi tiết.** `Track` (domain) không giữ `createdAt` hay bộ đếm (đó là dữ liệu đọc, không phải bất biến
của aggregate). Thêm port `Optional<TrackStats> find(TrackId)` với `record TrackStats(Instant createdAt, int likeCount, int commentCount)`,
adapter đọc `tracks` bằng JPA. `GetTrackResult.from(track)` đổi thành `from(track, stats, likedByMe)`; `GetTrackUseCase` và
`UpdateTrackUseCase` đều phải truyền (PATCH cũng trả track chi tiết).

**4e. Bộ đếm: sự kiện → `UPDATE`.**
```java
// track/application/port/out/TrackCounterRepository.java
public interface TrackCounterRepository {
    /** Adds delta (+1 or -1) to the like counter of the track, in the transaction that is open. */
    void addToLikeCount(UUID trackId, int delta);
    void addToCommentCount(UUID trackId, int delta);   // dùng ở guide 04
}
```
```java
// track/infrastructure/persistence/TrackCounterPersistenceAdapter.java  (JdbcTemplate)
// SQL: UPDATE tracks SET like_count = like_count + ? WHERE id = ?
// TODO: jdbcTemplate.update(...). Nếu 0 dòng bị cập nhật (track vừa bị xoá)? Quyết định và ghi lại bằng một test.
```
```java
// track/infrastructure/event/TrackCounterListener.java
@Component
public class TrackCounterListener {
    private final AdjustTrackCountersUseCase useCase;   // TODO: constructor

    @EventListener
    public void on(TrackLiked event)   { /* TODO: useCase.likeAdded(event.trackId()) */ }

    @EventListener
    public void on(TrackUnliked event) { /* TODO: useCase.likeRemoved(event.trackId()) */ }
}
```
`AdjustTrackCountersUseCase` rất mỏng (`likeAdded` → `addToLikeCount(id, +1)`); nó tồn tại để listener (Infrastructure) chỉ *gọi* use case
chứ không chạm adapter trực tiếp. Test unit với `FakeTrackCounterRepository`.

### Bước 5. Infrastructure của `engagement`

```java
// engagement/infrastructure/persistence/LikePersistenceAdapter.java
@Repository
public class LikePersistenceAdapter implements LikeRepository {

    private static final String INSERT_SQL = """
        INSERT INTO likes (user_id, track_id) VALUES (?, ?)
        ON CONFLICT (user_id, track_id) DO NOTHING
        """;

    private final JdbcTemplate jdbcTemplate;   // TODO: constructor

    @Override
    public boolean addIfAbsent(Like like) {
        // TODO: int written = jdbcTemplate.update(INSERT_SQL, userId, trackId);   written: 1 = new, 0 = already there
        return false;
    }
    // TODO: remove (DELETE ... WHERE user_id=? AND track_id=?), removeAllOfTrack (DELETE ... WHERE track_id=?)
}
```
Vì sao `JdbcTemplate` mà không phải `JpaRepository`? Thao tác là **một câu SQL** và ta cần **số dòng bị ảnh hưởng**; entity với khoá
phức hợp (`@IdClass`) chỉ thêm rào cản. (Phase 3 cũng dùng `JdbcTemplate` cho hàng đợi job.) `created_at` do DB điền (`DEFAULT now()`), nên
không truyền; pgjdbc cũng không nhận `java.time.Instant` làm tham số, một cái bẫy nhỏ nếu bạn thử.

```java
// engagement/infrastructure/persistence/ViewerLikesJdbcReader.java — implements com.lasono.track.application.port.out.ViewerLikesReader
// SQL: SELECT track_id FROM likes WHERE user_id = :viewer AND track_id IN (:ids)
// Gợi ý: NamedParameterJdbcTemplate tự bung Collection thành "?, ?, ?". Danh sách rỗng hoặc viewer null -> trả Set.of() mà KHÔNG chạy SQL.
```
```java
// engagement/infrastructure/track/TrackLookupAdapter.java — implements TrackLookup, the anti-corruption layer
// requireVisible: gọi getTrackUseCase.execute(trackId, viewerId);
//   bắt com.lasono.track.application.usecase.TrackNotFoundException -> ném engagement...TrackNotFoundException
//   dịch GetTrackResult -> TrackFacts(ready = "READY".equals(status), durationMs = Math.round(durationSeconds * 1000))
// likeCountOf: getTrackUseCase.execute(...).likeCount()
```

### Bước 6. Presentation

```java
@RestController
public class LikeController {
    // TODO: ctor(LikeTrackUseCase, UnlikeTrackUseCase)

    @PutMapping("/api/v1/tracks/{id}/like")
    public LikeResult like(@PathVariable("id") UUID id, Principal principal) {
        // TODO: likeTrackUseCase.execute(id, UUID.fromString(principal.getName()));
        return null;
    }

    @DeleteMapping("/api/v1/tracks/{id}/like")
    public LikeResult unlike(@PathVariable("id") UUID id, Principal principal) { /* TODO */ return null; }
}
```
`EngagementExceptionHandler` (`@RestControllerAdvice`): `TrackNotFoundException` → `404`, `TrackNotReadyException` → `409`, trả
`ProblemDetail.forStatusAndDetail(...)` như `TrackExceptionHandler`. Test: `LikeControllerTest` bằng `MockMvcBuilders.standaloneSetup`
giống `UserControllerTest` (principal giả bằng `.principal(() -> USER_ID)`).

### Bước 7. Dọn dữ liệu khi xoá track (`TrackDeleted`)

Vì không có khoá ngoại, xoá track để lại like mồ côi (và `GET /users/{id}/likes` có thể trỏ vào track không tồn tại). Giải pháp là
một sự kiện **thật sự xuyên module**:

1. `track`: thêm port `EventPublisher` (bản sao riêng của module `track`, xem lưu ý ở guide 01) + `SpringEventPublisher`.
   Trong `DeleteTrackUseCase.removeFromDatabase(...)` (đang chạy trong `transaction.execute`), sau `trackRepository.delete(...)` gọi
   `events.publish(new TrackDeleted(...))`. Vì nằm **trong** transaction, listener của engagement xoá like **cùng transaction** với xoá track.
2. `engagement`: `TrackDeletedListener` (`@EventListener`) → `RemoveEngagementOfTrackUseCase` → `likes.removeAllOfTrack(...)` (guide 04 thêm
   comments vào cùng use case).
3. Test trước: `DeleteTrackUseCaseTest.execute_shouldPublishTrackDeleted` (fake publisher), và `postgresTest`
   `deletingATrackRemovesItsLikes` + `ifTheLikesCannotBeRemovedTheTrackIsNotDeleted` (listener ném lỗi → track còn nguyên).

### Bước 8. Đăng ký ArchUnit, chạy toàn bộ, commit

`./gradlew test --rerun`, `./gradlew postgresTest --rerun`. Commit nhỏ (ví dụ):
`feat: allow PUT in CORS`, `feat: likes and counters migrations`, `feat: like domain of the engagement module`,
`feat: like and unlike use cases`, `feat: like persistence with ON CONFLICT`, `feat: like counters on tracks`,
`feat: like endpoints`, `feat: remove likes when a track is deleted`.

## 7. Trace-through cụ thể

**Dữ liệu:** track `T = 0c1f…`, `like_count = 5`; user `A`, `B`. Mức cô lập mặc định của PostgreSQL: `READ COMMITTED`.

### Trace 1. Cùng một user bấm 2 lần cùng lúc (dùng `ON CONFLICT`)

```
t0  R1: BEGIN                                    R2: BEGIN
t1  R1: INSERT likes(A,T) ON CONFLICT DO NOTHING → ghi 1 dòng (chưa commit)
t2                                               R2: INSERT likes(A,T) ON CONFLICT DO NOTHING
                                                     → ĐỢI: khoá khoá-chính (A,T) đang do R1 giữ, chưa biết R1 commit hay rollback
t3  R1: publish TrackLiked → UPDATE like_count 5→6
t4  R1: COMMIT
t5                                               R2: thức dậy, thấy dòng (A,T) đã commit → "conflict" → DO NOTHING → 0 dòng
t6                                               R2: added = false → KHÔNG phát sự kiện
t7                                               R2: likeCountOf → 6 ; COMMIT ; trả {liked:true, likeCount:6}
```
Kết quả: 1 dòng `likes`, `like_count = 6`, cả hai request nhận `200`. Nếu ở t4 R1 **rollback** thì ở t5 R2 sẽ tự chèn thành công và phát sự kiện.

### Trace 2. Hai user khác nhau, code SAI (đọc → +1 trong Java → ghi)

```
t1  R1 (A): SELECT like_count FROM tracks WHERE id=T      → 5
t2  R2 (B): SELECT like_count FROM tracks WHERE id=T      → 5
t3  R1: UPDATE tracks SET like_count = 6 WHERE id=T ; COMMIT
t4  R2: UPDATE tracks SET like_count = 6 WHERE id=T ; COMMIT      ← ghi đè: có 2 like mới, bộ đếm chỉ +1
```
Đó là **lost update**: `likes` có 7 dòng, `like_count = 6`. Test `manyLikesAtTheSameTimeAreAllCounted` sẽ đỏ với code này.

### Trace 3. Hai user khác nhau, code ĐÚNG (`SET like_count = like_count + 1`)

```
t1  R1 (A): UPDATE tracks SET like_count = like_count + 1 WHERE id=T   → khoá dòng T, 5→6 (chưa commit)
t2  R2 (B): UPDATE tracks SET like_count = like_count + 1 WHERE id=T   → ĐỢI khoá dòng
t3  R1: COMMIT
t4  R2: có khoá; PostgreSQL đọc lại phiên bản dòng mới nhất đã commit (like_count = 6),
        tính lại "6 + 1" → 7 ; COMMIT
```
Phép cộng nằm *trong* câu lệnh nên không có khoảng hở giữa "đọc" và "ghi". (Đây là hành vi "re-check" của `READ COMMITTED`, mục 13.2.1 của
tài liệu PostgreSQL.) Bài học: **hai request bị tuần tự hoá trên dòng `tracks` của track đó**; track cực hot sẽ thành điểm nghẽn: đó là
lý do Redis được nêu cho Phase 8.

### Trace 4. Một trang danh sách có `isLikedByMe`

`GET /tracks?limit=3` bởi user A. `ListTracksUseCase` lấy 3 track `[T1, T2, T3]` (1 truy vấn), duration (1 truy vấn),
`likedAmong(A, [T1,T2,T3])` (1 truy vấn) → `{T2}`. Kết quả: `isLikedByMe` là `false, true, false`. Tổng 3 truy vấn cho cả trang, không phụ thuộc kích thước trang.

## 8. Test cần viết

**Domain / fake**

| Test | Kiểm tra |
|------|----------|
| `LikeTest.aLikeNeedsAUserAndATrack` | `requireNonNull` |
| `InMemoryLikeRepositoryTest.addIfAbsentReturnsTrueTheFirstTimeAndFalseTheSecond` | fake đúng ngữ nghĩa của port |
| `InMemoryLikeRepositoryTest.removeAllOfTrackRemovesOnlyThatTracksLikes` | không xoá nhầm |

**Use case** (`LikeTrackUseCaseTest`, `UnlikeTrackUseCaseTest`)

| Test | Ca biên |
|------|---------|
| `execute_shouldStoreTheLikeAndPublishTrackLiked` | đường chính |
| `execute_twice_shouldPublishOnlyOnce` | idempotent |
| `execute_shouldReturnTheCountAfterTheChange` | giá trị trong response |
| `execute_onATrackThatIsInvisibleToTheUser_shouldBeNotFound` | track private của người khác → 404 |
| `execute_onATrackThatIsNotReady_shouldBeConflict` | `PROCESSING`/`FAILED` → 409 |
| `execute_onYourOwnTrack_shouldWork` | được like track của mình |
| `execute_whenThePublisherFails_shouldPropagateTheError` | lỗi nổi lên (để rollback) |
| `unlike_whenThereWasNoLike_shouldPublishNothing` | idempotent |
| `unlike_aNotReadyTrack_shouldStillWork` | không kiểm `ready` khi bỏ like |
| `unlike_shouldPublishTrackUnlikedOnce` | |

**Track side**

| Test | Kiểm tra |
|------|----------|
| `AdjustTrackCountersUseCaseTest.likeAddedAddsOne` / `likeRemovedSubtractsOne` | |
| `TrackCounterListenerTest` (unit) | mỗi sự kiện gọi đúng use case |
| `ListTracksUseCaseTest.listingMarksTheTracksTheViewerLiked` + 2 ca | `isLikedByMe` |
| `GetTrackUseCaseTest.theDetailShowsCountsAndCreationTime` | field mới trong chi tiết |
| `DeleteTrackUseCaseTest.execute_shouldPublishTrackDeleted` | sự kiện xoá |

**postgresTest**

| Test | Kiểm tra |
|------|----------|
| `LikePersistenceAdapterPostgresTest.addingTheSameLikeTwiceStoresOneRow` | unique + ON CONFLICT |
| `...addIfAbsentReportsWhetherARowWasWritten` | trả 1/0 |
| `...twoRequestsOfTheSameUserAtTheSameTimeStoreOneLike` | race cùng user (mẫu: `UserPersistenceAdapterPostgresTest.twoSignUps...` với `CountDownLatch`) |
| `TrackCounterPostgresTest.manyLikesAtTheSameTimeAreAllCounted` | 20 user, 20 thread → `like_count == 20 == COUNT(*)` |
| `...aCounterCannotGoBelowZero` | CHECK constraint |
| `...savingATrackAgainDoesNotResetItsCounters` | `updatable = false` |
| `...aLikeAndItsCounterRollBackTogether` | listener lỗi → không còn dòng like |
| `LikeOverHttpPostgresTest.likeThenLikeAgainCountsOnce` | qua HTTP, `MockMvc` + JWT thật (mẫu: `ProfilePageOverHttpPostgresTest`) |
| `...aPrivateTrackOfSomeoneElseIsNotFound` / `...withoutALoginIsUnauthorized` | quy tắc hiển thị |
| `...theListShowsIsLikedByMeAndTheCount` | field mới trong `GET /tracks` |
| `...deletingATrackRemovesItsLikes` | dọn dẹp |

**Controller / config:** `LikeControllerTest` (200 + body, 404, 409, 401 do security), `CorsConfigTest.putIsAnAllowedMethod`, ArchUnit như mục 4.

**Mutation check** (làm ít nhất 3): bỏ `ON CONFLICT` → test race đỏ; đổi `+ ?` thành `= ?` → test đếm đồng thời đỏ; bỏ `updatable = false`
→ `savingATrackAgain...` đỏ. Trả lại code sau mỗi lần.

## 9. Lỗi thường gặp

| Lỗi | Dấu hiệu | Cách nhận ra / sửa |
|-----|----------|--------------------|
| Phát sự kiện cả khi `ON CONFLICT` ghi 0 dòng | Mỗi lần bấm like, count tăng | Test `execute_twice_shouldPublishOnlyOnce`. Chỉ phát khi `addIfAbsent == true`. |
| Quên `@Transactional` trên use case | Like còn nhưng count lệch khi listener lỗi | Test `aLikeAndItsCounterRollBackTogether`. Dùng `org.springframework.transaction.annotation.Transactional`. |
| `@Transactional` trên method gọi từ method khác cùng class | Không có transaction | Proxy chỉ chặn lời gọi từ bên ngoài. Giữ `@Transactional` ở `execute` công khai. |
| Bộ đếm về 0 sau khi worker xử lý xong | `like_count` đang 3 rồi thành 0 | `TrackPersistenceAdapter.save` ghi đè. Cột phải `updatable = false`. |
| JSON ra `likedByMe` | UI không hiện trạng thái like | Dùng `record ... boolean isLikedByMe`; class thường với getter `isLikedByMe()` bị Jackson đổi tên. |
| Truyền `Instant` cho `JdbcTemplate` | Lỗi `Can't infer the SQL type to use for an instance of java.time.Instant` | Để DB điền `now()`, hoặc `OffsetDateTime.ofInstant(i, ZoneOffset.UTC)`. |
| Test xanh trên H2, đỏ trên Postgres | `ON CONFLICT`, so sánh bộ giá trị khác | Mọi thứ về SQL phải có `postgresTest`; H2 chỉ để chạy nhanh phần logic. |
| `postgresTest` lẫn dữ liệu của test trước | Count lệch ngẫu nhiên | Quên `DELETE FROM likes` trong `cleanTestDatabase()`. |
| Bắt `DataIntegrityViolationException` để làm idempotent | "current transaction is aborted" ở câu lệnh sau | PostgreSQL huỷ transaction sau lỗi. Dùng `ON CONFLICT`. |
| Like track vừa chuyển sang private của người khác | `404` khi muốn bỏ like | Chấp nhận (ghi là giới hạn); bài tập: cho phép `DELETE like` bỏ qua kiểm tra hiển thị. |
| Lộ sự tồn tại của track private qua `403` | Hợp đồng sai | Luôn `404` (xem hợp đồng, quy tắc 2). |
| Danh sách `isLikedByMe` bị N+1 | Log SQL có hàng chục truy vấn `likes` | Một truy vấn `IN (:ids)` cho cả trang. |

## 10. Kiểm tra thủ công

Chuẩn bị: `docker compose up -d`, `export LASONO_JWT_SECRET=...`, `cd backend && ./gradlew bootRun`.

```bash
BASE=http://localhost:8080/api/v1
json() { python3 -c "import sys,json;print(json.load(sys.stdin)$1)"; }

# Hai user
for U in a b; do
  curl -s -X POST $BASE/auth/register -H 'Content-Type: application/json' \
    -d "{\"email\":\"$U@x.com\",\"displayName\":\"User $U\",\"password\":\"correct horse\"}" >/dev/null
done
TOKEN_A=$(curl -s -X POST $BASE/auth/login -H 'Content-Type: application/json' -d '{"email":"a@x.com","password":"correct horse"}' | json "['accessToken']")
TOKEN_B=$(curl -s -X POST $BASE/auth/login -H 'Content-Type: application/json' -d '{"email":"b@x.com","password":"correct horse"}' | json "['accessToken']")

# A upload một track (dùng file mp3/wav bất kỳ), đợi READY
ID=$(curl -s -X POST $BASE/tracks -H "Authorization: Bearer $TOKEN_A" -F title=Demo -F "file=@demo.mp3;type=audio/mpeg" | json "['trackId']")
sleep 5; curl -s $BASE/tracks/$ID | json "['status']"        # kỳ vọng: READY
```

| # | Lệnh | Kỳ vọng |
|---|------|---------|
| 1 | `curl -i -X PUT $BASE/tracks/$ID/like` | `401` (không token) |
| 2 | `curl -s -X PUT $BASE/tracks/$ID/like -H "Authorization: Bearer $TOKEN_B"` | `200 {"trackId":"…","liked":true,"likeCount":1}` |
| 3 | lặp lại lệnh 2 | `200` giống hệt, `likeCount` vẫn `1` |
| 4 | `curl -s $BASE/tracks/$ID -H "Authorization: Bearer $TOKEN_B" \| json "['isLikedByMe']"` | `True`; không token thì `False` |
| 5 | `curl -s -X PUT $BASE/tracks/$ID/like -H "Authorization: Bearer $TOKEN_A"` | `likeCount: 2` (được like track của mình) |
| 6 | `curl -s -X DELETE $BASE/tracks/$ID/like -H "Authorization: Bearer $TOKEN_B"` | `liked:false, likeCount:1`; lặp lại → vẫn `1` |
| 7 | `curl -s "$BASE/tracks?limit=5" -H "Authorization: Bearer $TOKEN_A"` | item có `likeCount`, `isLikedByMe`, `createdAt` |
| 8 | A đổi track sang `PRIVATE` (`curl -X PATCH … -d '{"visibility":"PRIVATE"}'`), rồi B `PUT like` | `404` (không phải `403`) |
| 9 | `curl -i -X PUT $BASE/tracks/00000000-0000-0000-0000-000000000000/like -H "Authorization: Bearer $TOKEN_A"` | `404` |
| 10 | Preflight: `curl -i -X OPTIONS $BASE/tracks/$ID/like -H 'Origin: http://localhost:3000' -H 'Access-Control-Request-Method: PUT'` | `200` và `Access-Control-Allow-Methods` có `PUT` |
| 11 | Kiểm chứng bộ đếm bằng SQL: `"/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe" exec lasono-postgres psql -U lasono -d lasono -c "SELECT t.like_count, (SELECT count(*) FROM likes l WHERE l.track_id=t.id) FROM tracks t WHERE t.id='$ID'"` | hai số bằng nhau |

**Kịch bản trên UI** (tắt `FAKE_LIKES`, giữ các cờ còn lại; xem [`00-how-to-use.md`](00-how-to-use.md)):
1. Đăng nhập B, mở Home → track của A có nút tim rỗng, số like `0`.
2. Bấm tim → tim đầy ngay (optimistic), tab Network có `PUT …/like` `200`; reload trang → tim vẫn đầy, số `1`.
3. Mở cửa sổ ẩn danh (chưa đăng nhập) → số `1`, tim rỗng; bấm tim → được mời đăng nhập.
4. Bấm tim lần nữa ở B → tim rỗng, số `0`. Tắt backend rồi bấm tim → tim quay về trạng thái cũ và có thông báo lỗi (rollback).

## 11. Câu hỏi tự kiểm tra

<details><summary>Hiện đáp án gợi ý sau khi tự trả lời</summary>

1. **`PUT like` hai lần có phải lỗi không? Server làm gì?** Không; idempotent. Lần hai `ON CONFLICT DO NOTHING` ghi 0 dòng → không sự kiện → count giữ nguyên, vẫn `200`.
2. **Vì sao `UPDATE ... SET n = n + 1` an toàn còn `read → +1 → save` thì không?** Phép cộng chạy trong DB dưới khoá dòng; kiểu kia có khoảng hở giữa đọc và ghi (lost update).
3. **Vì sao bắt `DataIntegrityViolationException` không phải cách tốt để làm idempotent trên PostgreSQL?** Sau lỗi unique, transaction ở trạng thái hỏng; mọi câu lệnh sau bị từ chối.
4. **Hai user like cùng lúc, chuyện gì xảy ra ở dòng `tracks`?** Hai `UPDATE` tuần tự hoá trên khoá dòng; người sau tính lại trên phiên bản đã commit. Count đúng.
5. **Vì sao cột đếm là `insertable/updatable = false`?** Vì `TrackPersistenceAdapter.save` dựng entity mới và sẽ ghi đè bộ đếm bằng 0 mỗi lần lưu track.
6. **Vì sao trả `404` chứ không `403` cho track private của người khác?** `403` xác nhận track tồn tại → lộ thông tin; `404` không phân biệt được với "không có".
7. **`ViewerLikesReader` do ai định nghĩa, ai cài? Vì sao?** `track` định nghĩa, `engagement` cài: để `track` không import `engagement` mà vẫn biết trạng thái like.
8. **Không có khoá ngoại thì xoá track sẽ để lại gì? Xử lý thế nào?** Like mồ côi; xử lý bằng sự kiện `TrackDeleted` chạy cùng transaction.
9. **Khi nào `likeCount` có thể lệch `COUNT(*)`? Làm sao biết?** Sửa DB bằng tay, lỗi code, hoặc nếu dùng `AFTER_COMMIT`. Job đối soát so hai số.

</details>

## 12. Bài tập mở rộng

1. **Job đối soát:** một `@Scheduled` (hoặc endpoint nội bộ) chạy
   `UPDATE tracks t SET like_count = c.n FROM (SELECT track_id, count(*) n FROM likes GROUP BY track_id) c WHERE c.track_id = t.id AND t.like_count <> c.n`
   và log số track bị sửa. Viết test: cố tình làm lệch rồi chạy job. (Gợi ý: job đọc `likes` nên đặt nó ở `engagement`/`discovery`, và nghĩ xem nó có được phép ghi
   vào `tracks` không.)
2. **Hot track:** dùng `pgbench` hoặc k6 (guide 07) bắn 500 like/giây vào *một* track và đo. Đây là câu chuyện để quyết định Redis ở Phase 8.
