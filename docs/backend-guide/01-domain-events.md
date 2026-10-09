# Guide 01: Domain events (làm đầu tiên)

> Phase 5 · Cần xong trước: không (chỉ cần Phase 4) · Mở khoá: guide 02, 03, 04
> Đọc [`00-how-to-use.md`](00-how-to-use.md) trước nếu chưa đọc.

## 1. Mục tiêu và nghiệm thu

**Làm gì.** Cho phép một module báo "có chuyện vừa xảy ra" mà **không biết ai quan tâm**, và module khác phản ứng mà **không
import class của module kia**. Ví dụ: `engagement` ghi một lượt like rồi phát `TrackLiked`; module `track` nghe sự kiện đó và
tăng `tracks.like_count`.

**Vì sao cần.** Quy tắc ArchUnit của dự án cấm `track` biết `engagement` (và `identity` biết `track`...). Nhưng bộ đếm
`likeCount` hiển thị ở `track`, còn lượt like sinh ra ở `engagement`. Sự kiện là cầu nối một chiều:
*người phát* không phụ thuộc *người nghe*.

**Xong khi:**

- [ ] Gói `com.lasono.shared.event` có các sự kiện (record thuần Java, không import Spring/JPA).
- [ ] Có port phát sự kiện ở tầng application và một adapter dùng `ApplicationEventPublisher`.
- [ ] Có fake `RecordingEventPublisher` để unit test use case mà không cần Spring.
- [ ] Một `postgresTest` chứng minh: listener đồng bộ (`@EventListener`) **chạy trong cùng transaction** — listener ném lỗi thì
      toàn bộ (kể cả dữ liệu đã ghi trước đó) bị rollback.
- [ ] ArchUnit: `shared` không phụ thuộc module nào và không dùng framework; `track`/`identity` không phụ thuộc `engagement`.
- [ ] Bạn giải thích được (viết 5 dòng) khi nào chọn `@EventListener` và khi nào `@TransactionalEventListener(AFTER_COMMIT)`.

## 2. Kiến thức cần biết trước

