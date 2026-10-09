# LaSono: Kế hoạch làm lại UI + bộ hướng dẫn backend để vừa học vừa code

> Đặt file này vào `docs/UI_BUILD_PLAN.md`. Đọc kèm `PROJECT_STATUS.md`.
>
> Bối cảnh: Phase 1-4 đã xong cả backend lẫn UI. Leon (fresher Java Spring Boot) sẽ
> TỰ CODE backend cho Phase 5, 6, 7 để học. Nhiệm vụ của bạn:
> 1. Viết bộ tài liệu backend dạng hướng dẫn học, đủ để Leon tự code từng tính năng.
> 2. Làm lại toàn bộ UI Flutter web cho đẹp, thực tế, cảm giác như một app streaming
>    âm nhạc chuyên nghiệp (bố cục kiểu SoundCloud).
> 3. Phần Phase 1-4 nối backend THẬT; phần Phase 5-6 chạy bằng dữ liệu giả cho đến khi
>    Leon code xong backend.
>
> KHÔNG viết code backend production.

## 0. Quy tắc bất biến

1. KHÔNG sửa code backend Java. Chỉ ĐỌC để hiểu kiến trúc, quy ước và API đang có.
2. KHÔNG làm hỏng chức năng Phase 1-4 đang chạy: upload, stream Range 206, danh sách
   keyset, processing status, waveform, register/login, refresh token rotation, owner,
   public/private, profile. Làm lại GIAO DIỆN, giữ nguyên logic đã đúng.
3. Bố cục lấy cảm hứng từ SoundCloud (player bar dưới đáy, waveform lớn trong track card,
   comment nổi trên waveform, profile có banner). KHÔNG dùng logo, tên, màu cam đặc trưng,
   icon hay asset của SoundCloud. LaSono có nhận diện riêng.
4. Non-goals (KHÔNG làm UI): playlist, repost, notification, messaging, recommendation,
   mobile build. Không hiển thị số liệu backend không có (ví dụ lượt nghe). Không có nút "chết".
5. Mọi truy cập dữ liệu đi qua interface repository; UI không gọi HTTP trực tiếp.
6. Sau MỖI giai đoạn: `flutter analyze`, `flutter test`, sửa lỗi, `git commit` với message
   mô tả chính xác thay đổi (không gộp việc không liên quan). Cập nhật mục "Tiến độ" trong
   `docs/ui-handoff.md`.
7. Repo luôn ở trạng thái build được, tài liệu phản ánh đúng những gì đã làm, để có thể dừng
   bất cứ lúc nào khi hết quota.

## Giai đoạn 0: Khảo sát (không sửa gì)

Đọc `PROJECT_STATUS.md`, `docs/phase1-e2e.md`, `docs/phase-3-audio-processing.md`, toàn bộ
cấu trúc backend (đặc biệt module `identity` và module track) và `app/`. Ghi vào
`docs/ui-handoff.md`:
- State management, router, HTTP client, cách lưu token, cách xử lý 401/refresh hiện có.
- Cách Phase 4 đang cho phát track private (audio element không gắn được header). Giữ nguyên.
- Danh sách endpoint Phase 1-4 thực tế (method, path, response) đọc từ controller.
- Quy ước backend thực tế: tên package, cách đặt port/adapter, cách viết use case, định dạng
  lỗi, cách viết test, cách dùng Flyway, quy tắc ArchUnit. Bộ hướng dẫn ở Giai đoạn 1 PHẢI
  bám theo đúng các quy ước này, không tự đặt quy ước mới.

## Giai đoạn 1: Hợp đồng API cho Phase 5-6 (LÀM TRƯỚC UI)

### `docs/api-contract.md`
- **Phần A: Phase 1-4 (đã có).** Mô tả lại endpoint thực tế làm tài liệu tham chiếu. Chỉ mô
  tả, không đề xuất thay đổi; nếu thấy điểm đáng cải thiện thì ghi vào mục "Ghi chú" riêng.
- **Phần B: Phase 5-6 (Leon sẽ code).** Theo đúng định dạng lỗi, kiểu ID, định dạng thời gian
  và kiểu phân trang keyset ĐANG CÓ. Với mỗi endpoint: method + path, auth, request/response
  JSON mẫu, mã lỗi, màn hình dùng nó, ghi chú nghiệp vụ.
  - Likes: `PUT`/`DELETE /tracks/{id}/like` (idempotent), danh sách track đã like của user.
  - Follows: `PUT`/`DELETE` follow user, danh sách followers/following (keyset),
    `followerCount`, `followingCount`, `isFollowedByMe` trong profile.
  - Comments: tạo, liệt kê theo `positionMs` hoặc thời gian, xoá (chủ comment hoặc chủ track).
    Comment có `positionMs` (0 ≤ positionMs ≤ durationMs).
  - Feed: `GET /feed` keyset.
  - Search: `GET /search` (tracks, users), keyset hoặc giới hạn kết quả, nói rõ chọn gì.
  - Các field mới thêm vào Track: `likeCount`, `commentCount`, `isLikedByMe`.
  - Quy tắc hiển thị: track private không xuất hiện trong feed/search của người khác; không
    like/comment được track private của người khác (trả 404, không phải 403, và giải thích vì sao).
