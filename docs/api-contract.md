# LaSono API contract

> Hợp đồng giữa backend (Spring Boot) và app (Flutter).
>
> - **Phần A** mô tả những gì **đang chạy** ở Phase 1-4 (đọc từ controller, không đề xuất thay đổi).
> - **Phần B** là những gì **Leon sẽ tự code** ở Phase 5-6. App đã có `Fake*Repository` và `Http*Repository`
>   viết theo đúng phần này, nên khi backend khác hợp đồng thì sửa **hợp đồng trước**, rồi mới sửa code.
> - **Phần C** là mở rộng **OPTIONAL** (ảnh bìa, avatar). UI đẹp ngay cả khi không có.
>
> Cách đọc kèm: [`backend-guide/`](backend-guide/00-how-to-use.md) (cách code từng endpoint),
> [`ui-handoff.md`](ui-handoff.md) (UI dùng endpoint nào ở màn hình nào).

## 0. Quy ước chung (đang áp dụng, Phần B phải theo đúng)

| Chủ đề | Quy ước |
|--------|---------|
| Base URL | `http://localhost:8080` (cấu hình bằng `API_BASE_URL` ở app). Mọi route nằm dưới `/api/v1`. |
| Auth | Header `Authorization: Bearer <accessToken>` (JWT HS256, sống 15 phút, `sub` = id user). Refresh token nằm trong cookie `lasono_refresh`, chỉ dùng với `/auth/*`. |
| Route "tuỳ chọn auth" | Route công khai, nhưng nếu có Bearer thì người xem là user đó. **Bearer hết hạn gửi vào route công khai vẫn bị `401`** (Spring kiểm tra mọi token nó thấy) nên app phải refresh rồi thử lại. |
| Id | UUID, chuỗi chữ thường, ví dụ `"5b0c2d4e-1111-4222-8333-944455566677"`. Id sai định dạng ở path → `400`. |
| Thời gian | `Instant` UTC, ISO-8601 có `Z`, ví dụ `"2026-10-08T12:34:56.789012Z"`. Độ dài âm thanh: `durationSeconds` (số thực, giây); vị trí comment: `positionMs` (số nguyên, mili giây). |
| Phân trang | Keyset: `?cursor=<opaque>&limit=<n>`; `limit` mặc định 20, tối đa 50 (quá thì bị cắt về 50, `< 1` → `400`). Phản hồi `{ "items": [...], "nextCursor": "..." | null }`. `nextCursor = null` ở trang cuối. Cursor là chuỗi mờ (opaque): app không được đọc hay tự tạo. Cursor hỏng → `400 "Invalid cursor"`. |
| Lỗi | `application/problem+json`: `{ "type": "about:blank", "title": "Not Found", "status": 404, "detail": "...", "instance": "/api/v1/..." }`. App chỉ dựa vào `status` và `detail`. `401`/`403` do Spring Security có `detail` cố định, không có `instance`. |
| Mã lỗi | `400` dữ liệu sai · `401` chưa đăng nhập / token sai · `403` thấy được nhưng không có quyền · `404` không tồn tại **hoặc không được phép biết là tồn tại** · `409` sai trạng thái · `415` sai định dạng file · `416` Range sai · `413` file quá lớn. |
| CORS | Chỉ `http://localhost:3000` và `http://127.0.0.1:3000`; methods `GET, POST, PATCH, DELETE, OPTIONS`; `allowCredentials = true`. |
| JSON boolean | Tên field boolean là **`isLikedByMe`**, `isFollowedByMe` (Phần B). Dùng `record` để Jackson giữ nguyên tên (class thường với getter `isLikedByMe()` sẽ bị đổi thành `likedByMe`). |

---

# Phần A. Phase 1-4 (đã chạy)

## A1. Tài khoản

### `POST /api/v1/auth/register` — công khai
Request: `{ "email": "alice@example.com", "displayName": "Alice", "password": "correct horse" }`

Response `201`:
```json
{ "userId": "5b0c2d4e-1111-4222-8333-944455566677", "email": "alice@example.com", "displayName": "Alice" }
```
| Mã | Khi nào |
|----|---------|
| `400` | email sai định dạng, tên rỗng/quá 50 ký tự, mật khẩu < 8 ký tự hoặc > 72 **byte** |
| `409` | email đã đăng ký (`"Email already registered: ..."`) |

Màn hình: Đăng ký. Email được chuẩn hoá chữ thường, tên được cắt khoảng trắng hai đầu.

