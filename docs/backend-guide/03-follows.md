# Guide 03: Follows (idempotent, chặn tự follow, đếm, phân trang)

> Phase 5 · Cần xong trước: [guide 01](01-domain-events.md), [02](02-likes.md) (module `engagement` đã dựng) · Mở khoá: guide 05
> Khuôn giống guide 02; chỉ những điểm **khác** mới giải thích kỹ. Nếu gặp từ lạ, mở [`glossary.md`](glossary.md).

## 1. Mục tiêu và nghiệm thu

**Làm gì.** Một user theo dõi user khác. Profile hiển thị `followerCount`, `followingCount`, `isFollowedByMe`; có danh sách followers /
following (phân trang keyset); có endpoint batch lấy nhiều profile một lần (UI cần để hiện tên tác giả/người comment).

Theo [`api-contract.md` B2](../api-contract.md#b2-follows): `PUT`/`DELETE /users/{id}/follow`, `GET /users/{id}/followers|following`,
`GET /users?ids=…`, mở rộng `GET /users/{id}`, và `totalCount` ở `GET /users/{id}/tracks`.

**Xong khi:**

- [ ] `PUT`/`DELETE follow` đúng bảng mã (200 / 400 tự follow / 401 / 404 user lạ), idempotent, response `{userId, following, followerCount}`.
- [ ] Tự follow bị chặn ở **3 tầng**: domain (ném lỗi), use case → `400`, DB (`CHECK`). Có test cho từng tầng.
- [ ] `followerCount`/`followingCount` luôn khớp `COUNT(*)` trên `follows`, kể cả khi hai người follow nhau **cùng lúc** (không deadlock).
- [ ] `GET /users/{id}` có 3 field mới; `isFollowedByMe` là `false` khi chưa đăng nhập hoặc xem chính mình.
- [ ] `GET /users?ids=a,b` trả tối đa 50 profile, bỏ qua id lạ, `400` nếu quá 50 hoặc sai định dạng.
- [ ] Followers / following phân trang keyset đúng thứ tự, không trùng/sót khi có người follow mới giữa hai trang.
- [ ] `GET /users/{id}/tracks` có `totalCount`.
- [ ] App chạy với `FAKE_FOLLOWS` tắt.

## 2. Kiến thức cần biết trước

| Khái niệm | Đọc ở đâu |
|-----------|-----------|
| Deadlock và cách PostgreSQL phát hiện | [PostgreSQL: Deadlocks](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-DEADLOCKS) |
| `SELECT ... FOR UPDATE` và thứ tự khoá | [PostgreSQL: Row-level locks](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS) |
| Keyset pagination (so sánh bộ giá trị) | [PostgreSQL: Row constructor comparison](https://www.postgresql.org/docs/current/functions-comparisons.html#ROW-WISE-COMPARISON); xem `TrackCursor` + `TrackJpaRepository.findNewestAfter` trong code |
| `CHECK` constraint | [PostgreSQL: Check constraints](https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-CHECK-CONSTRAINTS) |
| `@RequestParam` với `List<UUID>` (tách dấu phẩy) | [Spring MVC: @RequestParam](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-methods/requestparam.html) |
| Idempotency, ON CONFLICT, bộ đếm nguyên tử | guide 02, mục 2-3 |

## 3. Quyết định thiết kế

### D1. Bộ đếm follow

Giống guide 02 (D2): chọn **cột phi chuẩn hoá** `users.follower_count`, `users.following_count`, cập nhật khi nhận `UserFollowed` /
`UserUnfollowed` bằng listener đồng bộ cùng transaction. Điểm **mới và nguy hiểm**: một lần follow cập nhật **hai hàng** `users`
(người được follow +1 follower, người đi follow +1 following). Hai request ngược chiều (A follow B, B follow A) có thể **deadlock**
(trace ở mục 7). Hai cách tránh:

| Phương án | Ghi chú |
|-----------|---------|
| **Khoá hai hàng theo thứ tự id cố định** (`SELECT ... WHERE id IN (a,b) ORDER BY id FOR UPDATE`) rồi mới `UPDATE` *(khuyến nghị)* | Mọi transaction xin khoá theo cùng một thứ tự nên không thể tạo vòng chờ. |
| Một `UPDATE ... WHERE id IN (a, b)` với `CASE` | Một câu lệnh nhưng thứ tự lấy khoá do planner quyết, không đảm bảo. |
| Không cập nhật `following_count`; đếm `COUNT(*)` khi đọc | Tránh được hai hàng, nhưng "following" thường được đếm trên mỗi lần xem profile. |

### D2. Biết user tồn tại thế nào?

Follow user không tồn tại → `404`. `engagement` không đọc bảng `users`; nó hỏi qua port `UserLookup`, adapter (ACL) gọi use case của `identity`
(`GetProfileUseCase`) và dịch `ProfileNotFoundException` thành lỗi của engagement. Cùng mô hình `TrackLookup` ở guide 02.

### D3. Ba field mới của profile đến từ đâu?

| Field | Nguồn |
|-------|-------|
| `followerCount`, `followingCount` | cột trong `users` (module `identity` sở hữu), chỉ-đọc từ Java |
| `isFollowedByMe` | port `FollowStateReader` do `identity` định nghĩa, `engagement` cài (đảo phụ thuộc, như `ViewerLikesReader`) |

### D4. Danh sách followers trả gì?

Chỉ `{userId, followedAt}` (xem hợp đồng). `engagement` không biết tên; app gọi `GET /users?ids=` cho cả trang. Tránh JOIN sang `users`
(ranh giới module) và dùng lại đúng endpoint batch mà `TrackCard`, comment cũng cần.

### D5. Chặn tự follow

Một quy tắc nghiệp vụ nên được bảo vệ ở mọi tầng: **domain** (đối tượng `Follow` không thể tồn tại nếu `follower == followee`),
**use case** (đổi lỗi domain thành `400`), **DB** (`CHECK`, lưới an toàn cuối nếu ai đó INSERT thẳng).

## 4. Vị trí trong kiến trúc

```
com.lasono.engagement
├── domain/        Follow, FollowRepository, exception/SelfFollowException
├── application/
│   ├── port/out/  UserLookup, FollowReader (phân trang)
│   └── usecase/   FollowUserUseCase, UnfollowUserUseCase, ListFollowersUseCase, ListFollowingUseCase,
│                  FollowResult, FollowPage, FollowEdge, PageCursor, UserNotFoundException
├── infrastructure/
│   ├── persistence/FollowPersistenceAdapter, FollowReaderJdbc
│   ├── persistence/FollowStateJdbcReader     (implements identity.application.port.out.FollowStateReader)
│   └── identity/UserLookupAdapter            (ACL → identity GetProfileUseCase)
└── presentation/  FollowController (+ thêm vào EngagementExceptionHandler)

com.lasono.identity   (thêm)
├── application/port/out/FollowStateReader, UserCounterRepository
├── application/usecase/AdjustUserCountersUseCase, GetProfilesUseCase (batch); sửa GetProfileUseCase, ProfileResult
├── domain/UserRepository + findAllById
└── infrastructure/event/UserCounterListener, persistence/UserCounterPersistenceAdapter; presentation/ sửa UserController

com.lasono.track      (thêm) totalCount cho tracks của một user + index owner
```

Phụ thuộc mới: `engagement.infrastructure → identity.application.usecase.GetProfileUseCase` và `→ identity.application.port.out.FollowStateReader`.
Quy tắc ArchUnit cần thêm: `moduleDoesNotDependOn(IDENTITY, ENGAGEMENT)` (đã có từ guide 02) và
`onlyInfrastructureMayUseOtherModules(ENGAGEMENT, IDENTITY)`.

## 5. Schema

```sql
-- V10__create_follows.sql
CREATE TABLE follows
(
    follower_id UUID NOT NULL,   -- the user who follows
    followee_id UUID NOT NULL,   -- the user who is followed
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_follows PRIMARY KEY (follower_id, followee_id),
    -- Last line of defence; the domain and the use case refuse it earlier.
    CONSTRAINT ck_follows_not_self CHECK (follower_id <> followee_id)
);

-- "Who follows X, newest first" (followers list) and keyset paging on (created_at, follower_id).
CREATE INDEX idx_follows_followee_created ON follows (followee_id, created_at DESC, follower_id DESC);
-- "Whom does X follow, newest first" (following list). The feed (guide 05) also looks up by follower_id.
CREATE INDEX idx_follows_follower_created ON follows (follower_id, created_at DESC, followee_id DESC);
```
```sql
-- V11__add_follow_counters_to_users.sql
ALTER TABLE users
    ADD COLUMN follower_count INT NOT NULL DEFAULT 0,
    ADD COLUMN following_count INT NOT NULL DEFAULT 0;

ALTER TABLE users
    ADD CONSTRAINT ck_users_follower_count_not_negative CHECK (follower_count >= 0),
    ADD CONSTRAINT ck_users_following_count_not_negative CHECK (following_count >= 0);
```
```sql
-- V12__add_owner_index_to_tracks.sql
-- "Tracks of one owner, newest first" (profile page, its totalCount, and the feed in guide 05).
CREATE INDEX idx_tracks_owner_created ON tracks (owner_id, created_at DESC, id DESC);
```

| Index | Lý do |
|-------|-------|
| PK `(follower_id, followee_id)` | Chặn follow trùng; trả lời "A có follow B không". |
| `idx_follows_followee_created` | PK không có `followee_id` ở đầu nên không giúp tìm followers của X; index này cũng đã sắp sẵn theo `created_at DESC` cho keyset. |
| `idx_follows_follower_created` | Tương tự cho danh sách "đang theo dõi" và cho feed. Thừa với PK về lọc, nhưng PK không sắp theo `created_at`. |
| `idx_tracks_owner_created` | Truy vấn track của một owner (hiện đang lọc `owner_id` rồi sort theo `created_at`) trở thành duyệt index đúng thứ tự, không sort. Kiểm chứng bằng `EXPLAIN` ở guide 05. |

Thêm `DELETE FROM follows` vào `PostgresIntegrationTest.cleanTestDatabase()`.

## 6. Các bước code theo thứ tự

### Bước 1. Migration + `postgresTest` hạ tầng
`FollowsMigrationPostgresTest`: `aUserCannotFollowThemselvesEvenWithADirectInsert` (CHECK), `theSameFollowTwiceIsRejected`, `countersStartAtZero`.

### Bước 2. Domain
```java
package com.lasono.engagement.domain;

public class Follow {
    // TODO: UserRef follower, UserRef followee
    public Follow(UserRef follower, UserRef followee) {
        // TODO: requireNonNull both; if equal -> throw new SelfFollowException()
    }
}

public interface FollowRepository {
    boolean addIfAbsent(Follow follow);            // true = new
    boolean remove(UserRef follower, UserRef followee);   // true = removed
}
```
`SelfFollowException extends RuntimeException`, message `"You cannot follow yourself"` (hợp đồng). Test trước: `FollowTest.aUserCannotFollowThemselves`,
`InMemoryFollowRepositoryTest` (như `InMemoryLikeRepositoryTest`).

### Bước 3. Application
```java
@Component
public class FollowUserUseCase {
    // ctor(FollowRepository, UserLookup, EventPublisher, Clock)

    @Transactional
    public FollowResult execute(UUID followerId, UUID followeeId) {
        // TODO 1: Follow follow = new Follow(new UserRef(followerId), new UserRef(followeeId));   // self -> SelfFollowException (400)
        // TODO 2: userLookup.requireExists(followeeId);                                          // unknown -> UserNotFoundException (404)
        // TODO 3: boolean added = follows.addIfAbsent(follow);
        // TODO 4: if (added) events.publish(new UserFollowed(followerId, followeeId, clock.instant()));
        // TODO 5: return new FollowResult(followeeId.toString(), true, userLookup.followerCountOf(followeeId));
        throw new UnsupportedOperationException("TODO");
    }
}
```
Thứ tự **1 trước 2** có chủ ý: tự follow trả `400` ngay cả khi id hợp lệ (không cần hỏi DB). Test ghi lại thứ tự này:
`execute_followingYourselfIsBadRequestAndAsksNobody` (fake `UserLookup` đếm số lần được gọi = 0).

`UnfollowUserUseCase`: user lạ → `404`; bỏ follow người chưa follow (kể cả chính mình) → vẫn `200 following:false` mà không sự kiện.

`ListFollowersUseCase` / `ListFollowingUseCase`: kiểm tra user tồn tại (`404`), giải mã cursor, lấy `limit + 1` dòng, cắt, tạo `nextCursor`.
Cấu trúc **y hệt** `ListTracksUseCase.page(...)`: hãy mở nó ra và mô phỏng.
```java
public record FollowEdge(UUID userId, Instant followedAt) {}
public record FollowPage(List<FollowEdge> items, String nextCursor) {}

public interface FollowReader {
    List<FollowEdge> followersOf(UUID userId, PagePosition after, int limit);
    List<FollowEdge> followingOf(UUID userId, PagePosition after, int limit);
}
```
`PageCursor`/`PagePosition`: bản chép của `TrackCursor`/`TrackPosition` cho engagement (`micros:uuid`, Base64URL, `400` khi hỏng). Bạn sẽ cần cùng
một thứ ở `discovery` (guide 05): khi đó (lần thứ ba) hãy rút ra `shared.paging` (*rule of three*), đừng làm sớm hơn.

### Bước 4. Infrastructure `engagement`
- `FollowPersistenceAdapter` (`JdbcTemplate`): `INSERT INTO follows (follower_id, followee_id) VALUES (?, ?) ON CONFLICT DO NOTHING`; `DELETE ... WHERE follower_id=? AND followee_id=?`.
- `FollowReaderJdbc`: truy vấn keyset
  ```sql
  SELECT follower_id AS user_id, created_at FROM follows
  WHERE followee_id = ? AND (created_at, follower_id) < (?, ?)      -- bỏ điều kiện này ở trang đầu
  ORDER BY created_at DESC, follower_id DESC
  LIMIT ?
  ```
  Đọc `created_at` bằng `rs.getObject("created_at", OffsetDateTime.class).toInstant()`; truyền lại tham số cũng bằng `OffsetDateTime` (pgjdbc không nhận `Instant`).
  Cho `followingOf`: đổi vai trò hai cột.
- `FollowStateJdbcReader` implements `FollowStateReader` của identity: `SELECT followee_id FROM follows WHERE follower_id = :viewer AND followee_id IN (:ids)`.
- `UserLookupAdapter`: `requireExists` gọi `GetProfileUseCase.execute(id, null)`, bắt `ProfileNotFoundException`; `followerCountOf` đọc `followerCount` của profile.

### Bước 5. Phía `identity`: bộ đếm, profile, batch
1. **`UserJpaEntity`**: thêm `follower_count`, `following_count` với `insertable = false, updatable = false` (lý do y như `TrackJpaEntity` ở guide 02).
   `UserPersistenceAdapter.save` truyền `0, 0`. Test `postgresTest`: `renamingAUserDoesNotResetItsCounters` (đổi tên qua `UpdateProfileUseCase` khi count đang là 3).
2. **Bộ đếm**:
   ```java
   // identity/application/port/out/UserCounterRepository.java
   public interface UserCounterRepository {
       /** Changes both counters of one follow in a fixed order, so that two opposite follows cannot deadlock. */
       void followAdded(UUID followerId, UUID followeeId);
       void followRemoved(UUID followerId, UUID followeeId);
   }
   ```
   Adapter (`JdbcTemplate`) — **khung bắt buộc**:
   ```java
   // 1) Lock both rows in id order.   SELECT id FROM users WHERE id IN (?, ?) ORDER BY id FOR UPDATE
   // 2) UPDATE users SET follower_count  = follower_count  + ? WHERE id = <followee>
   // 3) UPDATE users SET following_count = following_count + ? WHERE id = <follower>
   ```
   `UserCounterListener` (`@EventListener` cho `UserFollowed`/`UserUnfollowed`) → `AdjustUserCountersUseCase`.
3. **`FollowStateReader`** (port của identity): `Set<UUID> followedAmong(UUID viewerId, Collection<UUID> userIds)`.
4. **Profile**: `ProfileResult` thành `(userId, displayName, followerCount, followingCount, isFollowedByMe)`; `GetProfileUseCase.execute(userId, viewerId)`.
   `isFollowedByMe` = `viewerId != null && !viewerId.equals(userId) && followState.followedAmong(viewerId, [userId]).contains(userId)`.
   `UserController.profile` nhận `Principal principal` (có thể `null`) → `viewerOf(principal)` như `TrackController`.
5. **Batch** `GET /api/v1/users?ids=`:
   ```java
   @GetMapping("/api/v1/users")
   public ProfilesResult profiles(@RequestParam("ids") List<UUID> ids, Principal principal) {
       // TODO: getProfilesUseCase.execute(ids, viewerOf(principal))  — dedupe, > 50 -> 400, unknown ids skipped
       return null;
   }
   ```
   `UserRepository.findAllById(Collection<UserId>)` (thêm vào interface + `InMemoryUserRepository` + adapter dùng `JpaRepository.findAllById`).
   Thêm `TooManyIdsException` + handler `400` trong `IdentityExceptionHandler`. Nhớ rằng id sai định dạng do Spring tự đổi thành `400`; hãy viết test để chắc.
6. **SecurityConfig** (đặt **trước** dòng `anyRequest()` và cẩn thận thứ tự với `/users/me`):
   ```java
   .requestMatchers(HttpMethod.GET, "/api/v1/users").permitAll()                              // batch
   .requestMatchers(HttpMethod.GET, "/api/v1/users/*/followers", "/api/v1/users/*/following").permitAll()
   ```
   `PUT`/`DELETE /api/v1/users/*/follow` không cần dòng nào: rơi xuống `authenticated()`. Test `SecurityConfigTest`: batch và followers mở cho người chưa đăng nhập; `follow` đóng.

### Bước 6. Presentation `engagement`
`FollowController`: `PUT`/`DELETE /api/v1/users/{id}/follow`, `GET /api/v1/users/{id}/followers`, `GET /api/v1/users/{id}/following`
(`@RequestParam cursor`, `limit`). `EngagementExceptionHandler` thêm: `SelfFollowException` → `400`, `UserNotFoundException` → `404`,
`InvalidPageRequestException` (bản của engagement) → `400`.

### Bước 7. `totalCount` cho tracks của một user (module `track`)
`TrackSummaryReader.countVisibleOfOwner(UUID ownerId, UUID viewerId)`; SQL
`SELECT count(*) FROM tracks WHERE owner_id = :owner AND (visibility = 'PUBLIC' OR owner_id = :viewer)`.
`ListTracksUseCase.executeForOwner` trả record mới `UserTracksResult(items, nextCursor, totalCount)` (đừng thêm `totalCount` vào `ListTracksResult`
dùng chung với `GET /tracks`: field `null` sẽ lọt vào JSON của endpoint đó). Test trước: `theTotalCountsOnlyWhatTheViewerMaySee`
(đa dạng: chủ thấy 3, người lạ thấy 2 vì 1 private).

### Bước 8. Đăng ký ArchUnit, chạy toàn bộ, commit
Commit gợi ý: `feat: follows and counters migrations`, `feat: follow domain refuses a self follow`, `feat: follow and unfollow use cases`,
`feat: follow persistence`, `feat: follower and following counters on users`, `feat: profile shows follow counts`, `feat: batch profiles endpoint`,
`feat: follow endpoints`, `feat: total count of the tracks of a user`.

## 7. Trace-through cụ thể

**Dữ liệu:** `A = aaaa…`, `B = bbbb…` (so sánh UUID: `aaaa… < bbbb…`). Cả hai có `follower_count = following_count = 0`.

### Trace 1. Deadlock khi A và B follow nhau cùng lúc (code SAI: không có thứ tự)

```
t1  R1 (A follows B): UPDATE users SET follower_count  = follower_count  + 1 WHERE id = B   → giữ khoá hàng B
t2  R2 (B follows A): UPDATE users SET follower_count  = follower_count  + 1 WHERE id = A   → giữ khoá hàng A
t3  R1: UPDATE users SET following_count = following_count + 1 WHERE id = A                 → ĐỢI R2 (A)
t4  R2: UPDATE users SET following_count = following_count + 1 WHERE id = B                 → ĐỢI R1 (B)
t5  (sau deadlock_timeout = 1 giây) PostgreSQL phát hiện vòng chờ, huỷ một transaction:
    ERROR: deadlock detected   (SQLSTATE 40P01)  → request đó nhận 500, like/follow của nó rollback
```
### Trace 2. Cùng tình huống, code ĐÚNG (khoá theo thứ tự id)

```
t1  R1: SELECT id FROM users WHERE id IN (A,B) ORDER BY id FOR UPDATE   → khoá A rồi B
t2  R2: SELECT id FROM users WHERE id IN (A,B) ORDER BY id FOR UPDATE   → ĐỢI khoá A (chưa có gì trong tay)
t3  R1: hai UPDATE; COMMIT                                              → nhả A, B
t4  R2: lấy A rồi B; hai UPDATE; COMMIT
```
Không ai giữ khoá mà lại đợi khoá của người đang đợi mình, nên không thể có vòng. Kết quả cuối: `A` (follower 1, following 1), `B` (follower 1, following 1).
**Test** `oppositeFollowsAtTheSameTimeBothSucceed`: 2 thread + `CountDownLatch`, lặp 50 lần, kỳ vọng không lần nào ném `CannotAcquireLockException`/deadlock.

### Trace 3. Phân trang followers bằng keyset, có người follow mới giữa hai trang

`user X` có 5 followers với `created_at` (mới → cũ): `F5 (10:05)`, `F4 (10:04)`, `F3 (10:03)`, `F2 (10:02)`, `F1 (10:01)`. `limit = 2`.

```
GET /users/X/followers?limit=2
  SQL: ... ORDER BY created_at DESC, follower_id DESC LIMIT 3  → F5, F4, F3   (3 = limit + 1)
  F3 chỉ để biết "còn trang sau" → trả [F5, F4], nextCursor = encode(F4.created_at, F4.id)
      (ví dụ F4.created_at = 2026-10-08T10:04:00Z → micros 1791453840000000, cursor = Base64URL("1791453840000000:<uuid của F4>"))
-- Giữa hai trang, F6 follow X lúc 10:06.
GET /users/X/followers?limit=2&cursor=…F4…
  SQL: ... AND (created_at, follower_id) < ('10:04', F4) ... LIMIT 3 → F3, F2, F1
  trả [F3, F2], nextCursor = encode(F2) ; không có F5, F4 trùng, không mất ai
```
Với `OFFSET 2` thay cho keyset, trang hai sẽ bắt đầu từ vị trí 3 của danh sách *mới* `[F6, F5, F4, F3, F2, F1]` → `F4, F3`: **F4 bị trả hai lần**. Đó là lý do chọn keyset.

## 8. Test cần viết

| Loại | Test | Kiểm tra / ca biên |
|------|------|--------------------|
| Domain | `FollowTest.aUserCannotFollowThemselves` | cùng id → `SelfFollowException` |
| Fake | `InMemoryFollowRepositoryTest.*` | như guide 02 |
| Use case | `FollowUserUseCaseTest.execute_shouldStoreTheFollowAndPublishUserFollowed` | đường chính |
| | `...execute_twice_shouldPublishOnlyOnce` | idempotent |
| | `...execute_followingYourselfIsBadRequestAndAsksNobody` | chặn sớm, không gọi `UserLookup` |
| | `...execute_anUnknownUserIsNotFound` | 404 |
| | `UnfollowUserUseCaseTest.unfollow_whenNotFollowing_shouldPublishNothing` | idempotent |
| | `ListFollowersUseCaseTest` — trang đầu, trang cuối `nextCursor == null`, cursor hỏng → lỗi, `limit < 1` → lỗi, `limit > 50` bị cắt, user lạ → 404 | khớp `ListTracksUseCaseTest` |
| Identity | `GetProfileUseCaseTest.isFollowedByMeIsFalseForYourselfAndForNobody` | 3 ca |
| | `GetProfilesUseCaseTest.moreThanFiftyIdsAreRefused`, `...unknownIdsAreSkipped`, `...duplicatesAreCountedOnce` | batch |
| | `AdjustUserCountersUseCaseTest` | gọi đúng repository |
| postgres | `FollowPersistenceAdapterPostgresTest.addingTheSameFollowTwiceStoresOneRow`, `...twoRequestsAtTheSameTimeStoreOneFollow` | unique |
| | `UserCounterPostgresTest.oppositeFollowsAtTheSameTimeBothSucceed` | **deadlock** (mutation check: bỏ `ORDER BY id` → thấy đỏ, có thể không ổn định, chạy 50 lần) |
| | `...countersMatchTheNumberOfRows` | `follower_count == COUNT(*)` |
| | `...renamingAUserDoesNotResetItsCounters` | `updatable = false` |
| | `FollowReaderJdbcPostgresTest.followersAreNewestFirstAndPagesDoNotOverlap` | trace 3, dùng dữ liệu cố định |
| | `...aNewFollowerBetweenTwoPagesDoesNotRepeatAnyone` | keyset vs offset |
| HTTP | `FollowOverHttpPostgresTest` | luồng đầy đủ + 400 tự follow + 404 + 401 + `GET /users?ids=` + profile 3 field |
| Security | `SecurityConfigTest.batchProfilesAndFollowersArePublic`, `...followNeedsALogin` | route |
| Track | `UserTracksPostgresTest.theTotalCountsOnlyWhatTheViewerMaySee` | `totalCount` |
| Arch | như guide 02 | module mới |

## 9. Lỗi thường gặp

| Lỗi | Dấu hiệu | Sửa |
|-----|----------|-----|
| Deadlock hiếm gặp | 500 ngẫu nhiên khi nhiều người follow nhau | Thứ tự khoá cố định (trace 2). |
| `/users/me` bị khớp bởi `/users/*` hoặc `/users?ids=` che nhau | Lộ email hoặc `401` bất ngờ | `SecurityConfigTest` giữ thứ tự: `/users/me` → `authenticated()` **trước** `/users/*`. Phase 4 đã gặp lỗi này. |
| `isFollowedByMe` luôn `false` | UI không hiện "Đang theo dõi" | App phải gửi Bearer cho `GET /users/{id}`. Ở Phase 4 app **cố ý không** gửi token cho route này; `HttpUserRepository` của UI mới đã đổi (dùng `sendWithToken`). Backend cũng phải lấy `Principal`. |
| Phản hồi rỗng cho `GET /users?ids=` | `[]` dù id đúng | Quên dedupe/`findAllById` nhận `UserId` mà bạn truyền `UUID`. |
| `count` âm | `CHECK` đỏ khi unfollow | Unfollow phát sự kiện dù `remove` trả `false`. |
| Cursor trang 2 trùng/sót | Mốc thời gian lệch micro giây | Giữ `micros` (xem `TrackCursor`); đừng dùng `Instant.toString()`. |
| Danh sách chậm | `EXPLAIN` có `Sort` | Thiếu `idx_follows_followee_created`. |
| `GET /users/{id}/followers` trả 401 | App chưa đăng nhập vẫn xem được | Quên `permitAll` cho route đó. |

## 10. Kiểm tra thủ công

Dùng lại `BASE`, `TOKEN_A`, `TOKEN_B`, hàm `json` ở guide 02. Lấy id: `ID_A=$(curl -s $BASE/users/me -H "Authorization: Bearer $TOKEN_A" | json "['userId']")`, tương tự `ID_B`.

| # | Lệnh | Kỳ vọng |
|---|------|---------|
| 1 | `curl -s -X PUT $BASE/users/$ID_A/follow -H "Authorization: Bearer $TOKEN_B"` | `200 {"userId":"$ID_A","following":true,"followerCount":1}` |
| 2 | lặp lại 1 | giống hệt, `followerCount` vẫn `1` |
| 3 | `curl -s $BASE/users/$ID_A -H "Authorization: Bearer $TOKEN_B"` | `followerCount:1, followingCount:0, isFollowedByMe:true` |
| 4 | `curl -s $BASE/users/$ID_A` (không token) | `isFollowedByMe:false` |
| 5 | `curl -i -X PUT $BASE/users/$ID_A/follow -H "Authorization: Bearer $TOKEN_A"` | `400` `You cannot follow yourself` |
| 6 | `curl -i -X PUT $BASE/users/00000000-0000-0000-0000-000000000000/follow -H "Authorization: Bearer $TOKEN_A"` | `404` |
| 7 | `curl -s "$BASE/users/$ID_A/followers"` | `{"items":[{"userId":"$ID_B","followedAt":"…Z"}],"nextCursor":null}` |
| 8 | `curl -s "$BASE/users/$ID_B/following?limit=1"` | một phần tử, `nextCursor:null` |
| 9 | `curl -s "$BASE/users?ids=$ID_A,$ID_B,00000000-0000-0000-0000-000000000000"` | 2 phần tử (id lạ bị bỏ) |
| 10 | `curl -i "$BASE/users?ids=abc"` | `400` |
| 11 | `curl -s -X DELETE $BASE/users/$ID_A/follow -H "Authorization: Bearer $TOKEN_B"` | `following:false, followerCount:0`; lặp lại → vẫn `0` |
| 12 | `curl -s "$BASE/users/$ID_A/tracks" \| json "['totalCount']"` | số track công khai của A |
| 13 | Đối chiếu: `SELECT follower_count, (SELECT count(*) FROM follows WHERE followee_id=u.id) FROM users u WHERE id='$ID_A'` | hai số bằng nhau |

**Kịch bản UI** (tắt `FAKE_FOLLOWS`): đăng nhập B → mở profile A → bấm *Theo dõi* → nút đổi thành *Đang theo dõi* ngay, số follower `+1`; reload trang vẫn đúng;
mở danh sách Followers của A thấy B (đúng tên); đăng xuất → profile A không có trạng thái theo dõi; bấm *Theo dõi* khi chưa đăng nhập → mời đăng nhập.

## 11. Câu hỏi tự kiểm tra

<details><summary>Hiện đáp án gợi ý sau khi tự trả lời</summary>

1. **Vì sao một lần follow có thể gây deadlock còn một lần like thì không?** Follow sửa hai hàng `users`; hai request ngược chiều lấy khoá theo thứ tự ngược nhau → vòng chờ. Like chỉ sửa một hàng.
2. **Cách sửa deadlock chuẩn?** Luôn lấy khoá theo thứ tự cố định (sắp theo id).
3. **Vì sao chặn tự follow ở cả domain lẫn DB?** Domain cho lỗi rõ và test nhanh; `CHECK` bảo vệ khi có ai INSERT trực tiếp hoặc sau này có code khác ghi vào bảng.
4. **Vì sao followers chỉ trả `userId`?** `engagement` không được đọc `users`; app ghép tên bằng `GET /users?ids=` (một request cho cả trang).
5. **Keyset khác `OFFSET` thế nào khi có bản ghi mới chen vào?** Keyset neo vào giá trị của dòng cuối nên không trùng/sót; `OFFSET` đếm vị trí nên bị lệch.
6. **Vì sao lấy `limit + 1` dòng?** Để biết còn trang sau mà không phải `COUNT(*)`.
7. **`isFollowedByMe` khi xem chính mình là gì? Vì sao?** `false`: không thể tự follow nên "đang theo dõi" vô nghĩa.
8. **Vì sao `GET /users/{id}` ở Phase 4 không gửi token mà bây giờ lại gửi?** Trước đó không cần cá nhân hoá; giờ `isFollowedByMe` cần biết người xem, và `sendWithToken` xử lý token hết hạn bằng refresh + thử lại.

</details>

## 12. Bài tập mở rộng

1. **Quan hệ hai chiều ("bạn bè"):** thêm `isFollowingMe` vào profile (người này có follow mình không?) và một tab "Bạn bè" (hai bên cùng follow). Tìm truy vấn dùng self-join trên `follows` và chỉ ra index nào được dùng.
2. **Chặn (block) người dùng:** bảng `blocks`; người bị chặn không follow/comment được. Quyết định xem quy tắc nằm ở domain hay use case, và `404` hay `403`.
