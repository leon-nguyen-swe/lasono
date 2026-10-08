# LaSono UI: tài liệu bàn giao

> Đọc kèm [`UI_BUILD_PLAN.md`](UI_BUILD_PLAN.md) (kế hoạch), [`api-contract.md`](api-contract.md) (hợp đồng API)
> và [`backend-guide/`](backend-guide/00-how-to-use.md) (hướng dẫn tự code backend Phase 5-7).
>
> **Đọc nhanh:** muốn chạy app → [Cách chạy](#cách-chạy). Muốn biết file nào ở đâu → [Cấu trúc thư mục](#cấu-trúc-thư-mục).
> Muốn nối một tính năng khi backend của nó xong → [Nối một tính năng](#nối-một-tính-năng-khi-backend-của-nó-xong).
> Việc còn lại → [TODO](#todo-còn-lại). Điều UI giả định về backend → [Giả định](#giả-định-ui-đặt-cho-backend).
>
> Mục **Tiến độ** ở dưới phản ánh đúng những gì đã commit. Phần "Khảo sát" là ảnh chụp **trước khi** làm lại UI (một số dòng của nó đã cũ, có ghi chú).

## Tiến độ

| Giai đoạn | Nội dung | Trạng thái |
|-----------|----------|------------|
| 0 | Khảo sát (mục "Khảo sát" bên dưới) | Xong |
| 1 | `docs/api-contract.md` | Xong |
| 2 | `docs/backend-guide/` + `docs/backend-checklist.md` | Xong |
| 3 | Design system (`lib/core/theme/`, `/dev/gallery`) | Xong: token màu (dark mặc định + light, WCAG AA có test), font Be Vietnam Pro nhúng, spacing/radius/elevation/motion/breakpoint, 2 theme, `ThemeController`. Xem trang tại `http://localhost:3000/dev/gallery` (chỉ debug) |
| 4 | Tầng dữ liệu (repository + `Fake*` + `Http*`) | Xong: 5 interface, `Http*` theo hợp đồng, `Fake*` + dữ liệu giả (8 user, 30 track, phát được), cờ theo từng tính năng, `UserDirectory`. 543 test xanh |
| 5 | App shell (top bar, player bar, hàng đợi, router) | Xong (hạ tầng): `go_router` + route guard + `AppShell` + `PlaybackController`. Màn hình cũ vẫn là `/` cho tới khi Giai đoạn 7 thay từng cái. 667 test xanh |
| 6 | Component (kèm widget test) | Xong: `TrackCard`, `WaveformView` (marker comment), `CoverArt`, `UserAvatar`, `LikeButton`, `FollowButton`, `CommentComposer`, `CommentList`, `UserTile`, `StatBlock`, `ProfileHeader`, `SkeletonLoader`, `EmptyState`, `ErrorState`, `showConfirmDialog`, `showToast`. 823 test xanh |
| 7 | Màn hình | Xong: đăng nhập/đăng ký, trang chủ (keyset + skeleton), upload (kéo thả), chi tiết track (waveform lớn, comment, menu chủ sở hữu, tự cập nhật khi PROCESSING), hồ sơ (track/đã thích, đổi tên), người theo dõi/đang theo dõi, bảng tin, tìm kiếm (bỏ dấu + tô đậm chữ khớp). Đã xóa toàn bộ màn hình cũ và test của chúng. 855 test xanh |
| 8 | Hoàn thiện | Xong (phần cần thiết): phím Space play/pause (không bắt khi đang gõ), tiêu đề tab theo bài đang phát, favicon + icon app + màu nền tối khi tải, chuyển trang bằng fade (tắt khi hệ điều hành bật "giảm chuyển động"), thẻ track nâng lên khi rê chuột, trang 404, rà responsive (sửa top bar bị tràn ở 600-900 px, sửa tiêu đề danh sách bị lệch giữa). Chưa làm: công tắc lỗi/độ trễ giả trên `/dev/gallery` (xem TODO) |
| 9 | Đối chiếu và bàn giao | Xong: `api-contract.md` đối chiếu và sửa (Phần D), tài liệu này, `PROJECT_STATUS.md`, `flutter analyze` sạch, 863 test xanh, `flutter build web` được, chạy với backend thật (mục "Kiểm tra với backend thật") |

## Cách chạy

```bash
# Backend (cần Docker cho PostgreSQL), xem README.md
docker compose up -d
cd backend && export LASONO_JWT_SECRET="$(openssl rand -base64 48)" && ./gradlew bootRun

# App. Trạng thái hiện tại: Phase 1-4 là backend thật, Phase 5-6 là dữ liệu giả
cd app && flutter pub get
flutter run -d web-server --web-port 3000 \
  --dart-define=FAKE_SOCIAL=true --dart-define=FAKE_FEED=true --dart-define=FAKE_SEARCH=true
```

- Cổng phải là **3000** (CORS của backend). Muốn trỏ tới backend khác: `--dart-define=API_BASE_URL=http://host:8080`.
- Không có `--dart-define` nào thì app dùng backend thật cho **mọi thứ**: like/comment/follow/feed/search sẽ báo lỗi (route chưa có, backend trả `401`/`404`). Đó là hành vi đúng cho tới khi guide tương ứng xong.
- Mỗi cờ chỉ làm giả **một** tính năng, xem bảng ở mục "Tầng dữ liệu". Đăng nhập, upload, phát, danh sách, sửa/xoá track và hồ sơ luôn dùng backend thật.
- Thế giới giả có 8 user và 30 track phát được (xem "Thế giới giả"). Trang design system: `http://localhost:3000/dev/gallery` (chỉ debug).
- Kiểm tra: `flutter analyze && flutter test`, rồi `flutter build web`. Test trên trình duyệt thật: xem cuối mục "Component".

## Cấu trúc thư mục

```
app/lib/
├── main.dart             LasonoApp: dựng session, repositories, player, theme, router
├── app_router.dart       go_router: route, route guard (redirectFor), trang chuyển fade, 404
├── api/                  Phase 1-4 giữ nguyên: AuthApi, TrackApi, ProfileApi, AccessTokens (refresh 1 lần), cookie web
├── auth/                 SessionController (đăng nhập, refresh single-flight, khôi phục phiên)
├── core/theme/           token màu (dark + light), font, spacing, radius, motion, breakpoint, ThemeController
├── core/text/            định dạng tiếng Việt: thời gian tương đối, 1:23, 1,2K, bỏ dấu, tô sáng chữ khớp
├── data/                 TẦNG DỮ LIỆU: interface repository, http/ (thật), fake/ (giả), cờ, UserDirectory
├── models/               Track, TrackPage, Comment, LikeState/FollowState/FollowEdge/CursorPage, SearchResults
├── playback/             PlaybackController: hàng đợi + player (just_audio), PlaybackScope
├── shell/                AppShell, TopBar, PlayerBar, app_context.dart (SessionScope + context.repos/playback/openTrack...)
├── widgets/              component dùng chung: TrackCard, WaveformView, LikeButton, FollowButton, Comment*, PagedListView, ...
├── screens/              mỗi route một file: home, track, profile, people, feed, search, upload, auth + track_actions.dart
└── dev/gallery_screen.dart   trang design system
app/test/                 phản chiếu lib/; support/test_harness.dart (TestEnv) dựng cả app với dữ liệu giả
```

Quy ước: màn hình lấy mọi thứ qua `context.repos` / `context.playback` / `context.viewerId` (`shell/app_context.dart`),
**không bao giờ** tự gọi HTTP. Danh sách dài dùng `PagedController` + `PagedListView` (keyset, chống câu trả lời cũ về muộn).
Điều hướng đi qua `context.openTrack`, `context.openUser`, `context.askToLogin` (quay lại đúng chỗ sau khi đăng nhập).

## Màn hình và dữ liệu của chúng

| Route | Trang | Phần **thật** (backend Phase 1-4) | Phần **giả** (cờ) |
|-------|-------|-----------------------------------|--------------------|
| `/` | Trang chủ | `GET /tracks` (keyset), tên tác giả | số like (`FAKE_LIKES`) |
| `/tracks/:id` | Chi tiết track | `GET /tracks/{id}`, `stream-url` + Range, `PATCH`, `DELETE`, tự hỏi lại khi `PROCESSING` | like, **comment** (`FAKE_COMMENTS`) |
| `/users/:id` | Hồ sơ | `GET /users/{id}`, `GET /users/{id}/tracks`, `PATCH /users/me` (đổi tên) | số theo dõi, nút follow (`FAKE_FOLLOWS`), tab "Đã thích" (`FAKE_FEED`) |
| `/users/:id/followers`, `/following` | Danh sách người | tên user | toàn bộ danh sách (`FAKE_FOLLOWS`) |
| `/feed` (cần đăng nhập) | Bảng tin | | `FAKE_FEED` |
| `/search?q=` | Tìm kiếm | | `FAKE_SEARCH` |
| `/upload` (cần đăng nhập) | Tải lên | `POST /tracks` (multipart), chuyển tới trang track | |
| `/login`, `/register` | Đăng nhập, đăng ký | `auth/*` | |
| `/dev/gallery` | Design system | | dữ liệu giả có sẵn |

## Kiểm tra với backend thật (Giai đoạn 9, 2026-10-08)

Chạy backend Phase 1-4 thật (PostgreSQL trong Docker, `./gradlew bootRun`), app là bản `flutter build web` phục vụ ở cổng 3000, điều khiển Chrome thật:

| Việc | Kết quả |
|------|---------|
| Danh sách track thật, keyset, tên tác giả, waveform, độ dài | Đúng |
| Đăng nhập trên trang mới → về trang chủ → danh sách tải lại và hiện **track riêng tư** của mình (nhãn "Riêng tư", menu ⋮) | Đúng |
| Bấm phát track thật: nghe được, thanh tiến độ và waveform chạy, player bar hiện (đã chạy `stream-url` + chữ ký) | Đúng |
| Tải lại trang: vẫn đăng nhập (cookie refresh), danh sách giữ nguyên | Đúng |
| `Range: bytes=0-99` → `206` + `Content-Range`; track private → `404` với khách, `200` với chủ; `PATCH`, `DELETE` (`204`, sau đó `404`); refresh không cookie → `401` | Đúng (curl) |
| Với cờ giả: tìm "son tung" ra "Sơn Tùng", bảng tin hiện bài của người đang theo dõi | Đúng |
| Không có cờ giả: trang track hiện lỗi ở phần bình luận ("Phiên đăng nhập đã hết hạn..." vì backend trả `401` cho route chưa có) | Đúng như thiết kế, nên luôn chạy với cờ cho tới khi backend xong |

Hai lỗi chỉ thấy khi chạy trình duyệt thật (test không bắt được vì font test khác font thật), đã sửa và có test: tiêu đề danh sách bị lệch vào giữa; top bar bị đẩy ra khỏi màn hình ở 600-900 px.
Chưa kiểm tra bằng tay trong lần này: kéo thả file upload (cần hộp thoại hệ điều hành), đổi tên hồ sơ, sửa/xoá track bằng nút (đã có test widget và đã thử bằng curl).

## Khảo sát (Giai đoạn 0)

Khảo sát dựa trên code ở `main` ngày 2026-10-08 (commit `8f542a3`), baseline: `flutter analyze` sạch,
232 test Flutter pass.

> **Đây là ảnh chụp trước khi làm lại.** Các màn hình cũ (`TrackListScreen`, `TrackScreen`, `TrackPlayerScreen`, `ProfileScreen`,
> `AuthScreen`, `EditTrackDialog`, `StatusBadge`...) đã bị xoá và thay bằng `lib/screens/*_page.dart`; `LasonoApp` không còn nhận `TrackApi`/`ProfileApi`.
> Các lớp `*Api`, `AccessTokens`, `SessionController` và cách phát private track (mục 2) vẫn đúng.

### 1. App Flutter hiện có (`app/lib`, khoảng 2650 dòng)

| Chủ đề | Thực tế | Hệ quả cho việc làm lại UI |
|--------|---------|----------------------------|
| State management | Không dùng package nào. `StatefulWidget` + `setState`; một `ChangeNotifier` duy nhất là `SessionController`, các màn hình nghe nó bằng `ListenableBuilder` / `addListener`. | Giữ nguyên cách này (không thêm Provider/Riverpod). Thêm vài `ChangeNotifier` nhỏ (hàng đợi phát, cache user) và đưa vào cây widget bằng `InheritedNotifier`. |
| Router | **Chưa có router.** `MaterialApp(home: ...)` và `Navigator.push(MaterialPageRoute(...))`. Không có named route, không có URL cho từng màn hình, **không có route guard** (chỉ có: bấm Upload khi chưa đăng nhập thì mở `AuthScreen` trước). | Kế hoạch nói "Router + route guard đang có" nhưng thực tế chưa có. Giai đoạn 5 thêm `go_router` (cần `ShellRoute` để player bar sống qua các trang). Hành vi "Upload cần đăng nhập" được giữ bằng một `redirect`. |
| HTTP client | Package `http`. `TrackApi`, `ProfileApi`, `AuthApi` mỗi lớp tự ghép URL từ `API_BASE_URL` (mặc định `http://localhost:8080`, đổi bằng `--dart-define=API_BASE_URL=...`), prefix `/api/v1`. Có timeout 30 s (upload 5 phút). Lỗi được đổi thành `TrackApiException` / `ProfileApiException` / `AuthApiException` với message tiếng Anh. | Các lớp `*Api` này **giữ nguyên** và trở thành phần dưới của các `Http*Repository` mới. UI không gọi chúng trực tiếp nữa. |
| Lưu token | Access token (JWT, 15 phút) chỉ nằm **trong bộ nhớ** của `SessionController`. Refresh token nằm trong cookie `lasono_refresh` (`HttpOnly`, `Secure`, `SameSite=Strict`, `Path=/api/v1/auth`) mà JS không đọc được. Trên web `AuthApi` dùng `BrowserClient()..withCredentials = true` (import có điều kiện trong `credentials_client*.dart`). | Giữ nguyên. Không lưu token vào `localStorage`. |
| 401 / refresh | `sendWithToken` (`api/access_tokens.dart`): gửi request kèm Bearer; nếu `401` và đang có token thì gọi `AccessTokens.refreshAccessToken()` đúng 1 lần rồi gửi lại đúng 1 lần. `SessionController.refreshAccessToken()` là *single-flight* (mọi request cùng chờ một lần refresh, vì backend xoay refresh token và không có thời gian ân hạn), có bộ đếm `_generation` để bỏ kết quả của phiên cũ. Khi mở app, `restore()` đổi cookie lấy access token trước khi hiện danh sách (`SessionStatus.restoring`). `GET /users/{id}` cố ý **không** gửi token vì server từ chối token hết hạn ngay cả ở route công khai. | Giữ nguyên toàn bộ. Mọi `Http*Repository` mới đi qua `sendWithToken`. |
| Phát nhạc | `PlayerService` (interface) + `JustAudioPlayerService` (bọc `just_audio`). `PlayerControls` tạo URL phát **khi bấm Play lần đầu**, tự rewind khi hết bài, chỉ lắng nghe stream của player *sau khi* load xong (stream của `just_audio` phát lại giá trị cuối cho người nghe mới). `TrackPlayback` poll `GET /tracks/{id}` mỗi 3 s khi `PROCESSING`. | Logic phát và seek (Range) **không viết lại**. Player bar mới bọc `PlayerService` bằng một `PlaybackController` (hàng đợi, bài hiện tại). |
| Màn hình | `TrackListScreen` (danh sách, load-more theo cuộn, menu tài khoản), `TrackPlayerScreen` (mở bằng push, có Sửa/Xoá cho owner), `TrackScreen` (form upload + ô "Load by id"), `ProfileScreen` (profile + tracks + đổi tên), `AuthScreen` (đăng nhập/đăng ký một màn hình), `EditTrackDialog`, `WaveformView` (CustomPaint 200 cột, tap để seek), `StatusBadge`. | Làm lại giao diện, giữ các `Key` quan trọng nếu test cũ còn cần (test cũ sẽ được cập nhật cùng màn hình). |
| Test | 232 test: `test/api` (HTTP với `MockClient`), `test/auth`, `test/models`, `test/screens`, `widget_test.dart`, `fake_auth_server.dart`, `fake_player_service.dart`. | Giữ `FakePlayerService` và các test API; test màn hình được viết lại khi màn hình đổi. |
| Dependencies | `http`, `file_picker`, `http_parser`, `just_audio`, `cupertino_icons`. Không có font tuỳ chỉnh, theme là `ColorScheme.fromSeed(deepPurple)` mặc định. | Giai đoạn 3 thêm font; Giai đoạn 5 thêm `go_router`. |

### 2. Phát track private

`<audio>` (và `just_audio` trên web) **không gắn được header `Authorization`**. Cách Phase 4 giải quyết, và UI mới
phải giữ nguyên:

1. Khi người dùng bấm Play lần đầu, app gọi `GET /api/v1/tracks/{id}/stream-url` (kèm Bearer nếu có).
   Server chỉ trả địa chỉ cho người được phép xem track (không thì `404`).
2. Phản hồi là `{url, expiresAt}`, trong đó `url` là đường dẫn tương đối
   `/api/v1/tracks/{id}/stream?expires=<epoch>&signature=<HMAC-SHA256>`. App ghép với `API_BASE_URL`.
3. `just_audio` mở địa chỉ đó; `/stream` chấp nhận chữ ký thay cho header (hiệu lực 1 giờ, gắn với một track).
4. Địa chỉ **không** được lưu lâu và không được log; mỗi lần phát lại sau khi dừng lâu cần xin lại.

Hệ quả cho hàng đợi phát: URL được xin **ngay trước khi load từng bài**, không xin trước cả hàng đợi.

### 3. Endpoint Phase 1-4 (đọc từ controller)

Bảng đầy đủ kèm JSON mẫu nằm ở [`api-contract.md`](api-contract.md) Phần A. Tóm tắt:

| Method | Path | Auth | Trả về |
|--------|------|------|--------|
| POST | `/api/v1/auth/register` | không | `201 {userId, email, displayName}` |
| POST | `/api/v1/auth/login` | không | `200 {accessToken, tokenType, expiresIn}` + cookie |
| POST | `/api/v1/auth/refresh` | cookie | `200` như login + cookie mới |
| POST | `/api/v1/auth/logout` | cookie | `204` |
| GET | `/api/v1/users/me` | Bearer | `{userId, email, displayName}` |
| PATCH | `/api/v1/users/me` | Bearer | như trên |
| GET | `/api/v1/users/{id}` | không | `{userId, displayName}` |
| GET | `/api/v1/users/{id}/tracks` | tuỳ chọn | `{items, nextCursor}` |
| POST | `/api/v1/tracks` | Bearer | `201 {trackId, title, status}` (multipart) |
| GET | `/api/v1/tracks` | tuỳ chọn | `{items, nextCursor}` |
| GET | `/api/v1/tracks/{id}` | tuỳ chọn | `{id, ownerId, title, description, visibility, status, mimeType, durationSeconds, waveform}` |
| PATCH | `/api/v1/tracks/{id}` | Bearer (owner) | như GET |
| DELETE | `/api/v1/tracks/{id}` | Bearer (owner) | `204` |
| GET | `/api/v1/tracks/{id}/stream-url` | tuỳ chọn | `{url, expiresAt}` |
| GET | `/api/v1/tracks/{id}/stream` | tuỳ chọn hoặc chữ ký | audio, `200` / `206` / `416` |

"Tuỳ chọn" = route công khai nhưng nếu có Bearer thì người xem là user đó (thấy thêm track private của mình).

### 4. Quy ước backend (guide ở Giai đoạn 2 bám theo đúng các mục này)

**Cấu trúc.** Modular Monolith, mỗi module là một package gốc `com.lasono.<module>` (hiện có `track`, `identity`),
bên trong chia 4 lớp:

```
com.lasono.<module>/
├── domain/                  entity, value object, Repository (interface), exception/ , model/ (enum)
├── application/
│   ├── port/out/            port ra ngoài (AudioStorage, PasswordHasher, TrackSummaryReader ...)
│   └── usecase/             <Verb><Noun>UseCase, <Verb><Noun>Command, <Noun>Result, exception của use case
├── infrastructure/          persistence/ (JpaEntity, JpaRepository, <X>PersistenceAdapter), security/, storage/, processing/
└── presentation/            <X>Controller, <X>ExceptionHandler, Request record
```

Cấu hình dùng chung nằm ở `com.lasono.config` (`SecurityConfig`, `CorsConfig`, `JwtConfig`, `ProblemDetailSecurityHandler`).

**Domain.** Không import Spring, JPA, `java.io`, `java.net`... (ArchUnit kiểm tra). Id là value object bọc `UUID`
(`TrackId`, `UserId`, `OwnerId`), có `equals/hashCode` và `getValue()`. Entity có hàm tạo kiểm tra bất biến và
`reconstitute(...)` để dựng lại từ DB. Lỗi nghiệp vụ là `RuntimeException` riêng, đặt trong `domain/exception/`.
Repository của domain là interface trong `domain/` (`TrackRepository`, `UserRepository`), adapter nằm ở infrastructure.

**Use case.** Một lớp `@Component` cho một hành động, hàm `execute(...)`. Đầu vào là record `...Command` hoặc tham số
đơn giản, đầu ra là record `...Result` chứa `String` / số (không trả entity). Dùng `@Transactional` ở use case khi cần
giữ khoá (ví dụ `UpdateTrackUseCase`), `noRollbackFor` khi phải commit trước khi ném lỗi
(`RefreshSessionUseCase`). Truy vấn danh sách đọc qua một port "reader" riêng (`TrackSummaryReader`) trả record
phẳng, không dựng aggregate.

**Adapter.** `<X>JpaEntity` (Lombok `@Getter @NoArgsConstructor(PROTECTED) @AllArgsConstructor`),
`<X>JpaRepository extends JpaRepository`, truy vấn khó viết `@Query(nativeQuery = true)`. Adapter map
entity ↔ domain bằng tay. Ràng buộc DB được bắt bằng **tên constraint** (`uq_users_email`) để đổi thành lỗi domain.
`saveAndFlush` khi cần lỗi unique nổi lên ngay trong hàm.

**Lỗi HTTP.** `@RestControllerAdvice` theo module trả `ProblemDetail` (`application/problem+json`):
`{type:"about:blank", title, status, detail, instance}`. Security (`401`/`403` thiếu token) do
`ProblemDetailSecurityHandler` viết tay với `detail` cố định. Quy ước mã: `400` dữ liệu sai, `401` chưa/không hợp lệ
đăng nhập, `403` thấy được nhưng không có quyền, `404` không có **hoặc không được phép biết là có** (track private
của người khác, quyết định D7), `409` sai trạng thái (track chưa READY, đang PROCESSING), `415` sai định dạng, `416` Range.

**Id, thời gian, phân trang.** Id là UUID dạng chuỗi chữ thường. Thời gian là `Instant` UTC (ISO-8601 khi serialize;
cột `TIMESTAMPTZ`, cắt về micro giây trước khi lưu). Phân trang là keyset: `?cursor=&limit=` (mặc định 20, tối đa 50),
trả `{items, nextCursor}` với `nextCursor = null` ở trang cuối; cursor là Base64URL không padding của
`<micro giây>:<uuid>`; lấy `limit + 1` dòng để biết còn trang sau mà không cần `COUNT`; so sánh cặp
`(created_at, id) < (:createdAt, :id)`; con trỏ hỏng thì `400`.

**Flyway.** File `backend/src/main/resources/db/migration/V<N>__<mo_ta>.sql` (hiện đến `V7`). `ddl-auto: validate`
nên entity phải khớp schema. Không sửa migration đã áp dụng (checksum). Ràng buộc đặt tên `pk_`, `uq_`, `fk_`, `ck_`;
index đặt tên `idx_<bảng>_<cột>`. Module không có khoá ngoại sang bảng của module khác (chỉ giữ id).

**Test.** JUnit 5 + AssertJ (hoặc `assertEquals`), không dùng Mockito cho code mới ở domain/use case: dùng *fake* tự
viết (`InMemoryUserRepository`, `FakePasswordHasher`) và test lại chính fake đó (`InMemoryUserRepositoryTest`).
Controller test dùng `MockMvcBuilders.standaloneSetup(...)` + Mockito cho use case. Test cần PostgreSQL thật kế thừa
`PostgresIntegrationTest` (tag `postgres`, database `lasono_test`, tự xoá bảng trước mỗi test — **khi thêm bảng mới phải
thêm `DELETE FROM <bảng>` vào đó**), chạy bằng `./gradlew postgresTest`; test end-to-end qua HTTP dùng
`@AutoConfigureMockMvc` (ví dụ `ProfilePageOverHttpPostgresTest`). Tên test: `<hành vi>` viết thành câu
(`aSavedUserCanBeFoundById`) hoặc `method_shouldX` ở use case.

**ArchUnit.** `ArchitectureRules` + `ArchitectureTest` kiểm: domain không dùng framework/IO; domain không phụ thuộc
các lớp ngoài; application không phụ thuộc presentation; chỉ infrastructure dùng infrastructure; `track` và `identity`
không phụ thuộc nhau (`moduleDoesNotDependOn`). Mỗi quy tắc có test "cố tình vi phạm" trong `ArchitectureRulesTest`
với lớp mẫu ở `src/test/java/archfixture`. Module mới phải được thêm vào `ArchitectureTest` (mảng `importPackages` và từng quy tắc).

**Bảo mật route.** `SecurityConfig.authorizeHttpRequests` mở từng route cụ thể; mọi thứ còn lại `authenticated()`.
Hiện mở: `/api/v1/auth/**`, `GET /api/v1/tracks/**`, `GET /api/v1/users/*/tracks`, `GET /api/v1/users/*`
(sau `/api/v1/users/me`, thứ tự quan trọng). CORS (`CorsConfig`) chỉ cho `GET, POST, PATCH, DELETE, OPTIONS` từ
`localhost:3000`, `allowCredentials = true`. **`PUT` chưa được cho phép**, nên endpoint `PUT .../like` của Phase 5 cần
sửa `CorsConfig` (đã ghi trong guide 02).

### 5. Những điểm lệch giữa kế hoạch và code thực tế

| # | Kế hoạch nói | Thực tế | Cách xử lý |
|---|--------------|---------|------------|
| 1 | "Router + route guard đang có" | Chưa có router | Thêm `go_router` ở Giai đoạn 5 |
| 2 | Profile ở `/{handle}` | Không có handle, profile theo `userId` | Route `/users/:id` |
| 3 | `TrackCard` có "thời gian đăng tương đối" | Track list/detail **không trả `createdAt`** (cursor có nhưng không lộ ra) | Hợp đồng Phần B thêm `createdAt` (additive); model Dart parse `createdAt` nullable, ẩn dòng thời gian khi thiếu |
| 4 | `TrackCard` có tên tác giả | Track chỉ có `ownerId` (module `track` không biết tên) | Hợp đồng thêm `GET /users?ids=` (batch). Hiện tại `UserDirectory` gọi `GET /users/{id}` song song và cache |
| 5 | "Likes" tab trên profile, `followerCount`... | Backend chưa có | Dữ liệu giả (Giai đoạn 4) |
| 6 | Ảnh bìa, avatar | Backend không có ảnh | Placeholder sinh theo id (Phần C của hợp đồng là OPTIONAL) |
| 7 | `PUT` like/follow | CORS chưa cho `PUT` | Ghi trong guide 02, Leon sửa khi code |

## Tầng dữ liệu (Giai đoạn 4)

UI **không gọi HTTP trực tiếp**: mọi thứ đi qua các interface repository. Một màn hình không biết dữ liệu là thật hay giả.

### Cấu trúc `app/lib/data/`

```
data/
├── repository_exception.dart     RepositoryException + RepositoryErrorKind (network, unauthorized, forbidden, notFound, conflict, invalid, server)
├── track_repository.dart         TrackRepository   → thật: TrackApi (Phase 1-4, giữ nguyên)
├── user_repository.dart          UserRepository    → thật: HttpUserRepository (bọc ProfileApi + batch)
├── social_repository.dart        SocialRepository  (like, follow, comment)
├── feed_repository.dart          FeedRepository    (feed, danh sách track đã like)
├── search_repository.dart        SearchRepository
├── http/                         ApiClient + Http*Repository viết theo docs/api-contract.md Phần B
├── fake/                         FakeWorld (dữ liệu), Fake*Repository, FakeBehavior (trễ + lỗi), FakeAudio, routing_repositories.dart
├── fake_flags.dart               cờ --dart-define theo từng tính năng
├── user_directory.dart           cache tên user (ChangeNotifier)
└── app_repositories.dart         AppRepositories.create(...) + RepositoriesScope (InheritedWidget)
```

| Interface | Dữ liệu thật từ | Phase backend | Cờ fake |
|-----------|-----------------|---------------|---------|
| `TrackRepository` | `TrackApi` | 1-4 (có) | — |
| `UserRepository` | `HttpUserRepository` | 1-4 (có); `GET /users?ids=` và các số đếm thuộc guide 03 | `FAKE_FOLLOWS` (số đếm, `isFollowedByMe`) |
| `SocialRepository` | `HttpSocialRepository` | guide 02, 03, 04 | `FAKE_LIKES`, `FAKE_FOLLOWS`, `FAKE_COMMENTS` (hoặc `FAKE_SOCIAL` cho cả ba) |
| `FeedRepository` | `HttpFeedRepository` | guide 05 | `FAKE_FEED` |
| `SearchRepository` | `HttpSearchRepository` | guide 06 | `FAKE_SEARCH` |

Mỗi `Http*` có TODO ghi rõ guide nào làm route đó. Cờ riêng của một tính năng **thắng** `FAKE_SOCIAL`
(`FAKE_SOCIAL=true FAKE_LIKES=false` = follow/comment giả, like thật).

```bash
# Trạng thái hiện tại: backend Phase 1-4 thật, mọi thứ Phase 5-6 giả
flutter run -d web-server --web-port 3000 \
  --dart-define=FAKE_SOCIAL=true --dart-define=FAKE_FEED=true --dart-define=FAKE_SEARCH=true
```

### Dữ liệu thật và giả sống chung thế nào (định tuyến theo id)

Khi có ít nhất một cờ, mọi lời gọi đi qua `Routing*Repository`:

1. **id giả** (bắt đầu bằng `f4e00000-`) luôn vào repository giả, vì backend thật chưa từng nghe tới nó;
2. id thật vào repository thật, trừ khi cờ của tính năng đó bật (khi ấy dùng bản giả cho id thật luôn);
3. với cờ `likes`/`comments` bật, số like/comment và `isLikedByMe` của **track thật** được thay bằng số của thế giới giả, để màn hình hiện đúng thứ vừa bấm.

Không cờ nào bật thì **không** có lớp định tuyến: dùng thẳng repository thật.

### Thế giới giả (`FakeWorld`, cố định, không ngẫu nhiên)

- 8 user (Sơn Tùng, Đen Vâu, Bích Phương, Hà Anh Tuấn, Minh Anh, Luna Park, DJ Kaito, Maya Chen), 30 track tên Việt lẫn Anh, track xen kẽ tác giả, thời điểm đăng từ vài chục phút đến ~3 tuần trước.
- 28 track `READY` (45-90 giây, 200 peak waveform), 1 `PROCESSING` ("Hạ trắng"), 1 `FAILED` ("Bản tình ca cuối"): thấy đủ các trạng thái.
- Comment rải trên waveform (tổng hơn 60), người comment là các user giả.
- Minh Anh **không follow ai**. User thật đăng nhập lần đầu **không theo dõi ai** (như backend thật), nên bảng tin trống cho tới khi họ theo dõi ai đó. Test dùng `FakeWorld()` mặc định, trong đó user mới theo dõi sẵn Sơn Tùng, Đen Vâu, Luna Park (`newViewerFollowsSome: true`) để có bảng tin đầy.
- **Track giả phát được thật:** `FakeAudio` sinh một file WAV 8 kHz trong bộ nhớ (một giai điệu nhẹ, mỗi track một giai điệu) và trả về dạng `data:` URI, nên play/seek/waveform/comment đều thử được mà không cần file.
- Search giả mô phỏng `unaccent` + `pg_trgm` (cùng công thức độ giống, test ghim đúng các số 9/13, 6/16 của guide 06), nên `son tung` ra `Sơn Tùng` và `son tuhg` vẫn ra.

### Giả lập độ trễ và lỗi

`FakeBehavior` (mặc định trễ ngẫu nhiên 200-600 ms, có seed nên lặp lại được) dùng chung cho mọi repository giả:
`repositories.fakeBehavior!.failing = true` làm **mọi** lời gọi giả lỗi mạng (để xem trạng thái lỗi/thử lại), `failNext(n)` làm hỏng n lời gọi kế tiếp.
(Chưa có công tắc hiển thị trên `/dev/gallery`: xem TODO.)

### Nối một tính năng khi backend của nó xong

1. Làm xong guide tương ứng và kiểm bằng `curl` (mục 10 của guide).
2. Bỏ `--dart-define` của tính năng đó (xem bảng trên). Không sửa code app.
3. Đăng nhập thật và đi hết kịch bản UI ở mục 10 của guide. Nếu khác hợp đồng: sửa `api-contract.md` trước, rồi `Http*Repository` và test `test/data/http/`.
4. Backend và app chỉ cần khớp hợp đồng: các test `test/data/http/*` ghim đúng đường dẫn, query, JSON và mã lỗi của hợp đồng.

### Chạy với backend Phase 1-4 thật: không vỡ

- Field mới (`createdAt`, `likeCount`, `commentCount`, `isLikedByMe`, `followerCount`...) được đọc **an toàn**: thiếu thì mặc định 0/false/null (test `social_models_test.dart`).
- `GET /users?ids=` chưa có → `HttpUserRepository` thử một lần, thấy `404/401/405` thì **tự chuyển sang gọi từng `GET /users/{id}`** (song song) và nhớ như vậy.
- Khác Phase 4: profile được đọc **kèm token** (để `isFollowedByMe` đúng người xem). Nếu server từ chối token hết hạn mà không refresh được, app đọc lại **không token** (route công khai). `ProfileApi.getProfile` cũ (không gửi token) vẫn giữ nguyên, không dùng cho UI mới.
- `RepositoryException.kind` cho UI chọn thông báo (`unauthorized` → mời đăng nhập, `notFound`, `conflict`, `network` → "thử lại"...). `TrackApiException` và `ProfileApiException` nay kế thừa nó (giữ nguyên `message`).

### `UserDirectory`

Danh sách track/comment/follower chỉ có **id** user. `UserDirectory.profiles(ids)` xin tên cho cả trang **bằng một request**, không xin lại id đã biết hoặc đang chờ, nhớ kết quả, và là `ChangeNotifier` để widget vẽ lại khi tên đến. Dùng trong `TrackCard`, `CommentList`, `UserTile`, trang track và hồ sơ.

### Giả định UI đặt cho backend (ghi lại để Giai đoạn 9 đối chiếu)

- `createdAt` có trong mọi track (list, detail); thiếu thì `TrackCard` ẩn dòng "x ngày trước".
- Track private của người khác trả `404` cho like/comment (không `403`).
- `PUT/DELETE` like và follow trả trạng thái mới (`liked`/`following` + số đếm) để UI đồng bộ số mà không phải tải lại.
- Comment `positionMs` được UI kẹp trong `[0, durationMs]` trước khi gửi; server vẫn kiểm lại.
- `GET /users/{id}` và `GET /users?ids=` đọc Bearer nếu có (tuỳ chọn auth) vì `isFollowedByMe` theo người xem; app có đường lui không token khi gặp `401`.
- `GET /users?ids=` nhận tới 50 id; chưa có route thì app gọi từng `GET /users/{id}`.
- `GET /tracks/{id}/comments`: `order=recent&limit=20` cho danh sách, `order=position&limit=100` cho marker trên waveform.
- Search: `limit` ≤ 50 mỗi loại, không có cursor; user trong kết quả không cần `followingCount`.
- `PUT` được CORS cho phép (like, follow).
- Bảng đầy đủ field app đọc và giá trị khi thiếu: `api-contract.md` Phần D.

## App shell (Giai đoạn 5)

### Router (`go_router`) và route guard

App dùng **URL dạng đường dẫn** (`usePathUrlStrategy`): `/dev/gallery`, không có `#`. Server phải trả `index.html` cho mọi địa chỉ (`flutter run` đã làm; bản triển khai: `try_files {path} /index.html`, xem guide 07).

| Route | Trang | Ghi chú |
|-------|-------|---------|
| `/` | Trang chủ | |
| `/tracks/:id`, `/users/:id`, `/users/:id/followers`, `/users/:id/following` | Track, hồ sơ, danh sách người | Profile theo `userId`, **không có handle** (xem khảo sát) |
| `/upload` | Tải lên | Cần đăng nhập |
| `/feed` | Bảng tin | Cần đăng nhập |
| `/search?q=` | Tìm kiếm | Từ khoá nằm trong địa chỉ nên link được và nút Back chạy đúng |
| `/login`, `/register` | Đăng nhập, đăng ký (`?from=` để quay lại) | Ngoài shell, bố cục hai cột |
| `/splash` | Logo + spinner | Trong lúc tìm phiên đăng nhập (cookie refresh); sau đó về đúng chỗ cũ |
| `/dev/gallery` | Trang design system trong shell | Chỉ debug (release chuyển về `/`) |
| mọi địa chỉ khác | Trang 404 thân thiện | Nút "Về trang chủ" |

Các trang trong shell chuyển bằng fade 200 ms (`_fade` trong `app_router.dart`), không fade nếu hệ điều hành bật "giảm chuyển động".

Route guard là hàm thuần `redirectFor(status, location, debug)` (test bảng đầy đủ trong `test/app_router_test.dart`):
- đang tìm phiên → `/splash?from=<nơi đang đứng>`; có câu trả lời → quay lại `from`;
- chưa đăng nhập mà vào `/upload` hoặc `/feed` → `/login?from=...`; đăng nhập xong **tự quay lại** trang đó;
- đã đăng nhập mà vào `/login`/`/register` → về `from` hoặc `/`;
- `from` chỉ nhận địa chỉ **trong app** (`/…`); `https://evil` hay `//evil` bị bỏ (chống open redirect).

### Shell (`lib/shell/`)

`ShellRoute` giữ **một** `AppShell` sống suốt lúc trang bên trong đổi, nên nhạc không ngắt khi chuyển trang (có test: phát ở gallery rồi bấm Feed, `stopCalls == 0` và track không được load lại).

- **`TopBar`**: logo chữ + 5 thanh sóng (không dùng logo/màu của dịch vụ nào khác), mục Trang chủ / Bảng tin (đánh dấu trang hiện tại), ô tìm kiếm lớn ở giữa (gõ xong dừng 400 ms hoặc Enter mới tìm; cần ≥ 2 ký tự; ô tự điền khi mở bằng link `/search?q=`), nút Tải lên, avatar + menu (Trang cá nhân, đổi giao diện sáng/tối, Đăng xuất) hoặc nút Đăng nhập / Tạo tài khoản. Trong lúc chưa biết đã đăng nhập hay chưa là một vòng tròn xám (không nhảy bố cục).
- **`PlayerBar`**: cố định ở đáy, chỉ hiện khi có gì đang phát. Bìa, tên bài + tác giả (bấm để mở), prev / play-pause / next, thanh tiến độ seek được (kéo hoặc bấm), thời gian (chữ số cùng độ rộng, không giật), âm lượng + tắt tiếng. Có trạng thái đang tải (spinner) và lỗi (thông báo + nút thử lại).
- **`PageContainer`**: căn giữa, rộng tối đa 1200, lề 16/24/32 theo cỡ màn hình. Mọi trang trong shell dùng nó.
- Điều hướng đi qua `onGo(location)`: các widget không biết router (dễ test).

| Màn hình | Top bar | Player bar |
|----------|---------|------------|
| expanded (≥ 1024) | đủ: logo chữ, 2 mục, ô tìm kiếm, Tải lên, tài khoản | đủ, có âm lượng |
| medium (600-1024) | như trên | không có âm lượng |
| compact (< 600) | logo (là nút Home), icon Bảng tin / Tìm kiếm / Tải lên, tài khoản; ô tìm kiếm thành icon | **thanh mini**: bìa, tên, next, play-pause, vạch tiến độ mảnh ở trên (bấm để mở bài) |

Đã kiểm tra không tràn ở 320 px (top bar và player bar, tên bài rất dài).

### `PlaybackController` (`lib/playback/`)

Nằm **trên** router, bọc `PlayerService` (vẫn là `just_audio`; logic Range/seek của Phase 1-4 không viết lại).
- **Hàng đợi**: `playQueue(tracks, startIndex, sourceId)`: bấm play trong danh sách nào thì danh sách đó thành hàng đợi. `extendQueue(sourceId, more)` thêm trang kế tiếp của cùng danh sách. Track chưa `READY` nằm trong hàng đợi nhưng bị **bỏ qua** khi next/prev.
- **Next / previous**: previous khi đã phát > 3 s thì phát lại từ đầu, ngược lại lùi một bài. Hết bài tự sang bài kế; hết hàng đợi thì dừng ở bài cuối, về 0:00 (sửa lỗi cũ: `just_audio` giữ `playing = true` sau khi hết, nên seek sau đó không có tiếng).
- Địa chỉ phát được xin **ngay trước khi load từng bài** (không xin cả hàng đợi), giữ đúng cách Phase 4 phát track private bằng địa chỉ có chữ ký.
- Bấm bài khác khi bài trước còn đang tải: bài bấm sau thắng, bài trước không bao giờ được phát (test + mutation check).
- `playing` được cập nhật ngay khi bấm (lạc quan), luồng sự kiện của player chỉ xác nhận: nút không phản hồi chậm một nhịp.
- Vị trí và độ dài là `ValueNotifier` riêng: tick vị trí mỗi 200 ms chỉ vẽ lại thanh tiến độ, không vẽ lại cả bar.
- Đăng xuất **dừng** nhạc và xoá hàng đợi (bài đang phát có thể là bài private của user đó).

### Thành phần đã làm ở giai đoạn này (kéo sớm từ Giai đoạn 6)

`CoverArt` (ảnh bìa hoặc gradient sinh ổn định từ id, FNV-1a nên giống nhau trên mọi nền tảng) và `UserAvatar` (chữ cái đầu `ST`, `ĐV`... + màu theo id, mọi màu đều ≥ 4.5:1 với chữ trắng).

### Phím tắt và tiêu đề tab

- **Space** play/pause. Không bắt phím khi đang gõ trong ô nhập (focus nằm trong `EditableText`) và khi đang có nút được focus thì nút đó nhận Space trước. Có test và mutation check (bỏ điều kiện thì test gõ khoảng trắng đỏ).
- Tiêu đề tab: `LaSono`, hoặc `<tên bài> · LaSono` khi có bài trong hàng đợi (widget `Title` trong `AppShell`).

## Component (Giai đoạn 6)

Xem tất cả ở `http://localhost:3000/dev/gallery` (mục "App components", dùng thế giới dữ liệu giả). Mọi component đều có widget test, kể cả bố cục ở 320 px.

| Component | Việc nó làm | Quyết định đáng nhớ |
|-----------|-------------|---------------------|
| `TrackCard` | bìa vuông, tác giả, tiêu đề, nút play tròn lớn, waveform ngay trong card (bấm để seek **và phát**), like, số comment, "x ngày trước", menu owner, nhãn Riêng tư, trạng thái PROCESSING/FAILED | Không biết hàng đợi: bấm play gọi `onPlay` để **trang** biến danh sách thành hàng đợi. Phone: waveform xuống dưới, nhóm bên phải xuống dòng khi hết chỗ |
| `WaveformView` | thanh **vuông** đứng trên một đường, **phản chiếu** mờ bên dưới (68% chiều cao cho sóng, 32% cho phản chiếu), vạch mảnh ở chỗ đang phát; cột đã phát đổi màu; rê chuột hiện thời gian + vạch; click seek; avatar comment nằm **trong vùng phản chiếu** tại `positionMs`; nội dung nổi lên khi rê vào avatar **hoặc khi phát tới ±1,5 s** | Các comment gần nhau < 22 px gộp thành một avatar kèm "+n". Cần `durationMs`, không có thì không vẽ marker |
| `WaveformCache` | danh sách track **không** mang waveform (200 số × 20 track), nên mỗi card tự đọc waveform của mình **một lần** | gộp request đang bay, không nhớ lỗi, không hỏi track chưa READY |
| `LikeButton`, `FollowButton` | cập nhật ngay (lạc quan), server xác nhận số chính xác; lỗi → quay lại + thông báo tiếng Việt; **bấm lần hai khi lần một chưa xong bị bỏ qua**; chưa đăng nhập → `onNeedLogin`, không gửi request | `unauthorized` khi đang gửi → quay lại + mời đăng nhập lại; mutation check: bỏ chặn bấm đôi / bỏ rollback đều làm test đỏ |
| `CommentComposer` | "Bình luận tại 1:23": thời điểm lấy theo vị trí đang phát **lúc bắt đầu gõ**, bấm chip để chỉnh (`m:ss`, kiểm tra ≤ độ dài), tối đa 500 ký tự đếm theo ký tự người thấy (emoji = 1) | khớp quy tắc server (guide 04) để lỗi hiếm khi tới server |
| `CommentList` | tên tác giả (xin **một request** cho cả trang qua `UserDirectory`), "tại 1:23" bấm để nhảy tới, "3 giờ trước", xoá (tác giả hoặc chủ track) có hộp xác nhận | |
| `ProfileHeader` | banner gradient theo id, avatar đè nửa mép banner, tên, 3 số liệu (người theo dõi, đang theo dõi, bài hát), nút hành động | `StatBlock` bấm được để mở danh sách |
| `SkeletonLoader` | khối shimmer thay chỗ nội dung đang tải | tôn trọng "giảm chuyển động" của hệ điều hành (đứng yên) |
| `EmptyState`, `ErrorState` | trạng thái trống có gợi ý hành động; lỗi có nút "Thử lại"; `ErrorState.from(error)` chọn thông báo theo loại lỗi | `errorMessageFor` giữ nguyên lý do server nói với lỗi `invalid` (cho biết cần sửa gì) |
| `showConfirmDialog`, `showToast` | hộp xác nhận (nút xoá màu lỗi), thông báo ngắn | `showToastOn(messenger, ...)` cho nút đã bị gỡ khỏi màn hình trong lúc request chạy |

### Định dạng (tiếng Việt, `lib/core/text/`)

`relativeTime` ("vừa xong", "5 phút trước", "3 ngày trước", "2 tuần trước", "1 năm trước"; thời điểm ở tương lai do lệch đồng hồ cũng là "vừa xong"), `formatPosition` (`1:23`), `parsePosition`, `formatCount` (`1,2K`), `foldAccents` (bỏ dấu, dùng cho search giả và tô sáng).

### Lỗi thật tìm được nhờ chạy trình duyệt thật

**Hàm băm màu bị sai trên web** (test VM xanh!): trong trình duyệt, `int` của Dart chỉ chính xác tới 2^53, nên phép nhân của FNV-1a (`hash * 0x01000193`) mất bit thấp và mọi avatar cùng một màu. Test chạy trên Chrome (RED), sửa bằng phép nhân tách hai nửa 16 bit (không số nào vượt 2^41), thêm test đối chiếu với thuật toán chuẩn dùng `BigInt` và test "id chỉ khác ký tự cuối ra màu khác nhau".

Chạy test trên trình duyệt (CI chỉ chạy VM):
```bash
CHROME_EXECUTABLE=/đường/dẫn/tới/chrome flutter test --platform chrome test/widgets/cover_art_test.dart
```
Hai test ảnh lỗi (`Image.network`) mô phỏng lỗi theo cách của VM nên bị bỏ qua trên web (`skip: kIsWeb`).

## Lỗi tìm ra khi kiểm tra tay (2026-10-09) và cách đã sửa

Người dùng chạy app thật bằng trình duyệt và báo 6 lỗi. Nguyên nhân gốc và cách giữ cho chúng không quay lại:

| # | Hiện tượng | Nguyên nhân gốc | Cách sửa và giữ |
|---|------------|-----------------|-----------------|
| 1, 3, 5 | Bấm phát bài thứ hai thì vẫn ra nhạc bài đầu; hết độ dài bài đầu thì tự chuyển bài; tua gần cuối cũng tự chuyển bài | Trên web, khi `just_audio` đang phát bài A mà gọi `setUrl` cho bài B thì **không hề gán nguồn mới** cho phần tử `<audio>` (đã xác nhận bằng cách ghi log mọi lần gán `audio.src`: bản cũ chỉ có `el1 src=A`, không bao giờ có B). Controller vẫn tưởng đã nạp B nên giao diện hiện B, còn âm thanh và sự kiện "hết bài" là của A | `JustAudioPlayerService.load` gọi `stop()` trước `setUrl`, để `just_audio` dựng player nền mới cho địa chỉ mới (`lib/player_service.dart`). **Test VM không bắt được lỗi này** (cần trình duyệt thật): xem kịch bản kiểm tra tay bên dưới |
| 2 | Chrome tự điền email/mật khẩu từ bộ nhớ, ô mật khẩu không xoá được ký tự | `AutofillGroup` + `autofillHints` làm Flutter web tạo form cho Chrome điền; sau khi điền, ô mật khẩu mất khả năng sửa | Bỏ `AutofillGroup`/`autofillHints`, đặt `autocorrect: false`, `enableSuggestions: false` (có test). **Đánh đổi:** trình quản lý mật khẩu không điền giúp nữa. Khi Flutter sửa lỗi này có thể bật lại |
| 4 | Tài khoản mới đã "đang theo dõi" Sơn Tùng, Đen Vâu | Dữ liệu giả cho người dùng mới theo dõi sẵn 3 người để bảng tin không trống | `FakeWorld(newViewerFollowsSome: false)` khi chạy app (như backend thật: tài khoản mới theo dõi không ai). Bảng tin ban đầu trống và có nút dẫn về trang chủ. Test vẫn dùng mặc định `true` |
| 6 | "Đang xử lý" mà xoá vẫn được, xoá xong về trang chủ | Backend chặn xoá khi `PROCESSING` (`409`), nên lần xoá được là lúc track **đã xong** nhưng thẻ trong danh sách còn hiện trạng thái cũ (chỉ trang track mới tự làm mới). Về trang chủ sau khi xoá ở trang track là chủ ý | `TrackTile` tự hỏi lại mỗi 3 giây khi còn `PROCESSING` và báo cho danh sách khi xong (có test). Mục "Xoá" bị vô hiệu hoá và ghi "(đang xử lý)" khi `PROCESSING` |

Cải tiến kèm theo: tab "Bài hát" / "Người dùng" của tìm kiếm nói rõ loại nào không có kết quả; waveform đổi sang kiểu thanh vuông có phản chiếu.

### Kịch bản kiểm tra tay sau khi đổi code phát nhạc hoặc waveform

Cần chạy lại trong trình duyệt thật vì `flutter test` (VM) không có `<audio>`:

1. Mở trang chủ (đã có ít nhất 3 bài, bài có độ dài khác nhau), bấm phát bài 1, đợi vài giây, bấm phát bài 2: phải **nghe đúng bài 2** và thanh tiến độ chạy theo độ dài bài 2.
2. Để bài 2 chạy hết: chỉ khi **bài 2 hết** mới tự sang bài 3 (không phải khi hết độ dài bài 1).
3. Tua nhanh nhiều lần gần cuối waveform: không tự sang bài khác trừ khi thật sự hết bài.
4. Cách quan sát khách quan (nếu nghi ngờ): chèn vào `index.html` của bản build một đoạn ghi log mọi lần gán `HTMLMediaElement.src`/`play()`/`pause()`; mỗi bài mới phải có một dòng `src=<id bài đó>`.

## TODO còn lại

| # | Việc | Ghi chú |
|---|------|---------|
| 1 | **Backend Phase 5-6** (like, follow, comment, feed, search, `GET /users?ids=`, `createdAt` và các số đếm) | Việc của Leon, theo `backend-guide/`. Làm xong từng guide thì bỏ cờ tương ứng (mục "Nối một tính năng") |
| 2 | Công tắc "giả lập lỗi mạng / độ trễ" trên `/dev/gallery` | Hiện chỉ đặt được bằng code: `repositories.fakeBehavior!.failing = true` |
| 3 | Tiến độ upload theo phần trăm | Gói `http` không báo tiến độ gửi; thanh hiện là vòng chạy không xác định. Muốn phần trăm cần `XMLHttpRequest`/`dio` trên web |
| 4 | Ảnh bìa và avatar thật | Phần C của hợp đồng (optional). Model đã đọc `coverUrl`/`avatarUrl`; chưa có UI chọn ảnh |
| 5 | Comment > 100 trên một track chỉ hiện 100 marker đầu | Giới hạn đã ghi ở hợp đồng B3 |
| 6 | Search không phân trang | Quyết định có chủ ý của hợp đồng B5 |
| 7 | Quản lý track mới có: sửa tiêu đề/mô tả, đổi riêng tư/công khai, xoá có xác nhận (trên thẻ và trang track) | Không có xoá hàng loạt |
| 8 | Chưa có CI chạy `flutter build web` và test trên Chrome | CI hiện chỉ chạy VM |
| 9 | Kiểm tra tay còn lại: tự điền mật khẩu của Chrome sau khi sửa (không thể mô phỏng trong trình duyệt tự động) | Người dùng đã thử kéo thả upload và đổi tên hồ sơ: đều đạt |
| 10 | Không có test tự động chạy trình duyệt cho lớp phát nhạc | Đã thử: máy này không có Chrome trong WSL nên `flutter test --platform chrome` không chạy được. Nếu có CI với Chrome, thêm một test nạp hai địa chỉ liên tiếp vào `JustAudioPlayerService` và kiểm độ dài |
