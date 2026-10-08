# Backend checklist: Phase 5 → 6 → 7

> Tích `[x]` khi **tiêu chí nghiệm thu bằng HTTP** của mục đó đúng (chạy bằng `curl`, xem mục 10 của từng guide). Chi tiết cách làm nằm ở guide tương ứng.
> Quy trình cho mỗi mục và Definition of Done: [`backend-guide/00-how-to-use.md`](backend-guide/00-how-to-use.md).
> Hợp đồng: [`api-contract.md`](api-contract.md). `$BASE = http://localhost:8080/api/v1`.
>
> Sau mỗi mục: tắt cờ fake tương ứng ở app (cột "Cờ"), chạy app với backend thật, rồi tick ô "UI" ở cuối mục. Cũng tick vào `PROJECT_STATUS.md` (file cục bộ, không commit).

## Phase 5: Engagement

### 5.1 Domain events — [guide 01](backend-guide/01-domain-events.md)
- [ ] Gói `com.lasono.shared.event` và các record sự kiện (7 sự kiện)
- [ ] Port `EventPublisher` + adapter Spring + fake `RecordingEventPublisher`
- [ ] Quy tắc ArchUnit cho `shared` (có ca cố tình vi phạm)
- [ ] `postgresTest`: listener đồng bộ lỗi ⇒ rollback cả phần ghi của người phát
- **Nghiệm thu:** không có endpoint; `./gradlew test` và `postgresTest` xanh, ArchUnit xanh. Bạn giải thích được `@EventListener` vs `AFTER_COMMIT`.

### 5.2 Likes — [guide 02](backend-guide/02-likes.md) · Cờ: `FAKE_LIKES`
- [ ] CORS cho phép `PUT`
- [ ] Migration `tracks.like_count/comment_count` + bảng `likes`; `cleanTestDatabase()` đã xoá `likes`
- [ ] Module `engagement` dựng xong + ArchUnit (4 quy tắc, `track ✗→ engagement`)
- [ ] `PUT/DELETE /tracks/{id}/like` idempotent
- [ ] `likeCount`, `commentCount`, `isLikedByMe`, `createdAt` trong `GET /tracks`, `GET /tracks/{id}`, `GET /users/{id}/tracks`, `PATCH /tracks/{id}`
- [ ] Bộ đếm đúng khi 20 like đồng thời; lưu lại track không reset bộ đếm
- [ ] Xoá track dọn `likes` (qua `TrackDeleted`)
- **Nghiệm thu HTTP:**
  - [ ] `PUT like` không token → `401`; hai lần liên tiếp → cùng `{"liked":true,"likeCount":1}`
  - [ ] `DELETE like` hai lần → `likeCount` giảm một lần
  - [ ] Track private của người khác → `404` (không `403`); track chưa READY → `409`
  - [ ] `GET /tracks` có `isLikedByMe:true` đúng track
  - [ ] SQL: `like_count == count(*)`
- [ ] UI: tim đầy/rỗng khớp, tải lại vẫn đúng

### 5.3 Follows — [guide 03](backend-guide/03-follows.md) · Cờ: `FAKE_FOLLOWS`
- [ ] Migration `follows`, counters ở `users`, index `idx_tracks_owner_created`
- [ ] `PUT/DELETE /users/{id}/follow` (tự follow bị chặn ở domain, use case, DB)
- [ ] Bộ đếm cập nhật không deadlock khi hai người follow nhau cùng lúc
- [ ] `GET /users/{id}` có `followerCount`, `followingCount`, `isFollowedByMe`
- [ ] `GET /users?ids=` (batch, tối đa 50)
- [ ] `GET /users/{id}/followers|following` (keyset)
- [ ] `GET /users/{id}/tracks` có `totalCount`
- **Nghiệm thu HTTP:**
  - [ ] Follow chính mình → `400`; user lạ → `404`; không token → `401`
  - [ ] Follow hai lần → `followerCount` tăng một lần
  - [ ] `GET /users?ids=a,b,<id lạ>` → 2 phần tử; `?ids=abc` → `400`
  - [ ] Followers phân trang không trùng khi có người follow mới giữa hai trang
  - [ ] SQL: `follower_count == count(*)`
- [ ] UI: nút Theo dõi, danh sách Followers/Following đúng tên

