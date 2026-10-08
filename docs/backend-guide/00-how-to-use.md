# Cách dùng bộ hướng dẫn backend

> Bộ guide này giúp Leon **tự code** backend Phase 5, 6, 7 mà vẫn hiểu *vì sao* làm vậy.
> Mỗi guide đưa khung class, SQL minh hoạ, tên test; **phần thân logic là việc của bạn** (`// TODO`).
> Đọc kèm: [`../api-contract.md`](../api-contract.md) (hợp đồng, Phần B là thứ bạn phải làm đúng),
> [`../ui-handoff.md`](../ui-handoff.md) (UI đã sẵn sàng, đang chạy bằng dữ liệu giả),
> [`../backend-checklist.md`](../backend-checklist.md) (ô đánh dấu theo thứ tự).

## 1. Thứ tự đọc và làm

| # | Guide | Phase | Làm gì | Vì sao thứ tự này |
|---|-------|-------|--------|-------------------|
| 1 | [`01-domain-events.md`](01-domain-events.md) | 5 | Cơ chế sự kiện giữa các module | Likes, follows, comments đều cập nhật bộ đếm ở module khác qua sự kiện. Roadmap yêu cầu làm đầu tiên. |
| 2 | [`02-likes.md`](02-likes.md) | 5 | Like/unlike, bộ đếm, `isLikedByMe` | Đơn giản nhất, nhưng dạy hết các khái niệm khó: idempotent, race condition, counter. Đồng thời dựng module `engagement`. |
| 3 | [`03-follows.md`](03-follows.md) | 5 | Follow/unfollow, followers/following, profile mở rộng | Lặp lại khuôn của likes, thêm self-follow và batch profile. |
| 4 | [`04-timestamped-comments.md`](04-timestamped-comments.md) | 5 | Comment gắn `positionMs` | Cần cả track lẫn user, kiểm tra theo `durationMs`, phân quyền xoá. |
| 5 | [`05-feed.md`](05-feed.md) | 6 | Feed + danh sách like; dựng module `discovery` | Cần dữ liệu follows và tracks, nên làm sau 03. |
| 6 | [`06-search-vietnamese.md`](06-search-vietnamese.md) | 6 | Tìm kiếm không dấu | Độc lập với 02-05, để cuối vì kỹ thuật khác hẳn (PostgreSQL extension). |
| 7 | [`07-phase7-proof-and-release.md`](07-phase7-proof-and-release.md) | 7 | k6, Actuator/Grafana, Docker Compose, README | Chỉ có ý nghĩa khi tính năng đã chạy. |
| — | [`glossary.md`](glossary.md) | | Thuật ngữ | Mở bất cứ lúc nào gặp từ lạ. |

**Mỗi guide 01-06 có cùng 12 mục** (mục tiêu → kiến thức nền → quyết định thiết kế → vị trí trong kiến trúc → schema → các bước
code → trace-through → test → lỗi thường gặp → kiểm tra thủ công → câu hỏi tự kiểm tra → bài tập mở rộng). Đọc **mục 1-5 trước khi
gõ dòng code nào**; mục 6 là phần bạn làm từng bước; mục 7 (trace) nên đọc *trước* mục 6 để có hình dung.

## 2. Quy trình chuẩn cho mỗi tính năng

Giữ đúng thứ tự này (khớp `CLAUDE.md` của dự án: test trước, RED rồi mới GREEN).

```
1. Đọc guide (mục 1-5, 7)
2. Migration Flyway (V<N>__...sql)           → ./gradlew postgresTest (PostgresSetupTest) kiểm tra chạy được
3. Domain + unit test                         → ./gradlew test
4. Use case + port + fake trong bộ nhớ        → ./gradlew test
5. Adapter (JPA entity, repository, SQL)      → ./gradlew postgresTest
6. Controller + ExceptionHandler + Security   → ./gradlew test (controller test), postgresTest (qua HTTP)
7. ArchUnit: thêm module/quy tắc mới          → ./gradlew test
8. Kiểm tra bằng curl (mục 10 của mỗi guide)
9. Nối UI: tắt cờ fake của tính năng, chạy app với backend thật
```

Với **mỗi test** làm đúng vòng TDD:

