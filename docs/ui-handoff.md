# LaSono UI: tài liệu bàn giao

> Đọc kèm [`UI_BUILD_PLAN.md`](UI_BUILD_PLAN.md) (kế hoạch), [`api-contract.md`](api-contract.md) (hợp đồng API)
> và [`backend-guide/`](backend-guide/00-how-to-use.md) (hướng dẫn tự code backend Phase 5-7).
>
> File này được viết dần theo từng giai đoạn. Mục **Tiến độ** ở dưới luôn phản ánh đúng những gì đã commit.

## Tiến độ

| Giai đoạn | Nội dung | Trạng thái |
|-----------|----------|------------|
| 0 | Khảo sát (mục "Khảo sát" bên dưới) | Xong |
| 1 | `docs/api-contract.md` | Xong |
| 2 | `docs/backend-guide/` + `docs/backend-checklist.md` | Xong |
| 3 | Design system (`lib/core/theme/`, `/dev/gallery`) | Xong: token màu (dark mặc định + light, WCAG AA có test), font Be Vietnam Pro nhúng, spacing/radius/elevation/motion/breakpoint, 2 theme, `ThemeController`. Xem trang tại `http://localhost:3000/#/dev/gallery` (chỉ debug) |
| 4 | Tầng dữ liệu (repository + `Fake*` + `Http*`) | Chưa |
| 5 | App shell (top bar, player bar, hàng đợi, router) | Chưa |
| 6 | Component | Chưa |
| 7 | Màn hình | Chưa |
| 8 | Hoàn thiện | Chưa |
| 9 | Đối chiếu và bàn giao | Chưa |

## Khảo sát (Giai đoạn 0)

Khảo sát dựa trên code ở `main` ngày 2026-10-08 (commit `8f542a3`), baseline: `flutter analyze` sạch,
232 test Flutter pass.

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