### `POST /api/v1/auth/login` — công khai (bỏ qua header Authorization)
Request: `{ "email": "alice@example.com", "password": "correct horse" }`

Response `200` (kèm `Set-Cookie: lasono_refresh=...; HttpOnly; Secure; SameSite=Strict; Path=/api/v1/auth`, `Cache-Control: no-store`):
```json
{ "accessToken": "eyJhbGciOi...", "tokenType": "Bearer", "expiresIn": 900 }
```
`401 "Invalid email or password"` cho **mọi** thất bại (email lạ, sai mật khẩu): cố ý không phân biệt.

### `POST /api/v1/auth/refresh` — dùng cookie
Không body. Response `200` giống login, cookie mới thay cookie cũ. `401 "Invalid refresh token"` (cùng một câu trả lời cho thiếu, lạ, hết hạn, đã thu hồi, đã dùng rồi). Dùng lại token đã dùng → thu hồi cả "gia đình" token. **Không có thời gian ân hạn**: app chỉ được gửi một refresh tại một thời điểm.

### `POST /api/v1/auth/logout` — dùng cookie
Không body. Luôn `204`, xoá cookie.

### `GET /api/v1/users/me` — Bearer
```json
{ "userId": "5b0c2d4e-...", "email": "alice@example.com", "displayName": "Alice" }
```
`401` nếu token sai, hoặc nếu tài khoản của token không còn tồn tại.

### `PATCH /api/v1/users/me` — Bearer
Request: `{ "displayName": "Alice B." }` → `200` như `GET /users/me`. `400` nếu tên rỗng hoặc dài hơn 50 ký tự hoặc thiếu field.

### `GET /api/v1/users/{id}` — công khai
```json
{ "userId": "5b0c2d4e-...", "displayName": "Alice" }
```
Không bao giờ có email. `404 "No user with id ..."`. **App không gửi token vào route này** (xem ghi chú ở `ui-handoff.md`).

### `GET /api/v1/users/{id}/tracks?cursor=&limit=` — tuỳ chọn auth
`{ items: [Track tóm tắt], nextCursor }`. Ai cũng thấy track `PUBLIC`; track `PRIVATE` chỉ hiện khi người xem chính là chủ. Id lạ → danh sách rỗng (track module không biết user có tồn tại hay không); app đọc profile trước để hiện "không tìm thấy".

## A2. Track

**Track tóm tắt** (phần tử của `items`):
```json
{
  "id": "0c1f...", "ownerId": "5b0c...", "title": "Nắng ấm xa dần", "description": "demo",
  "visibility": "PUBLIC", "status": "READY", "durationSeconds": 213.4
}
```
`status`: `PROCESSING` | `READY` | `FAILED`. `visibility`: `PUBLIC` | `PRIVATE`. `durationSeconds` là `null` cho đến khi `READY`.

**Track chi tiết** (`GET/PATCH /tracks/{id}`):
```json
{
  "id": "0c1f...", "ownerId": "5b0c...", "title": "Nắng ấm xa dần", "description": "demo",
  "visibility": "PUBLIC", "status": "READY", "mimeType": "audio/mpeg",
  "durationSeconds": 213.4, "waveform": [0.02, 0.31, 0.58]
}
```
`waveform` là 200 số trong [0, 1], `null` cho đến khi `READY`. Danh sách **không** trả `waveform` và `mimeType`.

### `POST /api/v1/tracks` — Bearer, `multipart/form-data`
Fields: `title` (bắt buộc), `description` (tuỳ chọn), `visibility` (`PUBLIC`|`PRIVATE`, mặc định `PUBLIC`), `file` (MP3/WAV, ≤ 50 MB).

Response `201`: `{ "trackId": "0c1f...", "title": "Nắng ấm xa dần", "status": "PROCESSING" }`
(chú ý: field là `trackId`, không phải `id`).

| Mã | Khi nào |
|----|---------|
| `400` | title rỗng, file rỗng, `visibility` không hợp lệ (`"Visibility must be PUBLIC or PRIVATE"`) |
| `401` | không có/không hợp lệ token |
| `413` | file > 50 MB (có header CORS) |
| `415` | `Content-Type` của phần file không phải `audio/mpeg`, `audio/wav`, `audio/x-wav` |

Chủ track là user trong token, không bao giờ là field của request. Sau `201`, một worker nền chuyển `PROCESSING → READY` (thường vài giây) hoặc `FAILED` (sau 3 lần thử, ~95 giây).