- **Phần C: Mở rộng tùy chọn (ghi rõ "OPTIONAL").** Ảnh bìa track và avatar user qua port
  `ImageStorage`. UI phải đẹp ngay cả khi KHÔNG có phần này (dùng placeholder).

## Giai đoạn 2: Bộ hướng dẫn backend `docs/backend-guide/`

Mục tiêu: Leon đọc và tự code từng tính năng, hiểu vì sao làm như vậy. Phong cách Leon thích:
đi từng bước, có ví dụ trace cụ thể, có khung code (scaffold) thay vì trang trắng.

**Ranh giới:** được viết khung class (tên class, package, layer, chữ ký method, annotation
quan trọng, phần thân để `// TODO` kèm gợi ý), SQL minh hoạ cho truy vấn khó, migration Flyway
gợi ý và tên test case. KHÔNG viết sẵn phần thân logic hoàn chỉnh. Mọi tên package, port,
quy ước phải khớp code hiện có (Giai đoạn 0).

### File cần tạo

- `00-how-to-use.md`: thứ tự đọc; quy trình chuẩn cho mỗi tính năng (đọc guide → migration →
  domain + unit test → use case → adapter → controller → `postgresTest` → ArchUnit → kiểm tra
  bằng curl → nối UI bằng cách bật HTTP repository); cách chạy app ở chế độ dữ liệu giả và
  thật; Definition of Done.
- `01-domain-events.md` (làm TRƯỚC, đúng như roadmap)
- `02-likes.md`
- `03-follows.md`
- `04-timestamped-comments.md`
- `05-feed.md`
- `06-search-vietnamese.md`
- `07-phase7-proof-and-release.md` (k6, Actuator/Micrometer/Grafana, Docker Compose trên VPS,
  README; mức hướng dẫn tổng quan và checklist)
- `glossary.md`: thuật ngữ (idempotency, keyset, outbox, fan-out on read/write, trigram,
  race condition, isolation level...) giải thích ngắn kèm ví dụ.

### Khung bắt buộc cho mỗi guide 01-06

1. **Mục tiêu và nghiệm thu:** tính năng làm gì, khi nào coi là xong.
2. **Kiến thức cần biết trước:** khái niệm, kèm link tài liệu chính thức (Spring, PostgreSQL,
   Hibernate) để tự đọc thêm.
3. **Quyết định thiết kế:** 2-3 phương án, trade-off, phương án khuyến nghị cho LaSono và lý do.
4. **Vị trí trong kiến trúc:** module nào, mỗi class nằm ở layer nào (Domain / Application /
   Infrastructure / Presentation), port nào cần, sơ đồ phụ thuộc dạng text. Kiểm tra không vi
   phạm dependency rule và ArchUnit hiện có.
5. **Schema:** migration Flyway gợi ý, ràng buộc unique, index và lý do cho từng index.
6. **Các bước code theo thứ tự:** mỗi bước có khung code, giải thích, và cách kiểm chứng bước
   đó trước khi qua bước sau.
7. **Trace-through cụ thể:** ít nhất một ví dụ chạy tay với dữ liệu thật (ví dụ hai request like
   đồng thời theo dòng thời gian; một trang feed với cursor cụ thể; một truy vấn "son tung"
   khớp "Sơn Tùng").
8. **Test cần viết:** liệt kê tên test case (unit, `postgresTest`, controller), mỗi cái kiểm tra
   điều gì, ca biên nào.
9. **Lỗi thường gặp:** những sai lầm điển hình và cách nhận ra.
10. **Kiểm tra thủ công:** lệnh curl theo thứ tự, kết quả mong đợi, rồi kịch bản trên UI.
11. **Câu hỏi tự kiểm tra:** 5-8 câu kiểu phỏng vấn kèm đáp án gợi ý (để ở cuối, gập lại).
12. **Bài tập mở rộng:** 1-2 hướng nâng cấp sau v1.0.

### Nội dung trọng tâm từng guide

- **01 domain events:** sự kiện nào (`TrackLiked`, `TrackUnliked`, `UserFollowed`,
  `CommentPosted`...), event là record trong Domain hay Application, publish qua
  `ApplicationEventPublisher` hay Spring Modulith; `@EventListener` vs
  `@TransactionalEventListener(AFTER_COMMIT)`; chuyện gì xảy ra nếu listener lỗi; khi nào cần
  outbox (giải thích nhưng không bắt buộc ở v1.0, giữ nguyên chính sách hoãn Kafka).