1. Viết test. 2. Chạy, thấy **RED vì đúng lý do** (hành vi chưa có, không phải lỗi biên dịch: tạo khung method trả
giá trị tạm trước). 3. Viết code tối thiểu. 4. Chạy, thấy GREEN. 5. Dọn code (refactor) khi đã xanh.

Mẹo kiểm tra test không "xanh giả": phá thử code (đổi `+ 1` thành `+ 2`, bỏ `ON CONFLICT`), test phải đỏ, rồi trả lại.
Dự án đã làm vậy ở Phase 2-4 (xem các "Pitfalls" trong `docs/phase-*.md`).

### Lệnh hay dùng

```bash
cd backend
./gradlew test                              # H2, nhanh, không cần Docker
./gradlew postgresTest                      # cần Postgres thật (docker compose up -d) và DB lasono_test
./gradlew test --tests '*LikeTrackUseCaseTest'          # chạy một lớp test
./gradlew postgresTest --tests '*LikePersistenceAdapterPostgresTest'
./gradlew test --rerun                      # Gradle nói "UP-TO-DATE" thì test không chạy lại, dùng --rerun
```

- `--tests` chỉ lọc **task cuối** khi đưa hai task cùng lúc: chạy `test` và `postgresTest` thành hai lệnh riêng.
- Gradle trên `/mnt/d` rất chậm khi có nhiều daemon: `./gradlew --stop` trước khi chạy cả bộ.
- Sửa một migration đã chạy thì Flyway báo sai checksum và **mọi** postgresTest đỏ. Với migration *của bạn* chưa commit, cách nhanh
  là xoá và tạo lại database test: `DROP DATABASE lasono_test; CREATE DATABASE lasono_test;`.

## 3. Chạy app ở chế độ dữ liệu giả và thật

Backend Phase 1-4 chạy thật. Phase 5-6 chưa có, nên app có một **cờ fake riêng cho từng tính năng**
(`--dart-define`), tắt từng cờ khi backend của tính năng đó xong:

| Cờ | Che cho | Tắt khi xong | Guide |
|----|---------|--------------|-------|
| `FAKE_LIKES=true` | like/unlike, `likeCount`, `isLikedByMe` | 02 | 02 |
| `FAKE_FOLLOWS=true` | follow/unfollow, followers/following, số follower, batch profile | 03 | 03 |
| `FAKE_COMMENTS=true` | comment trên waveform, `commentCount` | 04 | 04 |
| `FAKE_SOCIAL=true` | **tắt/bật cả ba cờ trên cùng lúc** (tiện, một cờ đủ) | 02 + 03 + 04 | 02-04 |
| `FAKE_FEED=true` | feed, danh sách like của user | 05 | 05 |
| `FAKE_SEARCH=true` | search | 06 | 06 |

Một cờ riêng (`FAKE_LIKES=false`) **thắng** `FAKE_SOCIAL=true`: để chạy thật mỗi likes, đặt `FAKE_SOCIAL=true --dart-define=FAKE_LIKES=false`.

```bash
# Backend thật (Phase 1-4) + mọi thứ Phase 5-6 giả — trạng thái hiện tại:
cd app
export PATH="$HOME/development/flutter/bin:$PATH"
flutter run -d web-server --web-port 3000 \
  --dart-define=FAKE_SOCIAL=true --dart-define=FAKE_FEED=true --dart-define=FAKE_SEARCH=true

# Leon vừa code xong likes + follows + comments: tắt FAKE_SOCIAL, giữ hai cờ còn lại
flutter run -d web-server --web-port 3000 \
  --dart-define=FAKE_FEED=true --dart-define=FAKE_SEARCH=true

# Tất cả là backend thật (Definition of Done của Phase 6):
flutter run -d web-server --web-port 3000
```

Cổng **3000** là cổng duy nhất backend cho phép CORS. Nếu backend không ở `localhost:8080`, thêm
`--dart-define=API_BASE_URL=http://host:8080`. Backend chạy như README: `docker compose up -d`, đặt
`LASONO_JWT_SECRET`, `cd backend && ./gradlew bootRun`.

Khi một cờ bật, các id "giả" (có tiền tố `f4e00000-`) được app xử lý trong bộ nhớ; id thật vẫn đi qua backend thật. Nhờ vậy
bạn có thể: đăng nhập thật, upload thật, và like track thật trong khi follow vẫn là giả. Chi tiết nối từng tính năng nằm trong
`ui-handoff.md` mục "Nối một tính năng khi backend xong".