### `GET /api/v1/tracks?cursor=&limit=` — tuỳ chọn auth
`{ items: [Track tóm tắt], nextCursor }`, mới nhất trước (sắp theo `created_at DESC, id DESC`). Chỉ track `PUBLIC` và track `PRIVATE` của chính người xem.

### `GET /api/v1/tracks/{id}` — tuỳ chọn auth
Track chi tiết. `404` nếu không có **hoặc** track private của người khác.

### `PATCH /api/v1/tracks/{id}` — Bearer, chỉ chủ
Request: `{ "title": "...", "description": "...", "visibility": "PRIVATE" }`, field vắng = giữ nguyên, `description: ""` = xoá. Response `200` Track chi tiết.
`400` (title rỗng / visibility sai; không có gì bị đổi), `401`, `403` (track public nhưng không phải của bạn), `404` (không có, hoặc private của người khác).

### `DELETE /api/v1/tracks/{id}` — Bearer, chỉ chủ
`204`. `403`/`404` như PATCH. `409` khi track còn `PROCESSING` ("try again in a moment").

### `GET /api/v1/tracks/{id}/stream-url` — tuỳ chọn auth
`200 { "url": "/api/v1/tracks/0c1f.../stream?expires=1791466496&signature=ab12...", "expiresAt": "2026-10-08T13:34:56Z" }`, `Cache-Control: no-store`. `url` là đường dẫn tương đối, app ghép với base URL. Hiệu lực 1 giờ. `404` nếu người xem không được xem track. Địa chỉ này là chìa khoá: không log, không chia sẻ.

### `GET /api/v1/tracks/{id}/stream` — công khai hoặc có chữ ký
Header `Range: bytes=0-` tuỳ chọn. Query `expires` + `signature` thay cho header Authorization (cần cả hai, thiếu một thì coi như không có).
| Mã | Khi nào |
|----|---------|
| `200` | toàn bộ file MP3 (`Accept-Ranges: bytes`) |
| `206` | có `Range`, kèm `Content-Range: bytes 5242880-10544133/10544134` |
| `404` | track không có / private và người gọi không có quyền / chữ ký sai hoặc hết hạn |
| `409` | track chưa `READY` (đang xử lý, hoặc `FAILED`) |
| `416` | Range không hợp lệ, kèm `Content-Range: bytes */<size>` |

## A3. Ghi chú về Phần A (điểm đáng cải thiện, **không** nằm trong Phase 1-4)

Chỉ ghi lại, không đổi. Những mục có ✔ được Phần B xử lý.

| # | Quan sát | Hệ quả cho UI |
|---|----------|---------------|
| 1 ✔ | Track tóm tắt/chi tiết **không có `createdAt`** (cursor có nó nhưng không lộ ra). | Không hiển thị được "3 ngày trước". Phần B thêm `createdAt`. |
| 2 ✔ | Track chỉ có `ownerId`, không có tên tác giả; module `track` không được biết `identity` (quy tắc ArchUnit). | App phải hỏi tên. Phần B thêm `GET /users?ids=` (batch) để tránh N request. |
| 3 | Đặt tên không đồng nhất: upload trả `trackId`, các nơi khác trả `id`; profile trả `userId`. | Model Dart xử lý riêng từng chỗ. Không đổi vì sẽ làm vỡ client hiện có. |
| 4 | `GET /users/{id}/tracks` với id lạ trả `200` danh sách rỗng. | App đọc profile trước (đã làm). |
| 5 | Track tạo ở Phase 1-2 không có job xử lý nên kẹt `PROCESSING` mãi. | UI hiển thị đúng trạng thái; không phải lỗi UI. |
| 6 | Mime type của file chỉ dựa vào `Content-Type` client gửi (không kiểm tra magic bytes); file sai thành `FAILED` sau ~95 s. | Upload UI nên kiểm tra đuôi `.mp3`/`.wav` trước (đã có). |
| 7 | Không rate limit đăng nhập; `register` trả `409` cho email đã có (lộ email nào đã đăng ký). | Ghi nhận ở `docs/phase-4-identity.md` (Known limits). |

---

# Phần B. Phase 5-6 (Leon code)