- **02 likes:** unique `(user_id, track_id)`, `INSERT ... ON CONFLICT DO NOTHING`, cập nhật
  counter bằng `UPDATE ... SET like_count = like_count + 1` chỉ khi insert thực sự xảy ra, so
  sánh với đếm khi đọc; lost update và cách tránh; job đối soát counter (tùy chọn).
- **03 follows:** chặn tự follow, idempotent, đếm follower/following, phân trang danh sách.
- **04 comments:** validate `positionMs` theo `durationMs`, quyền xoá, index để lấy comment
  theo track, cách UI gom marker trên waveform.
- **05 feed:** fan-out on read (JOIN `follows`) vs fan-out on write, chọn on read cho v1.0;
  keyset theo `(created_at, id)`; index phù hợp; dùng `EXPLAIN ANALYZE` để kiểm chứng.
- **06 search:** extension `unaccent` + `pg_trgm`; vì sao cần hàm wrapper IMMUTABLE cho
  `unaccent` khi tạo index; GIN trigram index; `similarity` / toán tử `%`; xếp hạng; chỉ trả
  track READY + PUBLIC; test với dữ liệu tiếng Việt có dấu và không dấu.

### `docs/backend-checklist.md`
Checklist theo thứ tự code Phase 5 → 6 → 7, mỗi mục link tới guide tương ứng, có ô đánh dấu
và tiêu chí nghiệm thu bằng HTTP.

→ Commit: "docs: Phase 5-6 API contract and backend learning guides"

## Giai đoạn 3: Design system

Thư mục `lib/core/theme/`:
- Bảng màu riêng của LaSono: nền tối sâu làm mặc định (app nghe nhạc), một màu nhấn nổi bật
  KHÔNG phải cam; có light mode; màu ngữ nghĩa success/warning/error; màu waveform (đã phát,
  chưa phát, hover).
- Typography: font Google Fonts hỗ trợ tiếng Việt tốt (kiểm tra dấu hiển thị đúng), thang cỡ
  chữ rõ ràng.
- Spacing scale, radius, elevation/shadow, breakpoint, thời lượng animation.
- Độ tương phản chữ/nền đọc được ở cả hai chế độ.
- Màn hình `/dev/gallery` (chỉ debug) hiển thị mọi token và component.

→ Commit

## Giai đoạn 4: Tầng dữ liệu

- Giữ nguyên repository HTTP thật của Phase 1-4.
- Thêm interface cho Phase 5-6: `SocialRepository` (like, follow, comment), `FeedRepository`,
  `SearchRepository`; mở rộng model Track/User với các field mới trong hợp đồng.
- Mỗi interface có `Fake*` (trong bộ nhớ, trễ 200-600ms, có cờ để giả lập lỗi) và `Http*`
  viết sẵn theo hợp đồng, phần chưa có backend đánh dấu TODO.
- Bật/tắt theo TỪNG tính năng, không phải toàn cục, ví dụ
  `--dart-define=FAKE_SOCIAL=true --dart-define=FAKE_FEED=true --dart-define=FAKE_SEARCH=true`.
  Leon code xong tính năng nào thì tắt fake tính năng đó. Ghi rõ cách làm trong
  `docs/ui-handoff.md`.
- Field mới mà backend thật chưa trả (`likeCount`...) phải được parse an toàn (mặc định 0/false),
  để UI không vỡ khi chạy Phase 1-4 thật.
- Dữ liệu giả chất lượng cho Phase 5-6: ~30 track, ~8 user, tên Việt lẫn Anh, comment rải trên
  waveform, có user chưa follow ai, có kết quả search không dấu.

→ Commit

## Giai đoạn 5: App shell

- Top bar: logo chữ LaSono, các mục Home / Feed, ô search lớn ở giữa, nút Upload, avatar + menu
  (Profile, Đăng xuất) hoặc nút Đăng nhập / Tạo tài khoản.
- **Player bar cố định ở đáy:** ảnh bìa, tên + tác giả (bấm để mở track/profile), prev/play/next
  theo hàng đợi hiện tại, thanh tiến độ seek được, thời gian, âm lượng, nút like. Phát liên tục
  khi chuyển trang. Tái sử dụng bộ điều khiển phát hiện có, không viết lại logic Range/seek.
- Hàng đợi phát: bấm play trong một danh sách thì danh sách đó thành hàng đợi.
- Router + route guard đang có: giữ nguyên hành vi, chỉ thêm route mới.
- Responsive: desktop, tablet, mobile web (player bar thu gọn trên màn nhỏ).