## 4. Cấu trúc module sẽ có sau Phase 5-6

```
com.lasono
├── config/                       (SecurityConfig, CorsConfig ... — sửa khi thêm route)
├── shared/event/                 (MỚI, guide 01) sự kiện: record thuần Java, không phụ thuộc module nào
├── track/                        (có sẵn) + listener bộ đếm, ViewerLikesReader, TrackStats
├── identity/                     (có sẵn) + listener bộ đếm, FollowStateReader, batch profile
├── engagement/                   (MỚI, guide 02-04) likes, follows, comments — phía GHI
└── discovery/                    (MỚI, guide 05-06) feed, search, danh sách like — phía ĐỌC
```

Quy tắc phụ thuộc (ArchUnit bảo vệ, bạn sẽ thêm dần ở từng guide):

```
presentation ──► application ──► domain          (trong mỗi module, như hiện tại)
                    ▲
infrastructure ─────┘  (implements port)

track ✗─► identity    identity ✗─► track           (đã có)
track ✗─► engagement  identity ✗─► engagement      (MỚI: engagement đứng "trên")
track ──► shared      identity ──► shared    engagement ──► shared
engagement.infrastructure ──► track/identity (CHỈ ở đây, làm cầu nối "anti-corruption")
discovery ✗─► mọi module khác (nó đọc bảng bằng SQL, không import class)
```

Hãy vẽ lại sơ đồ này bằng tay sau khi xong guide 03: nếu bạn giải thích được vì sao mũi tên đi hướng đó, bạn đã hiểu phần
khó nhất của kiến trúc dự án.

## 5. Definition of Done (cho MỖI tính năng)

Một tính năng chỉ "xong" khi **tất cả** những điều sau đúng:

- [ ] Migration Flyway chạy sạch trên database trống **và** trên database dev đang có dữ liệu (`bootRun` không lỗi).
- [ ] Mọi test mới theo vòng RED → GREEN; `./gradlew test` và `./gradlew postgresTest` xanh từ đầu (`--rerun`).
- [ ] Có `postgresTest` cho mọi quy tắc phụ thuộc vào PostgreSQL (unique, ON CONFLICT, đồng thời, index) và một test qua HTTP.
- [ ] ArchUnit: module/quy tắc mới đã đăng ký trong `ArchitectureTest`, quy tắc mới có test "cố tình vi phạm".
- [ ] `PostgresIntegrationTest.cleanTestDatabase()` xoá bảng mới (thứ tự xoá đúng).
- [ ] `SecurityConfig`/`CorsConfig` đã cập nhật và có test (route mới không vô tình mở cho người chưa đăng nhập).
- [ ] Đã chạy **mọi lệnh curl** ở mục "Kiểm tra thủ công" và kết quả đúng mã trạng thái trong `api-contract.md`.
- [ ] Đã tắt cờ fake của tính năng, chạy app với backend thật, và làm hết kịch bản UI ở mục "Kiểm tra thủ công".
- [ ] `README.md` mục API có hàng cho endpoint mới; `PROJECT_STATUS.md` đã tick; nếu gặp lỗi khó/khái niệm mới thì ghi vào
      `docs/learning-log.md` (quy tắc: tối đa 1-2 mục mỗi PR, phần Takeaway để bạn tự điền).
- [ ] Commit nhỏ, một dòng, dạng `type: mô tả` (không scope), mỗi commit một file hoặc một cụm nhỏ.

## 6. Khi bị kẹt

1. Đọc lại **mục 7 (trace)** của guide; đối chiếu từng bước với log SQL: thêm vào `application.yaml` (chỉ khi debug, đừng commit)
   `spring.jpa.show-sql: true` và `logging.level.org.hibernate.SQL: DEBUG`.
2. Test PostgreSQL đỏ mà H2 xanh: gần như chắc chắn là khác biệt SQL (ON CONFLICT, so sánh bộ giá trị, kiểu thời gian).
3. Xem mục "Lỗi thường gặp" của guide.
4. Xem `docs/phase-3-audio-processing.md` và `docs/phase-4-identity.md`: các bẫy tương tự (khoá hàng, transaction, `noRollbackFor`)
   đã được ghi lại ở đó.