> Quyết định kiến trúc nền cho Phần B (chi tiết và lý do nằm trong guide 01-06):
> 1. Module mới `engagement` (likes, follows, comments) và `discovery` (feed, search, chỉ đọc). Module `track` và
>    `identity` vẫn **không biết nhau** và không biết `engagement`.
> 2. **Mọi tham chiếu chéo module trong JSON chỉ là id** (`ownerId`, `authorId`, `userId`); tên hiển thị lấy qua
>    `GET /users?ids=` (batch). Cùng tinh thần quyết định Phase 4: "app ghép câu trả lời của hai module".
>    Ngoại lệ có chủ ý: `GET /search` trả luôn danh sách user (có tên) vì discovery tự truy vấn bảng `users`.
> 3. Bộ đếm (`likeCount`, `commentCount`, `followerCount`, `followingCount`) là cột phi chuẩn hoá nằm ở bảng của module
>    hiển thị chúng (`tracks`, `users`), cập nhật bằng domain event cùng transaction.

## B0. Các kiểu dùng chung

**Track tóm tắt (mới)** = Track tóm tắt của Phần A cộng 4 field:
```json
{
  "id": "0c1f...", "ownerId": "5b0c...", "title": "Nắng ấm xa dần", "description": "demo",
  "visibility": "PUBLIC", "status": "READY", "durationSeconds": 213.4,
  "createdAt": "2026-10-08T12:34:56.789012Z",
  "likeCount": 12, "commentCount": 3, "isLikedByMe": false
}
```
**Track chi tiết (mới)** = Track chi tiết của Phần A cộng cùng 4 field.

| Field | Ý nghĩa |
|-------|---------|
| `createdAt` | Thời điểm tạo track (cột `tracks.created_at` đã có). |
| `likeCount`, `commentCount` | Số nguyên ≥ 0. `commentCount` đếm mọi comment của track. |
| `isLikedByMe` | `true` nếu người xem đã like. **Luôn `false` khi không đăng nhập.** |

Thêm field là thay đổi **tương thích ngược**: app cũ bỏ qua field lạ. Ngược lại, app mới phải chịu được backend cũ
chưa trả 4 field này (`createdAt = null`, `likeCount = 0`, `commentCount = 0`, `isLikedByMe = false`).

**Profile (mới)** = Profile của Phần A cộng 3 field:
```json
{ "userId": "5b0c...", "displayName": "Alice", "followerCount": 5, "followingCount": 2, "isFollowedByMe": true }
```
`isFollowedByMe` luôn `false` khi không đăng nhập và khi xem chính mình.

**Bình luận**:
```json
{
  "id": "9d3e...", "trackId": "0c1f...", "authorId": "5b0c...",
  "positionMs": 83000, "text": "Đoạn này hay quá!", "createdAt": "2026-10-08T12:40:00Z"
}
```

### Quy tắc hiển thị (áp dụng cho MỌI endpoint Phần B)

1. Track `PRIVATE` của người khác **không bao giờ** xuất hiện trong feed, search, danh sách like, hay bất kỳ
   danh sách nào; truy cập trực tiếp (like, comment, liệt kê comment) trả **`404`**.
2. **Vì sao `404` mà không phải `403`:** `403` nói "track này có tồn tại nhưng bạn không được phép", tức là lộ
   sự tồn tại (và id) của một track riêng tư. `404` làm track private của người khác không phân biệt được với
   track không có thật. Đây là quyết định D7 của Phase 4; `403` chỉ dùng khi thấy được mà không có quyền (xoá comment
   của người khác trên track public).
3. Feed và search chỉ hiện track `READY` + `PUBLIC`.
4. Comment và like cần track `READY` (comment cần `durationMs` để kiểm tra `positionMs`). Track chưa `READY` → `409`.

## B1. Likes

### `PUT /api/v1/tracks/{id}/like` — Bearer
Không body. **Idempotent**: gọi lần 2 trả đúng kết quả lần 1, bộ đếm không đổi.

Response `200`:
```json
{ "trackId": "0c1f...", "liked": true, "likeCount": 13 }
```
| Mã | Khi nào |
|----|---------|
| `401` | chưa đăng nhập |
| `404` | track không có, hoặc private của người khác |
| `409` | track chưa `READY` |

Màn hình: `LikeButton` trong `TrackCard`, trang track, player bar. Được phép like track của chính mình.

### `DELETE /api/v1/tracks/{id}/like` — Bearer
Idempotent. Response `200 { "trackId": "...", "liked": false, "likeCount": 12 }`. Cùng bảng lỗi (không có `409`: bỏ like một track không còn `READY` vẫn được).

### `GET /api/v1/users/{id}/likes?cursor=&limit=` — tuỳ chọn auth
`{ items: [Track tóm tắt (mới)], nextCursor }`. Sắp theo **thời điểm like** mới nhất trước (keyset trên `(liked_at, track_id)`),
chỉ gồm track người xem được phép thấy. Id user lạ → `404`.
Màn hình: tab "Likes" của Profile.