→ Commit

## Giai đoạn 6: Component (kèm widget test)

- `TrackCard` kiểu SoundCloud: ảnh bìa vuông bên trái, bên phải là tác giả, tiêu đề, nút play
  tròn lớn, **waveform ngay trong card** (bấm để seek và phát), hàng hành động (like, comment
  count, menu owner), thời gian đăng tương đối ("3 ngày trước"). Có trạng thái PROCESSING/FAILED.
- `WaveformView`: phần đã phát đổi màu, hover hiện thời gian, click seek, **avatar comment nhỏ
  dưới waveform tại vị trí `positionMs`**, hover/khi phát tới thì hiện nội dung comment nổi lên.
- `CoverArt`: ảnh bìa hoặc placeholder gradient sinh ổn định theo track id.
- `UserAvatar` (chữ cái đầu + màu theo id), `ProfileHeader` có banner gradient.
- `LikeButton`, `FollowButton`: optimistic update, rollback + thông báo khi lỗi, chặn bấm liên tục.
- `CommentComposer`: lấy `positionMs` hiện tại, hiện "bình luận tại 1:23", cho chỉnh.
- `CommentList`, `UserTile`, `StatBlock` (followers / following / tracks).
- `SkeletonLoader` (shimmer), `EmptyState`, `ErrorState` (nút thử lại), `ConfirmDialog`, toast.

Mọi danh sách và màn hình có đủ loading / error / empty.

→ Commit

## Giai đoạn 7: Màn hình (theo kịch bản "v1.0 done")

Làm lần lượt, mỗi màn hình commit riêng:

1. **Đăng nhập / Đăng ký** (làm lại giao diện, giữ logic): bố cục hai cột trên desktop, lỗi theo
   field từ server, hiện/ẩn mật khẩu.
2. **Home**: danh sách track với `TrackCard` mới, load-more keyset.
3. **Upload** (làm lại giao diện): vùng kéo thả lớn, tiến độ upload, form tiêu đề + visibility,
   sau upload chuyển tới trang track và hiện PROCESSING cập nhật tới READY.
4. **Track detail**: hero lớn (ảnh bìa, tiêu đề, tác giả, waveform cỡ lớn có comment), hàng hành
   động, ô comment, danh sách comment (bấm thời gian trong comment để nhảy tới đó), menu
   sửa/xoá/đổi visibility cho owner, màn hình 404 thân thiện.
5. **Profile** (`/{handle}` hoặc route hiện có): banner, avatar, tên, số liệu, nút follow, tab
   Tracks / Likes, track private chỉ hiện với chủ (kèm nhãn "Riêng tư").
6. **Followers / Following**: danh sách user có nút follow.
7. **Feed**: track từ người đang follow; empty state gợi ý vào Home để tìm người follow.
8. **Search**: debounce, tab Tất cả / Tracks / Users, highlight từ khóa, empty state.
9. **Quản lý track**: sửa tiêu đề, đổi visibility, xoá có xác nhận.

→ Commit sau mỗi màn hình.

## Giai đoạn 8: Hoàn thiện (CHỈ khi còn quota)

Transition giữa trang, hover state, shimmer, phím tắt (Space để play/pause), favicon, tiêu đề tab
đổi theo track đang phát, trang 404, rà responsive. Không thêm tính năng.

## Giai đoạn 9: Đối chiếu và bàn giao (BẮT BUỘC)

1. So DTO + `Http*Repository` với `docs/api-contract.md`; cập nhật hợp đồng để khớp những gì
   UI thực sự cần. Mọi field UI cần phải có trong hợp đồng.
2. Hoàn thiện `docs/ui-handoff.md`: cấu trúc thư mục, cách chạy, cờ fake theo tính năng, cách
   nối một tính năng khi backend xong, TODO còn lại, giả định UI đặt cho backend.
3. Cập nhật `PROJECT_STATUS.md`: dưới Phase 5 và 6, tách mục "UI (dữ liệu giả)" đã xong khỏi
   các mục backend chưa xong. KHÔNG đánh dấu backend là xong. Thêm link tới `docs/backend-guide/`.
4. Chạy `flutter analyze`, `flutter test`, `flutter build web`; chạy app với backend thật để kiểm
   tra Phase 1-4 vẫn hoạt động; commit cuối.

## Thứ tự ưu tiên khi quota gần hết

Giai đoạn 0 → 1 (hợp đồng) → 2 (guide 00, 01, 02 trước) → 9 (bàn giao) → 4 → 3 → 5 → 6 → 7 → 8.
Nếu quota sắp cạn: DỪNG việc đang làm, chạy ngay Giai đoạn 9 cho phần đã xong.