### 5.4 Timestamped comments — [guide 04](backend-guide/04-timestamped-comments.md) · Cờ: `FAKE_COMMENTS`
- [ ] Migration `comments` (+ 2 index), `cleanTestDatabase()` xoá `comments`
- [ ] Domain `Comment.post` kiểm text (1-500 code point) và `0 ≤ positionMs ≤ durationMs`
- [ ] `POST /tracks/{id}/comments` → `201`
- [ ] `GET /tracks/{id}/comments?order=position|recent` (keyset, hai kiểu cursor)
- [ ] `DELETE …/comments/{commentId}` (tác giả hoặc chủ track)
- [ ] `commentCount` khớp số dòng; xoá track xoá comment
- **Nghiệm thu HTTP:**
  - [ ] `positionMs = durationMs` → `201`; `durationMs + 1` → `400`; text rỗng → `400`
  - [ ] Hai comment cùng `positionMs` không mất khi phân trang `limit=1`
  - [ ] Người lạ xoá → `403`; track private của người khác → `404`; xoá hai lần → `404`
  - [ ] Cursor của `recent` dùng cho `position` → `400`
- [ ] UI: marker trên waveform, hover hiện nội dung, bấm thời gian để nhảy

## Phase 6: Discovery

### 6.1 Feed và danh sách like — [guide 05](backend-guide/05-feed.md) · Cờ: `FAKE_FEED`
- [ ] Module `discovery` + ArchUnit (4 cặp `moduleDoesNotDependOn`)
- [ ] `GET /feed` (keyset, chỉ READY + PUBLIC của người follow)
- [ ] `GET /users/{id}/likes` (sắp theo thời điểm like)
- [ ] Số đo `EXPLAIN ANALYZE` trước/sau index, kết luận 5 dòng trong PR
- **Nghiệm thu HTTP:**
  - [ ] Không token → `401`; không follow ai → `items: []`
  - [ ] Track của chính mình, track private, track PROCESSING không có trong feed
  - [ ] Trang 2 bằng `nextCursor` không trùng trang 1 kể cả khi có track mới đăng giữa hai lần gọi
  - [ ] `/users/{id}/likes` user lạ → `404`; khách xem được
- [ ] UI: màn Feed, trạng thái rỗng gợi ý, tab Likes

### 6.2 Search tiếng Việt — [guide 06](backend-guide/06-search-vietnamese.md) · Cờ: `FAKE_SEARCH`
- [ ] Migration `unaccent` + `pg_trgm` + `f_unaccent` + 2 GIN index
- [ ] `GET /search?q&type&limit`
- [ ] Bộ test dữ liệu tiếng Việt (bảng "oracle" của guide 06)
- [ ] `EXPLAIN` chứng minh dùng GIN trên 100 000 dòng
- **Nghiệm thu HTTP:**
  - [ ] `q=nang am` ra `Nắng ấm xa dần`; `q=son tung` ra `Sơn Tùng`; `q=son` vẫn ra; `q=son tuhg` vẫn ra
  - [ ] `q=a` → `400`; thiếu `q` → `400`; `type=foo` → `400`
  - [ ] Track private/PROCESSING không bao giờ xuất hiện; `q=%` không khớp tất cả
- [ ] UI: debounce, tab Tất cả/Tracks/Users, tô sáng từ khoá

## Phase 7: Proof and release — [guide 07](backend-guide/07-phase7-proof-and-release.md)

- [ ] k6: 5 kịch bản + bảng số liệu (`docs/phase-7-proof.md`)
- [ ] Actuator cổng riêng, `health` + `prometheus`; test bảo mật
- [ ] 3 số đo riêng; dashboard Grafana lưu JSON
- [ ] Dockerfile backend (ffmpeg, non-root), compose prod, Caddy, HTTPS
- [ ] Kịch bản "v1.0 xong" chạy hết trên bản công khai
- [ ] README (sơ đồ, demo, số liệu); `docs/phase-5/6/7-*.md`; `PROJECT_STATUS.md`

## Khi tất cả cờ fake đã tắt

- [ ] `flutter run -d web-server --web-port 3000` (không `--dart-define` fake nào) chạy trọn kịch bản v1.0
- [ ] `./gradlew test`, `./gradlew postgresTest`, `./gradlew ffmpegTest`, `flutter analyze`, `flutter test` đều xanh
- [ ] Xoá `Fake*Repository` còn dùng làm demo? **Không bắt buộc**: giữ chúng cho test widget, nhưng bỏ các cờ khỏi tài liệu chạy chính.