## B2. Follows

### `PUT /api/v1/users/{id}/follow` — Bearer
Idempotent. Response `200`: `{ "userId": "<người được follow>", "following": true, "followerCount": 6 }`.
| Mã | Khi nào |
|----|---------|
| `400` | tự follow chính mình (`"You cannot follow yourself"`) |
| `401` | chưa đăng nhập |
| `404` | user không tồn tại |

### `DELETE /api/v1/users/{id}/follow` — Bearer
Idempotent. Response `200 { "userId": "...", "following": false, "followerCount": 5 }`. Bỏ follow chính mình / người chưa follow: vẫn `200` (không có gì để làm).

### `GET /api/v1/users/{id}/followers?cursor=&limit=` và `GET /api/v1/users/{id}/following?cursor=&limit=` — công khai
```json
{ "items": [ { "userId": "7a8b...", "followedAt": "2026-10-01T08:00:00Z" } ], "nextCursor": "..." }
```
Sắp theo `followedAt` mới nhất trước, keyset `(followed_at, user_id)`. Chỉ trả id; app lấy tên và `isFollowedByMe`
bằng `GET /users?ids=`. User lạ → `404`.
Màn hình: Followers / Following, `UserTile` + `FollowButton`.

### `GET /api/v1/users/{id}` (mở rộng) và `GET /api/v1/users?ids=a,b,c` (mới, batch) — công khai
`GET /users/{id}` trả Profile (mới) ở B0. `GET /users?ids=` nhận tối đa **50** id, cách nhau dấu phẩy:
```json
{ "items": [ { "userId": "...", "displayName": "...", "followerCount": 0, "followingCount": 0, "isFollowedByMe": false } ] }
```
Id lạ bị bỏ qua (không lỗi); thứ tự không đảm bảo; `> 50` id hoặc id sai định dạng → `400`. Dùng cho tên tác giả
trên `TrackCard`, tên người comment, danh sách followers.

### `GET /api/v1/users/{id}/tracks` (mở rộng)
Thêm field `totalCount` vào phản hồi: số track **người xem được phép thấy** của user đó. Dùng cho `StatBlock` "Tracks".
```json
{ "items": [ ... ], "nextCursor": "...", "totalCount": 14 }
```

## B3. Comments

### `POST /api/v1/tracks/{id}/comments` — Bearer
```json
{ "positionMs": 83000, "text": "Đoạn này hay quá!" }
```
Response `201` Bình luận. Quy tắc: `text` sau khi cắt khoảng trắng dài 1-500 ký tự; `0 ≤ positionMs ≤ durationMs` của track
(`durationMs = round(durationSeconds * 1000)`).
| Mã | Khi nào |
|----|---------|
| `400` | text rỗng/quá dài; `positionMs` âm hoặc lớn hơn `durationMs` (detail nói rõ giới hạn) |
| `401` | chưa đăng nhập |
| `404` | track không có / private của người khác |
| `409` | track chưa `READY` |

### `GET /api/v1/tracks/{id}/comments?order=position|recent&cursor=&limit=` — tuỳ chọn auth
`{ items: [Bình luận], nextCursor }`.
- `order=position` (mặc định): `positionMs` tăng dần, keyset `(position_ms, id)`. Dùng để vẽ marker trên waveform. `limit` mặc định **50**, tối đa **200**.
- `order=recent`: mới nhất trước, keyset `(created_at, id)`. Dùng cho danh sách bên dưới waveform.
- Cursor của order này không dùng được cho order kia → `400`. `order` lạ → `400`. `404` như B1.

UI v1.0 tải tối đa 200 marker đầu theo `order=position`; track nhiều hơn 200 comment chỉ hiện 200 đầu trên waveform (ghi nhận là giới hạn).

### `DELETE /api/v1/tracks/{id}/comments/{commentId}` — Bearer
`204`. Được xoá: tác giả comment **hoặc** chủ track.
| Mã | Khi nào |
|----|---------|
| `403` | thấy track (public) nhưng không phải tác giả comment cũng không phải chủ track |
| `404` | track không có/private của người khác; hoặc comment không thuộc track này / không tồn tại (gọi lần 2 sau khi xoá cũng `404`) |

## B4. Feed