| Khái niệm | Đọc ở đâu |
|-----------|-----------|
| `ApplicationEventPublisher` và `@EventListener` (đồng bộ, cùng thread, cùng transaction) | [Spring: Standard and custom events](https://docs.spring.io/spring-framework/reference/core/beans/context-introduction.html#context-functionality-events) |
| `@TransactionalEventListener` và các `phase` (`BEFORE_COMMIT`, `AFTER_COMMIT`, `AFTER_ROLLBACK`) | [Spring: Transaction-bound events](https://docs.spring.io/spring-framework/reference/data-access/transaction/event.html) |
| Propagation của `@Transactional` (`REQUIRED`, `REQUIRES_NEW`) | [Spring: Transaction propagation](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html) |
| Spring Modulith events (phương án thay thế, có sẵn outbox) | [Spring Modulith: Working with Application Events](https://docs.spring.io/spring-modulith/reference/events.html) |
| Transactional outbox (chỉ đọc để hiểu, v1.0 không làm) | [microservices.io: Transactional outbox](https://microservices.io/patterns/data/transactional-outbox.html) |
| Shared kernel (DDD) | tìm "shared kernel domain-driven design" |

Ba điều cần nắm chắc:

1. `publishEvent(...)` của Spring **không đưa sự kiện vào hàng đợi**. Nó gọi từng listener ngay tại chỗ, theo thứ tự, trên **cùng
   thread**; `publishEvent` chỉ trả về khi mọi listener chạy xong. Vì vậy listener `@EventListener` *tham gia* transaction đang
   mở của người phát, và exception của listener bay ngược lên người phát.
2. `@TransactionalEventListener(AFTER_COMMIT)` thì khác: sự kiện được giữ lại cho đến khi transaction của người phát **commit
   xong** mới gọi listener. Nếu không có transaction đang mở, listener **không chạy** (trừ khi `fallbackExecution = true`).
3. Một sự kiện là **sự thật đã xảy ra** (quá khứ: `TrackLiked`), khác với *lệnh* (`IncreaseLikeCount`). Người phát không được
   mong đợi hay chờ kết quả từ người nghe.

## 3. Quyết định thiết kế

### 3.1 Sự kiện nằm ở đâu?

| Phương án | Mô tả | Được | Mất |
|-----------|-------|------|-----|
| A. **Shared kernel** `com.lasono.shared.event` *(khuyến nghị)* | Một gói chung chỉ chứa record sự kiện. Mọi module được phụ thuộc vào `shared`, `shared` không phụ thuộc ai. | Đơn giản, ArchUnit dễ viết (một quy tắc), listener không cần biết module phát. | Có một "chỗ chung" dễ phình ra; mọi thay đổi sự kiện ảnh hưởng nhiều module. |
| B. Sự kiện thuộc module phát (`com.lasono.engagement.event`) | Người nghe import trực tiếp gói `event` của người phát. | Rõ ai sở hữu sự kiện. | Phải nới quy tắc "module không biết nhau" thành "chỉ được biết gói `event` của nhau"; dễ trượt thành phụ thuộc thật. |
| C. Spring Modulith (`@ApplicationModuleListener`, named interface) | Thư viện kiểm tra ranh giới module và lưu sự kiện vào bảng. | Có outbox sẵn, kiểm tra kiến trúc tự động. | Thêm thư viện và khái niệm mới; trùng chức năng với ArchUnit đang dùng. |

**Chọn A cho LaSono** vì chỉ có 4 module, đội 1 người, và ta muốn *thấy* cơ chế (không để thư viện giấu đi). Khi số sự kiện
vượt ~15 hoặc có nhiều người, cân nhắc B hoặc C.

### 3.2 Sự kiện là record ở Domain hay Application?

Sự kiện là **sự thật của domain** nên về ý niệm thuộc Domain. Nhưng nó được chia sẻ giữa module nên không thể nằm trong
`domain/` của module nào. Lời giải: `shared.event` là một "domain nhỏ chung": record thuần Java, **chỉ chứa id, thời điểm và
dữ liệu tối thiểu**, không chứa entity. Quy tắc ArchUnit `domainIsFrameworkFree` áp dụng tương tự cho nó.

Chứa gì trong sự kiện? Chỉ những gì người nghe *chắc chắn cần* (id). Nếu nhét cả `Track` vào, người nghe sẽ phụ thuộc cấu trúc
của nó. Nếu người nghe cần thêm dữ liệu, nó tự hỏi qua port của nó.

### 3.3 Phát sự kiện bằng gì?

| Phương án | Ghi chú |
|-----------|---------|
| `ApplicationEventPublisher` dùng thẳng trong use case | Ngắn nhất, nhưng use case (Application) gắn với Spring và khó test. |
| **Port `EventPublisher` + adapter Spring** *(khuyến nghị)* | Use case chỉ biết interface `EventPublisher` (giống `PasswordHasher`, `AudioStorage`). Test dùng fake ghi lại sự kiện. Khớp quy ước port/adapter hiện có. |

### 3.4 `@EventListener` hay `@TransactionalEventListener(AFTER_COMMIT)`?

Đây là quyết định quan trọng nhất của guide. Cùng một sự kiện `TrackLiked`, hai cách cho hai hệ quả khác nhau:

| | `@EventListener` (đồng bộ) | `@TransactionalEventListener(AFTER_COMMIT)` |
|---|---|---|
| Chạy khi nào | Ngay khi `publish`, **trong** transaction của người phát | Sau khi transaction của người phát đã commit |
| Listener ném lỗi | Lan ngược lên → người phát rollback **cả like lẫn bộ đếm** | Like đã commit; lỗi chỉ được log; bộ đếm **lệch** |
| Dữ liệu listener ghi | Commit/rollback **cùng** người phát (nguyên tử) | Nếu `@Transactional` mặc định (`REQUIRED`), listener *tham gia lại* transaction đã commit → **thay đổi không bao giờ được commit** (bẫy kinh điển). Phải `REQUIRES_NEW`. |
| Làm chậm người phát | Có (listener chạy trước khi trả lời) | Có, nhưng sau commit; có thể kết hợp `@Async` |
| Hợp với | Việc **phải nhất quán với** thao tác chính: bộ đếm, dọn dữ liệu liên quan | Việc **phụ**, chấp nhận mất: gửi thông báo, ghi log phân tích, làm nóng cache |

**LaSono dùng `@EventListener` đồng bộ cho mọi bộ đếm và dọn dẹp**, vì yêu cầu là "bộ đếm nhất quán" (PROJECT_STATUS Phase 5),
và cả hai bảng nằm trong **một database**, nên một transaction bao được tất cả. Đây là lợi thế của modular monolith so với
microservice: ta *được phép* dùng ACID thay vì eventual consistency.

### 3.5 Khi nào cần outbox? (giải thích, KHÔNG làm ở v1.0)

Outbox cần khi listener nằm ở **hệ thống khác** (Kafka, email, service khác) nên không dùng chung transaction được. Vấn đề
"dual write": ghi DB thành công nhưng gửi message thất bại (hoặc ngược lại). Outbox giải quyết bằng cách ghi sự kiện vào một
bảng `outbox` **trong cùng transaction** với dữ liệu, rồi một tiến trình riêng đọc bảng đó và gửi đi (at-least-once, nên người
nhận phải idempotent).

Dự án đã quyết định **hoãn Kafka** (xem `PROJECT_STATUS.md`). Mọi listener của Phase 5-6 ở cùng JVM và cùng DB, nên không cần
outbox. Bảng job `processing_jobs` của Phase 3 chính là một dạng "outbox/hàng đợi trong PostgreSQL" mà bạn đã tự làm: cùng ý tưởng.

## 4. Vị trí trong kiến trúc

```
com.lasono.shared.event            ◄── mọi module đều được phụ thuộc vào đây
   DomainEvent (interface)
   TrackLiked, TrackUnliked, UserFollowed, UserUnfollowed,
   CommentPosted, CommentDeleted, TrackDeleted

com.lasono.engagement (guide 02-04)
   application/port/out/EventPublisher          ← port
   infrastructure/event/SpringEventPublisher    ← adapter, dùng ApplicationEventPublisher

com.lasono.track  (người nghe)
   infrastructure/event/TrackCounterListener    ← @EventListener, gọi use case của track
   application/usecase/AdjustTrackCountersUseCase
```

| Class | Module | Layer |
|-------|--------|-------|
| `DomainEvent` và các record sự kiện | `shared` | (chung, tương đương Domain) |
| `EventPublisher` | `engagement` (và `track` cho `TrackDeleted`) | Application · port |
| `SpringEventPublisher` | mỗi module phát | Infrastructure |
| `TrackCounterListener` | `track` | Infrastructure (adapter *vào*) |
| `AdjustTrackCountersUseCase` | `track` | Application |

Listener nằm ở Infrastructure vì nó là **adapter vào** (giống controller là adapter vào ở Presentation): nhận tín hiệu từ bên
ngoài module và **gọi một use case**, không chứa logic. Điều này tránh `onlyInfrastructureUsesInfrastructure` bị vi phạm
(listener → use case là hướng được phép).

**Kiểm tra dependency rule:** `shared` không import module nào (sẽ thêm quy tắc), `track` → `shared` (được),
`engagement` → `shared` (được), `track` ✗ `engagement` (quy tắc mới). `domain` của từng module vẫn không import Spring.

## 5. Schema

Guide này **không có migration**. Sự kiện đồng bộ không cần bảng. (Bảng `outbox` chỉ xuất hiện nếu bạn làm bài tập mở rộng.)

## 6. Các bước code theo thứ tự

### Bước 1. Dựng gói `shared.event` và quy tắc ArchUnit (RED trước)

Viết test ArchUnit **trước**: trong `ArchitectureRules` thêm quy tắc, trong `ArchitectureTest` thêm bài kiểm tra, trong
`ArchitectureRulesTest` thêm ca "cố tình vi phạm" với lớp mẫu ở `src/test/java/archfixture/shared/`.

```java
// ArchitectureRules.java
/** The shared kernel holds plain events only: no framework, and no module may be imported into it. */
public static ArchRule sharedKernelIsIndependent(String sharedRoot, String... moduleRoots) {
    // TODO: noClasses().that().resideInAPackage(sharedRoot + "..")
    //       .should().dependOnClassesThat().resideInAnyPackage( org.springframework.., jakarta.persistence.., + module roots)
    throw new UnsupportedOperationException("TODO");
}
```

Kiểm chứng: `ArchitectureRulesTest` có hai ca: (1) lớp mẫu trong `archfixture.shared` import một lớp trong
`archfixture.alpha` → quy tắc phải **fail**; (2) lớp chỉ dùng `java.time`/`java.util` → quy tắc phải **pass**.

### Bước 2. Các record sự kiện

```java
package com.lasono.shared.event;

import java.time.Instant;

/** Something that has already happened. Named in the past tense, carries ids and the time, nothing else. */
public interface DomainEvent {
    Instant occurredAt();
}
```

```java
public record TrackLiked(UUID trackId, UUID userId, Instant occurredAt) implements DomainEvent {}
public record TrackUnliked(UUID trackId, UUID userId, Instant occurredAt) implements DomainEvent {}
public record UserFollowed(UUID followerId, UUID followeeId, Instant occurredAt) implements DomainEvent {}
public record UserUnfollowed(UUID followerId, UUID followeeId, Instant occurredAt) implements DomainEvent {}
public record CommentPosted(UUID commentId, UUID trackId, UUID authorId, Instant occurredAt) implements DomainEvent {}
public record CommentDeleted(UUID commentId, UUID trackId, Instant occurredAt) implements DomainEvent {}
// Phát bởi module track khi xoá track: engagement nghe để dọn likes/comments của track đó.
public record TrackDeleted(UUID trackId, UUID ownerId, Instant occurredAt) implements DomainEvent {}
```

Mỗi record nên có **compact constructor** `Objects.requireNonNull` cho từng field (sự kiện thiếu id là lỗi lập trình, hãy
phát hiện ngay lúc tạo). Test: `DomainEventsTest` — `aTrackLikedEventWithoutATrackIdIsRejected`, v.v.

### Bước 3. Port và adapter phát sự kiện

```java
// engagement/application/port/out/EventPublisher.java
public interface EventPublisher {
    void publish(DomainEvent event);
}
```

```java
// engagement/infrastructure/event/SpringEventPublisher.java
@Component
public class SpringEventPublisher implements EventPublisher {

    private final ApplicationEventPublisher publisher;

    // TODO: constructor

    @Override
    public void publish(DomainEvent event) {
        // TODO: delegate to publisher.publishEvent(event)
    }
}
```

> `engagement` chưa tồn tại: tạo khung module ở guide 02 rồi quay lại, hoặc tạm đặt port + adapter ở module `track` để phát
> `TrackDeleted`. Cả hai module đều cần một `EventPublisher` riêng (mỗi module một port, vì module không import nhau). Chép
> 5 dòng này hai lần còn tốt hơn kéo một module phụ thuộc vào module kia.

Fake dùng cho unit test (đặt trong `src/test/java/.../usecase/`, đúng phong cách `FakePasswordHasher`):

```java
public class RecordingEventPublisher implements EventPublisher {
    private final List<DomainEvent> published = new ArrayList<>();
    @Override public void publish(DomainEvent event) { /* TODO: add */ }
    public List<DomainEvent> published() { /* TODO: copy */ return null; }
}
```

### Bước 4. Một listener đồng bộ thử nghiệm và bài kiểm chứng transaction

Chưa cần listener thật. Viết `postgresTest` với một listener **chỉ tồn tại trong test**:

```java
@TestConfiguration
static class ProbeConfig {
    @Bean ProbeListener probeListener() { return new ProbeListener(); }
}

static class ProbeListener {
    boolean failNext;
    @EventListener
    void on(TrackLiked event) {
        // TODO: ghi một dòng vào bảng bất kỳ bằng JdbcTemplate (ví dụ UPDATE tracks ...), rồi nếu failNext thì throw
    }
}
```

Kịch bản (dùng `TransactionTemplate` để mở transaction trong test): ghi một dòng, `publish(TrackLiked)`, listener ném lỗi →
đọc lại DB → dòng đầu **không còn**. Xem trace ở mục 7.

### Bước 5. Chạy `./gradlew test` và `postgresTest`; commit

Mỗi commit một cụm: `test: shared kernel architecture rule`, `feat: domain events of the shared kernel`,
`feat: event publisher port and Spring adapter`, `test: listeners join the transaction of the publisher`.

## 7. Trace-through cụ thể

**Dữ liệu:** track `T` có `like_count = 5`, user `A` chưa like. Bảng `likes` rỗng cho cặp (A, T).

**Trường hợp 1: listener đồng bộ thành công**

```
t0  PUT /tracks/T/like (A)                      LikeTrackUseCase.execute()          [@Transactional begin  ── TX#1]
t1  INSERT INTO likes (A,T) ON CONFLICT DO NOTHING → 1 row                           (chưa commit, chỉ TX#1 thấy)
t2  eventPublisher.publish(TrackLiked(T, A))    → ApplicationEventPublisher.publishEvent
t3    └─ TrackCounterListener.on(TrackLiked)    → UPDATE tracks SET like_count = like_count + 1 WHERE id = T
                                                  like_count: 5 → 6 (chưa commit, vẫn TX#1)
t4  publishEvent trả về; use case trả LikeResult
t5  COMMIT TX#1                                 → hàng likes (A,T) VÀ like_count = 6 cùng xuất hiện
```
Một người khác đọc ở t3 vẫn thấy `5` (READ COMMITTED: chưa commit thì chưa thấy), và thấy `6` ngay sau t5. Không bao giờ có
trạng thái "có like nhưng count vẫn 5".

**Trường hợp 2: listener đồng bộ ném lỗi** (ví dụ `UPDATE` vi phạm `CHECK (like_count >= 0)`)

```
t3  UPDATE tracks ... → DataIntegrityViolationException
t3' exception bay lên qua publishEvent → qua LikeTrackUseCase
t4  Spring rollback TX#1                         → hàng likes (A,T) biến mất, like_count vẫn 5
t5  Client nhận 500; thử lại là an toàn vì chưa có gì thay đổi
```

**Trường hợp 3: cùng sự kiện nhưng `AFTER_COMMIT`**

```
t5  COMMIT TX#1                                 → likes có hàng (A,T); like_count vẫn 5
t6  listener AFTER_COMMIT chạy: UPDATE tracks ...
      - nếu listener @Transactional(REQUIRED): UPDATE chạy trong TX#1 ĐÃ commit → KHÔNG ai commit nó → count vẫn 5 (im lặng!)
      - nếu @Transactional(REQUIRES_NEW): TX#2 mới commit → count = 6, nhưng nếu TX#2 lỗi thì like tồn tại mà count = 5
```
Bài học: `AFTER_COMMIT` cho phép "like thành công, bộ đếm sai". Muốn sửa phải có outbox hoặc job đối soát.

## 8. Test cần viết

| Loại | Tên test | Kiểm tra gì |
|------|----------|-------------|
| Unit | `DomainEventsTest.aEventWithoutAnIdIsRejected` (tham số hoá cho 7 record) | compact constructor chặn null |
| Unit | `DomainEventsTest.everyEventKnowsWhenItHappened` | `occurredAt()` trả đúng thời điểm truyền vào |
| Unit | `RecordingEventPublisherTest.itKeepsEventsInTheOrderTheyWerePublished` | test fake giữ thứ tự |
| ArchUnit | `ArchitectureTest.sharedKernelDependsOnNoModule` | quy tắc trên code thật |
| ArchUnit | `ArchitectureRulesTest` — 2 ca (vi phạm → fail, hợp lệ → pass) | quy tắc không "xanh giả" |
| Postgres | `SpringEventPublisherPostgresTest.aSynchronousListenerSeesTheEventBeforePublishReturns` | listener đã chạy khi `publish` trả về |
| Postgres | `...aListenerThatFailsRollsBackTheWritesOfThePublisher` | **ca biên chính**: rollback cả phần ghi trước đó |
| Postgres | `...aListenerWritesInTheTransactionOfThePublisher` | trong test, `TransactionSynchronizationManager.isActualTransactionActive()` là `true` trong listener |
| Postgres | `...anAfterCommitListenerRunsOnlyWhenThePublisherCommits` | rollback → listener AFTER_COMMIT **không** chạy |
| Postgres | `...anAfterCommitListenerThatJoinsTheTransactionLosesItsWrite` | minh hoạ bẫy `REQUIRED` (viết để *học*, giữ lại làm tài liệu sống) |

Thêm `@RecordApplicationEvents` (spring-test) nếu muốn đếm sự kiện đã phát mà không viết listener.

## 9. Lỗi thường gặp

| Lỗi | Dấu hiệu | Cách nhận ra / sửa |
|-----|----------|--------------------|
| Listener không được gọi | Sự kiện phát nhưng không có gì xảy ra | Listener không phải bean (thiếu `@Component`), hoặc kiểu tham số của `on(...)` khác kiểu sự kiện phát. |
| `@TransactionalEventListener` không chạy | Test không thấy gì | Không có transaction đang mở khi `publish` (ví dụ test không dùng `TransactionTemplate`). Thêm `fallbackExecution = true` chỉ khi chủ ý. |
| Count không đổi dù không lỗi | `AFTER_COMMIT` + `@Transactional` mặc định | Dùng `REQUIRES_NEW` hoặc quay lại `@EventListener` cho việc cần nhất quán. |
| Vòng phụ thuộc bean | App không khởi động: "circular reference" | Listener gọi use case, use case lại phát sự kiện mà chính listener xử lý. Tách sự kiện, đừng cho listener phát lại sự kiện cùng loại. |
| Listener làm chậm mọi request | Latency tăng | Listener đồng bộ cộng dồn thời gian. Giữ listener chỉ một `UPDATE`; việc nặng đẩy sang job. |
| Nhét entity vào sự kiện | Người nghe phụ thuộc cấu trúc entity của người phát | Chỉ id + thời điểm. |
| Quên `occurredAt` lấy từ `Clock` | Test không cố định được thời gian | Use case nhận `Clock` (như `LoginUseCase`), gọi `clock.instant()`. |

## 10. Kiểm tra thủ công

Guide này chưa có endpoint. Kiểm tra thủ công thật sự nằm ở guide 02 (like). Ở đây chỉ cần:

```bash
cd backend && ./gradlew test --rerun && ./gradlew postgresTest --rerun   # tất cả xanh
cd backend && ./gradlew test --tests '*ArchitectureTest*'                # quy tắc shared nằm trong đó
```

## 11. Câu hỏi tự kiểm tra

<details><summary>Hiện đáp án gợi ý sau khi tự trả lời</summary>

1. **`publishEvent` của Spring có phải hàng đợi không?** Không. Nó gọi listener ngay, cùng thread, và chỉ trả về khi listener xong.
2. **Vì sao bộ đếm dùng `@EventListener` mà không dùng `AFTER_COMMIT`?** Vì cần like và count commit cùng nhau; `AFTER_COMMIT` cho phép trạng thái "có like, count sai" nếu listener lỗi.
3. **Listener `AFTER_COMMIT` có `@Transactional` mặc định ghi dữ liệu thì chuyện gì xảy ra?** Nó tham gia transaction đã commit; thay đổi không bao giờ được commit.
4. **Vì sao event nằm ở `shared` mà không nằm ở `engagement`?** Để `track` nghe được mà không import `engagement`; quy tắc ArchUnit giữ ranh giới.
5. **Vì sao event chỉ chứa id?** Tránh người nghe phụ thuộc cấu trúc entity; nếu cần thêm, tự hỏi qua port.
6. **Outbox giải quyết vấn đề gì? Vì sao chưa cần?** Dual write giữa DB và hệ thống ngoài; mọi người nghe hiện cùng DB nên một transaction đủ.
7. **Nếu listener của `track` bị lỗi thì like có thành công không?** Không: lỗi lan lên, transaction rollback, client nhận 500 và có thể thử lại.
8. **Sự kiện khác lệnh ở điểm nào?** Sự kiện là sự thật đã xảy ra (quá khứ), người phát không quan tâm ai nghe; lệnh yêu cầu một người cụ thể làm gì.

</details>

## 12. Bài tập mở rộng

1. **Outbox thử nghiệm:** thêm bảng `outbox(id, type, payload jsonb, created_at, processed_at)`; ghi sự kiện vào đó trong cùng
   transaction và viết một `@Scheduled` job đọc `WHERE processed_at IS NULL ... FOR UPDATE SKIP LOCKED` (giống hàng đợi
   Phase 3) để "gửi" ra log. Phân biệt at-least-once với exactly-once.
2. **Thử Spring Modulith:** trên một nhánh riêng, thay `SpringEventPublisher` bằng `@ApplicationModuleListener` và đọc bảng
   `event_publication`. So sánh với tự làm: lợi gì, mất gì?