### `GET /api/v1/feed?cursor=&limit=` — Bearer
`{ items: [Track tóm tắt (mới)], nextCursor }`: track `READY` + `PUBLIC` của những người **mình đang follow**,
mới nhất trước, keyset `(created_at, id)`. Không gồm track của chính mình. Không follow ai → `items: []`
(UI hiện gợi ý đi tìm người để follow). `401` nếu chưa đăng nhập.

## B5. Search

### `GET /api/v1/search?q=son%20tung&type=all&limit=20` — tuỳ chọn auth
| Param | Ý nghĩa |
|-------|---------|
| `q` | bắt buộc; sau khi cắt khoảng trắng dài 2-100 ký tự, ngược lại `400`. |
| `type` | `all` (mặc định) \| `tracks` \| `users`. |
| `limit` | số kết quả **mỗi loại**, mặc định 20, tối đa 50. |

```json
{
  "tracks": [ { "...Track tóm tắt (mới)..." } ],
  "users":  [ { "userId": "7a8b...", "displayName": "Sơn Tùng", "followerCount": 120, "isFollowedByMe": false } ]
}
```
Khớp không phân biệt dấu và hoa thường (`"son tung"` khớp `"Sơn Tùng"`), cho cả lỗi gõ nhẹ (trigram). Track: khớp `title`; user:
khớp `displayName`. Xếp theo độ giống giảm dần, hoà thì mới hơn trước. Loại không được hỏi trả mảng rỗng.

**Chọn không dùng cursor ở v1.0:** thứ hạng theo độ giống không ổn định để làm keyset (điểm giống thay đổi theo từ khoá và
nhiều kết quả bằng điểm), người dùng hiếm khi lật quá vài chục kết quả, và `limit ≤ 50` đã đủ. Hướng nâng cấp (keyset theo
`(score, id)` hoặc `OFFSET`) nằm ở bài tập mở rộng của guide 06.

## B6. Thay đổi lên endpoint cũ (tổng hợp)

| Endpoint | Thay đổi | Loại |
|----------|----------|------|
| `GET /tracks`, `GET /users/{id}/tracks`, `GET /tracks/{id}`, `PATCH /tracks/{id}` | thêm `createdAt`, `likeCount`, `commentCount`, `isLikedByMe` | additive |
| `GET /users/{id}/tracks` | thêm `totalCount` | additive |
| `GET /users/{id}` | thêm `followerCount`, `followingCount`, `isFollowedByMe` | additive |
| `CorsConfig` | thêm method `PUT` | cấu hình |
| `SecurityConfig` | mở route mới (xem từng guide) | cấu hình |

## B7. Màn hình → endpoint

| Màn hình | Endpoint |
|----------|----------|
| Home | `GET /tracks`, `GET /users?ids=`, `PUT/DELETE /tracks/{id}/like` |
| Track detail | `GET /tracks/{id}`, `GET /tracks/{id}/stream-url`, `GET /tracks/{id}/comments`, `POST/DELETE comments`, like |
| Profile | `GET /users/{id}`, `GET /users/{id}/tracks`, `GET /users/{id}/likes`, `PUT/DELETE /users/{id}/follow` |
| Followers / Following | `GET /users/{id}/followers|following`, `GET /users?ids=`, follow |
| Feed | `GET /feed`, `GET /users?ids=`, like |
| Search | `GET /search`, follow, like |
| Upload / Quản lý track | Phần A |

---

# Phần C. Mở rộng tuỳ chọn (OPTIONAL)

**Ảnh bìa track và avatar user.** Không bắt buộc cho v1.0: UI dùng placeholder gradient sinh theo id nếu không có URL ảnh.
Gợi ý nếu Leon muốn làm: port `ImageStorage` (như `AudioStorage`, adapter lưu file cục bộ), kiểm tra loại file (JPEG/PNG/WebP, ≤ 2 MB).

| Endpoint | Mô tả |
|----------|-------|
| `PUT /api/v1/tracks/{id}/cover` | Bearer, chỉ chủ, `multipart` field `file`. `200` Track chi tiết. `415`, `413`, `403`, `404` như upload. |
| `GET /api/v1/tracks/{id}/cover` | Công khai theo quyền xem track; trả bytes ảnh + `Cache-Control`. `404` nếu chưa có. |
| `PUT /api/v1/users/me/avatar` | Bearer, `multipart` field `file`. |
| `GET /api/v1/users/{id}/avatar` | Công khai. `404` nếu chưa có. |

Field mới (nullable) nếu có làm: `coverUrl` ở Track, `avatarUrl` ở Profile. Model Dart đã đọc hai field này và mặc định `null`.
