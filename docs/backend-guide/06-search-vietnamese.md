# Guide 06: Tìm kiếm tiếng Việt (không dấu) với PostgreSQL

> Phase 6 · Cần xong trước: [guide 05](05-feed.md) (module `discovery`) — kỹ thuật độc lập với 02-04, có thể làm sớm hơn nếu muốn.
> Mục tiêu học: `unaccent`, `pg_trgm`, hàm IMMUTABLE, chỉ mục GIN, xếp hạng độ giống.

## 1. Mục tiêu và nghiệm thu

**Làm gì.** `GET /search?q=son tung` tìm track theo tiêu đề và user theo tên hiển thị, **không phân biệt dấu và hoa thường**, chịu được lỗi gõ nhẹ,
xếp kết quả giống nhất lên đầu. Theo [`api-contract.md` B5](../api-contract.md#b5-search).

**Xong khi:**

- [ ] `q=son tung` tìm ra user `Sơn Tùng` và track `Sơn Tùng M-TP`; `q=Sơn Tùng`, `q=SON TUNG`, `q=sơn tung` cho cùng kết quả.
- [ ] `q=nang am` tìm ra `Nắng ấm xa dần`; `q=den` tìm ra `Đen Vâu` (chữ `Đ`).
- [ ] Lỗi gõ nhẹ (`son tuhg`) vẫn ra `Sơn Tùng`.
- [ ] Chỉ track `READY` + `PUBLIC`; track private/đang xử lý không bao giờ xuất hiện.
- [ ] `q` ngắn hơn 2 ký tự (sau khi cắt khoảng trắng) hoặc dài hơn 100 → `400`; `type` lạ → `400`; `limit` mặc định 20, tối đa 50.
- [ ] Ký tự `%`, `_`, `\` trong `q` được coi là chữ thường (không là ký tự đại diện).
- [ ] Truy vấn dùng chỉ mục GIN (chứng minh bằng `EXPLAIN`) trên dữ liệu 100 000 dòng.
- [ ] App chạy với `FAKE_SEARCH` tắt.

## 2. Kiến thức cần biết trước

| Khái niệm | Đọc ở đâu |
|-----------|-----------|
| Extension `unaccent` (bỏ dấu) | [PostgreSQL: unaccent](https://www.postgresql.org/docs/current/unaccent.html) |
| Extension `pg_trgm` (trigram, `similarity`, `%`, `<%`, GIN/GiST) | [PostgreSQL: pg_trgm](https://www.postgresql.org/docs/current/pgtrgm.html) |
| Mức biến động của hàm: `IMMUTABLE` / `STABLE` / `VOLATILE` | [PostgreSQL: Function Volatility Categories](https://www.postgresql.org/docs/current/xfunc-volatility.html) |
| Chỉ mục trên biểu thức | [PostgreSQL: Indexes on Expressions](https://www.postgresql.org/docs/current/indexes-expressional.html) |
| Chỉ mục GIN | [PostgreSQL: GIN](https://www.postgresql.org/docs/current/gin.html) |
| Extension "trusted" (không cần superuser để `CREATE EXTENSION`) | [PostgreSQL: CREATE EXTENSION](https://www.postgresql.org/docs/current/sql-createextension.html) |
| Chuẩn hoá Unicode NFC/NFD | [Java: `java.text.Normalizer`](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/text/Normalizer.html) |
| Hibernate/JDBC: tham số đặt tên | `NamedParameterJdbcTemplate` (guide 05) |

Ba điều cần nắm chắc:

1. **Trigram** = mọi chuỗi 3 ký tự liên tiếp của một từ, sau khi đệm 2 dấu cách đầu và 1 dấu cách cuối. `son` → `"  s"`, `" so"`, `"son"`, `"on "`. Hai chuỗi giống nhau khi có nhiều trigram chung.
   `similarity(a, b) = |chung| / |hợp|`, trong [0, 1].
2. **Chỉ mục trên biểu thức chỉ được dùng khi truy vấn viết đúng cùng biểu thức.** Index trên `f_unaccent(lower(title))` thì `WHERE f_unaccent(lower(title)) % …` mới dùng được nó.
3. **Hàm trong biểu thức của index phải `IMMUTABLE`** (cùng đầu vào luôn cùng đầu ra, mãi mãi). `unaccent(text)` mặc định là `STABLE` (kết quả phụ thuộc từ điển có thể đổi), nên PostgreSQL từ chối dùng nó trong index.

## 3. Quyết định thiết kế

### D1. Công cụ tìm kiếm nào?

| Phương án | Hợp với | Nhược |
|-----------|---------|-------|
| `ILIKE '%q%'` | Cực nhỏ | Không bỏ dấu, không chỉ mục, quét toàn bảng. |
| **`unaccent` + `pg_trgm` (GIN)** *(khuyến nghị)* | Vài trăm nghìn dòng, tìm gần đúng, không thêm hệ thống | Không hiểu ngữ nghĩa/từ đồng nghĩa; không có stemming tiếng Việt. |
| Full-text search (`tsvector`, `to_tsquery`) | Văn bản dài, tìm theo từ khoá | Tiếng Việt không có cấu hình từ điển tốt sẵn có; không chịu lỗi gõ. |
| Elasticsearch/OpenSearch | Hàng triệu tài liệu, xếp hạng phức tạp | Thêm hệ thống (dự án hoãn đến Phase 8 nếu có số đo). |

Tiêu đề track và tên người ngắn, người dùng gõ gần đúng: trigram là lựa chọn tự nhiên.

### D2. Chuẩn hoá thế nào?

Cả cột và từ khoá được đưa về cùng một dạng **`f_unaccent(lower(x))`**: bỏ dấu rồi viết thường. Hàm `f_unaccent` là *wrapper IMMUTABLE* quanh `unaccent` (mục 6, bước 1).
Đã kiểm chứng trên PostgreSQL 17 của dự án: `f_unaccent(lower('Đặng Thị Đào ơ ư Sơn Tùng'))` → `dang thi dao o u son tung` (chữ `đ`, `ơ`, `ư` đều được xử lý), và chữ **đã tách dấu (NFD)** cũng ra `son tung`.
Nhưng hãy tự chạy lại điều đó trên database của bạn trong test (bước 1): dựa vào test, không dựa vào lời tôi.

### D3. Chọn toán tử nào để khớp? (quyết định quan trọng nhất)

Thí nghiệm trên chính PostgreSQL của dự án:

| Truy vấn | Tiêu đề | `similarity` | `word_similarity(q, tiêu đề)` |
|----------|---------|--------------|-------------------------------|
| `son tung` | `Sơn Tùng M-TP` | **0,69** (9/13 trigram) | 1 |
| `son` | `Sơn Tùng M-TP` | **0,31** (4/13; ngưỡng mặc định là 0,3, sát nút!) | 1 |
| `nang am` | `Nắng ấm xa dần` | 0,53 | — |

Từ khoá ngắn gần như không bao giờ đạt `similarity` cao với tiêu đề dài, vì mẫu số là tất cả trigram của tiêu đề. Do đó:

| Điều kiện | Dùng cho | Chỉ mục? |
|-----------|----------|----------|
| `col % q` (similarity ≥ `pg_trgm.similarity_threshold` = 0,3) | gõ gần đúng, từ khoá dài | GIN |
| **`q <% col`** (word similarity) | từ khoá là **một phần** của tiêu đề (`son` trong `Sơn Tùng M-TP`) | GIN |
| `col LIKE '%q%'` | chuỗi con chính xác (sau chuẩn hoá) | GIN (pg_trgm hỗ trợ `LIKE`) |

**Khuyến nghị:** lọc bằng `% OR <% OR LIKE`, xếp hạng bằng `GREATEST(similarity, word_similarity)`. Kết hợp ba điều kiện cùng biểu thức đã chỉ mục, planner dùng `BitmapOr` trên GIN.

### D4. Có phân trang không?

Không (xem hợp đồng B5): `limit` kết quả hàng đầu mỗi loại. Xếp hạng theo điểm giống không ổn định để làm keyset, và rất ít người lật quá vài chục kết quả.

### D5. Người dùng nào được trả về?

Mọi user (tên là thông tin công khai). Cân nhắc loại tài khoản "Legacy" (do migration V6 tạo cho track cũ, `password_hash = '!'`, không đăng nhập được): đừng để nó chiếm kết quả `q=legacy`. Quyết định và ghi lại bằng test.

## 4. Vị trí trong kiến trúc

```
com.lasono.discovery
├── application/
│   ├── port/out/ SearchReader
│   └── usecase/  SearchUseCase, SearchQuery (kiểm tra q/type/limit), SearchResult, UserHit, InvalidSearchException
├── infrastructure/persistence/ SearchReaderJdbc
└── presentation/ SearchController (+ DiscoveryExceptionHandler)
```
Cùng module `discovery` với guide 05, **cùng quy tắc ba rào chắn** (chỉ `SELECT`, SQL chỉ ở infrastructure, có `postgresTest`). Không phụ thuộc module nào khác.
`GET /api/v1/search` cần `permitAll` trong `SecurityConfig` (viewer tuỳ chọn).

## 5. Schema

```sql
-- V15__search_extensions_and_indexes.sql
-- Both extensions are "trusted" since PostgreSQL 13, so the owner of the database may create them without being a superuser.
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- unaccent() is STABLE, and an index may only use IMMUTABLE functions. This wrapper pins the dictionary
-- ('public.unaccent'), so the result cannot change between calls, and tells PostgreSQL so.
CREATE OR REPLACE FUNCTION f_unaccent(text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
AS $$ SELECT public.unaccent('public.unaccent', $1) $$;

-- Search tracks by title and users by display name: the same expression the queries use, or the index is not used.
CREATE INDEX idx_tracks_title_trgm ON tracks USING gin (f_unaccent(lower(title)) gin_trgm_ops);
CREATE INDEX idx_users_display_name_trgm ON users USING gin (f_unaccent(lower(display_name)) gin_trgm_ops);
```

| Chi tiết | Lý do |
|----------|-------|
| `f_unaccent` `IMMUTABLE` | Bắt buộc cho index trên biểu thức. Đánh dấu `IMMUTABLE` là **lời hứa** của bạn; nó đúng vì từ điển được ghim và ta không đổi `unaccent.rules`. (Đổi file rules sau này → phải `REINDEX`.) |
| `PARALLEL SAFE`, `STRICT` | Cho phép truy vấn song song; `NULL` vào → `NULL` ra (không gọi hàm). |
| GIN `gin_trgm_ops` | GIN lưu "trigram → danh sách dòng"; nhanh cho đọc, chậm hơn khi ghi. Hợp với tiêu đề ít sửa. (GiST ghi nhanh hơn nhưng đọc chậm hơn.) |
| Hai index riêng | Mỗi bảng một index; truy vấn track và user độc lập. |
| `lower` trước `f_unaccent` | Thứ tự không quan trọng với kết quả nhưng phải **giống hệt** trong index và truy vấn. |
| Collation | `lower()` phụ thuộc collation của database. Kiểm tra `SELECT datcollate FROM pg_database WHERE datname = current_database()`; nếu là `C`, `lower('Đ')` **không** đổi (xem mục 9). |

Flyway chạy migration trong transaction; `CREATE EXTENSION` và `CREATE FUNCTION` với `$$ … $$` chạy tốt. Trên H2 (nhóm test `test`) Flyway tắt nên migration này không chạy: **mọi test về tìm kiếm phải là `postgresTest`**.

## 6. Các bước code theo thứ tự

### Bước 1. Migration + test hạ tầng (RED trước)
`SearchMigrationPostgresTest`:
`f_unaccentRemovesTheVietnameseMarks` (`"Đặng Thị Đào"` → `"Dang Thi Dao"`, kể cả `ơ ư â ê ô ă`),
`f_unaccentGivesTheSameForTypedAndDecomposedLetters` (so `"Sơn"` NFC với `Normalizer.normalize("Sơn", NFD)`),
`f_unaccentIsImmutable` (`SELECT provolatile FROM pg_proc WHERE proname = 'f_unaccent'` = `'i'`),
`bothTrigramIndexesExist` (`pg_indexes`). Chạy `postgresTest` sau khi viết migration.

### Bước 2. Port và `SearchQuery`
```java
public interface SearchReader {
    /** Public READY tracks whose title is like {@code normalizedQuery}, best match first. */
    List<TrackItemResult> searchTracks(String normalizedQuery, UUID viewerId, int limit);
    List<UserHit> searchUsers(String normalizedQuery, UUID viewerId, int limit);
}
public record UserHit(String userId, String displayName, int followerCount, boolean isFollowedByMe) {}
```
`SearchQuery` (record + factory) làm phần kiểm tra:
```java
public record SearchQuery(String text, SearchType type, int limit) {
    public static SearchQuery of(String q, String type, Integer limit) {
        // TODO: trim; collapse runs of whitespace to one space; length (in code points) must be 2..100, else InvalidSearchException (400)
        // TODO: type null -> ALL ; "all"|"tracks"|"users" (any case) else 400 ; limit null -> 20, <1 -> 400, >50 -> 50
        throw new UnsupportedOperationException("TODO");
    }
}
```
Test trước (`SearchQueryTest`): `aOneCharacterQueryIsRejected`, `aQueryOfOneCharacterPaddedWithSpacesIsRejected`, `aQueryOf100CharactersIsAcceptedAnd101IsNot`, `spacesAreCollapsed`, `anUnknownTypeIsRejected`, `typeIsCaseInsensitive`, `limitDefaultsToTwentyAndIsCappedAtFifty`, `aLimitBelowOneIsRejected`.
Nhớ: **không** bỏ dấu ở Java; việc đó là của SQL (một nơi duy nhất, cùng hàm với index).

### Bước 3. SQL
```sql
-- Reads: tracks and audio_resources (track module), likes (engagement module).
WITH q AS (SELECT f_unaccent(lower(:q)) AS n)
SELECT t.id, t.owner_id, t.title, t.description, t.visibility, t.status, t.created_at,
       t.like_count, t.comment_count, ar.duration_ms,
       EXISTS (SELECT 1 FROM likes l WHERE l.user_id = :viewer AND l.track_id = t.id) AS liked_by_me,
       GREATEST(similarity(f_unaccent(lower(t.title)), q.n),
                word_similarity(q.n, f_unaccent(lower(t.title)))) AS score
FROM q, tracks t
JOIN audio_resources ar ON ar.track_id = t.id
WHERE t.visibility = 'PUBLIC' AND t.status = 'READY'
  AND (   f_unaccent(lower(t.title)) %  q.n
       OR q.n <% f_unaccent(lower(t.title))
       OR f_unaccent(lower(t.title)) LIKE '%' || :escaped || '%')
ORDER BY score DESC, t.created_at DESC, t.id DESC
LIMIT :limit
```
`:escaped` là `f_unaccent(lower(q))` **đã escape** `\`, `%`, `_` (thay `\` → `\\`, `%` → `\%`, `_` → `\_`); làm trong SQL (`replace(replace(replace(q.n, '\', '\\'), '%', '\%'), '_', '\_')`)
hoặc trong Java **sau** khi lấy dạng chuẩn hoá. Test `aPercentSignIsAnOrdinaryCharacter`: track `"100% hay"` và `"1000 hay"`; tìm `q=100%` chỉ ra track đầu.
Người xem chưa đăng nhập: `NOBODY = new UUID(0,0)` như guide 05. Bảng user tương tự: `f_unaccent(lower(u.display_name))`, `u.follower_count`, `EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = :viewer AND f.followee_id = u.id) AS followed_by_me`
(đọc `users`, `follows`).

Các điều kiện `% / <% / LIKE` đều dùng **chính biểu thức đã đặt chỉ mục** nên planner có thể `BitmapOr` ba lần quét GIN.

### Bước 4. Use case, controller, security
`SearchUseCase.execute(q, type, limit, viewerId)` gọi `SearchQuery.of`, rồi chỉ gọi reader của loại được hỏi (type `tracks` thì **không** truy vấn users). Mảng rỗng cho loại không hỏi.
`SearchController`: `@GetMapping("/api/v1/search")`, tham số `q` bắt buộc (thiếu → `400` mặc định của Spring, hãy kiểm tra có là `application/problem+json`).
`SecurityConfig`: `.requestMatchers(HttpMethod.GET, "/api/v1/search").permitAll()` + test.

### Bước 5. Dữ liệu thử tiếng Việt (bộ "oracle" của bạn)
Dùng trong `postgresTest` (một fixture cố định, đừng ngẫu nhiên):

| Loại | Giá trị |
|------|---------|
| Track (READY, PUBLIC) | `Nắng ấm xa dần`, `Sơn Tùng M-TP`, `Lạc trôi`, `Em của ngày hôm qua`, `Đen Vâu - Đi về nhà`, `Hà Anh Tuấn - Tháng Tư là lời nói dối của em` |
| Track không được thấy | `Nắng riêng tư` (PRIVATE), `Nắng đang xử lý` (PROCESSING) |
| User | `Sơn Tùng`, `Đen Vâu`, `Bích Phương`, `Hà Anh Tuấn`, `Minh Anh` |

| `q` | Kỳ vọng |
|-----|---------|
| `nang am`, `Nắng ấm`, `NANG AM` | track `Nắng ấm xa dần` đầu tiên; **không** có hai track `Nắng riêng tư`/`Nắng đang xử lý` |
| `son tung`, `Sơn Tùng`, `sơn tung` | user `Sơn Tùng` và track `Sơn Tùng M-TP` đứng đầu |
| `son` | vẫn ra `Sơn Tùng` (nhờ `<%`/`LIKE`; nếu chỉ dùng `%` có thể trượt!) |
| `den vau`, `đen`, `DEN` | user `Đen Vâu` và track `Đen Vâu - Đi về nhà` |
| `lac troi` | track `Lạc trôi` |
| `son tuhg` (gõ sai) | vẫn ra `Sơn Tùng` (similarity 0,375) |
| `anh` | `Hà Anh Tuấn`, `Minh Anh` (nhiều kết quả; kiểm tra thứ tự ổn định khi bằng điểm) |
| `zzzz` | rỗng |
| `%`, `_`, `\` | không lỗi, không khớp tất cả |

### Bước 6. Đo
Trong database tạm (như guide 05, bước 6) nạp 100 000 track tiêu đề ngẫu nhiên + vài tiêu đề tiếng Việt, `ANALYZE`, rồi:
```sql
EXPLAIN (ANALYZE, BUFFERS)
WITH q AS (SELECT f_unaccent(lower('nang am')) AS n)
SELECT ... FROM q, tracks t ... WHERE (... % ... OR ... <% ... OR ... LIKE ...) ORDER BY score DESC LIMIT 20;
```
Quan sát: `Bitmap Index Scan on idx_tracks_title_trgm` (có), so với khi `DROP INDEX` (quét tuần tự); thử `SET pg_trgm.similarity_threshold = 0.5;` thấy số dòng ứng viên thay đổi;
thử viết truy vấn với `unaccent(lower(title))` thay vì `f_unaccent(...)` để thấy index **không** được dùng.

### Bước 7. Commit
`feat: unaccent and trigram search migration`, `feat: search query validation`, `feat: search reader for tracks and users`, `feat: search endpoint`.

## 7. Trace-through cụ thể

**Truy vấn `q = "son tung"`; tiêu đề `"Sơn Tùng M-TP"`.**

1. Chuẩn hoá tiêu đề: `lower` → `sơn tùng m-tp`; `f_unaccent` → **`son tung m-tp`**. Từ khoá: `son tung` (đã không dấu).
2. `pg_trgm` coi mọi ký tự không phải chữ/số là dấu phân tách từ, nên `m-tp` thành hai từ `m` và `tp`. Trigram (đệm `"  "` trước, `" "` sau mỗi từ):

| Từ | Trigram |
|----|---------|
| `son` | `"  s"`, `" so"`, `son`, `on ` |
| `tung` | `"  t"`, `" tu"`, `tun`, `ung`, `ng ` |
| `m` | `"  m"`, `" m "` |
| `tp` | (`"  t"` đã có), `" tp"`, `tp ` |

Tiêu đề có **13** trigram khác nhau (PostgreSQL in ra bằng `show_trgm`: `{"  m","  s","  t"," m "," so"," tp"," tu","ng ","on ",son,"tp ",tun,ung}`).
Từ khoá có **9**: `"  s"`, `" so"`, `son`, `on `, `"  t"`, `" tu"`, `tun`, `ung`, `ng `. Cả 9 đều nằm trong tiêu đề.
3. `similarity = chung / hợp = 9 / (9 + 13 − 9) = 9/13 ≈ 0,692` ≥ 0,3 → `%` đúng. (Đo thật trên PostgreSQL 17: `0.6923077`.)
4. `LIKE '%son tung%'` trên `son tung m-tp` cũng đúng. `score = GREATEST(0,692; word_similarity = 1) = 1`.

**Tại sao từ khoá `son` (3 ký tự) cần `<%`:** 4 trigram chung / 13 = **0,3077**, chỉ hơn ngưỡng 0,3 một chút; một tiêu đề dài hơn chút (nhiều trigram hơn) sẽ làm `%` trượt. `word_similarity('son', 'son tung m-tp') = 1` vì `son` là một từ trọn vẹn trong tiêu đề.

**Lỗi gõ `son tuhg`:** trigram `tuhg` = `"  t"`, `" tu"`, `tuh`, `uhg`, `hg `. Chung với tiêu đề: `"  s"`, `" so"`, `son`, `on `, `"  t"`, `" tu"` = 6; hợp = 9 + 13 − 6 = 16 → `0,375` ≥ 0,3 → vẫn tìm ra, xếp thấp hơn kết quả gõ đúng.

## 8. Test cần viết

| Loại | Test | Ca biên |
|------|------|---------|
| Unit | `SearchQueryTest.*` (8 ca ở bước 2) | q, type, limit |
| Unit | `SearchUseCaseTest.onlyTheRequestedTypeIsSearched` | fake reader đếm lần gọi |
| postgres | `SearchMigrationPostgresTest.*` | bước 1 |
| | `SearchReaderJdbcPostgresTest.theSameResultWithOrWithoutMarksAndCase` | bảng bước 5 |
| | `...aShortWordInsideALongTitleIsFound` | `son`, bắt lỗi nếu chỉ dùng `%` |
| | `...aSmallTypoStillFindsTheName` | `son tuhg` |
| | `...aPrivateOrUnreadyTrackIsNeverFound` | quy tắc hiển thị |
| | `...percentAndUnderscoreAreOrdinaryCharacters` | escape |
| | `...exactMatchesRankAboveLooseOnes` | thứ tự theo điểm |
| | `...equalScoresAreOrderedNewestFirstAndStayStable` | tie-breaker |
| | `...theLimitIsApplied` | |
| | `...isFollowedByMeInUserHitsIsTrueOnlyForFollowedUsers` | |
| HTTP | `SearchOverHttpPostgresTest` — `400` (q quá ngắn/dài/thiếu, type lạ), `200` khách vãng lai, luồng tiếng Việt | |
| Security | `searchIsPublic` | |
| Perf (thủ công) | số liệu `EXPLAIN` trong PR | không là test tự động |

## 9. Lỗi thường gặp

| Lỗi | Dấu hiệu | Sửa |
|-----|----------|-----|
| `functions in index expression must be marked IMMUTABLE` | Migration lỗi | Dùng wrapper `f_unaccent`, không dùng `unaccent` trực tiếp. |
| Truy vấn không dùng index | `Seq Scan` trong `EXPLAIN` | Biểu thức trong `WHERE` khác biểu thức của index (ví dụ thiếu `lower`, hay dùng `unaccent` thay `f_unaccent`). Phải khớp từng ký tự. |
| Từ khoá ngắn không ra kết quả | `son` không thấy `Sơn Tùng M-TP` | Chỉ dùng `%`. Thêm `<%`/`LIKE` (mục 3, D3). |
| Database có collation `C` | `lower('Đ')` vẫn `Đ`, `đen` không ra `Đen Vâu` | Dùng collation `en_US.UTF-8`/`vi_VN.UTF-8` hoặc thêm `unaccent` trước `lower` (thứ tự này an toàn hơn vì `unaccent` đã đổi `Đ` → `D`). Có test `datcollate`. |
| `%`/`_` trong từ khoá ăn mọi thứ | `q=%` trả về tất cả | Escape cho `LIKE`. |
| Dùng `ILIKE` vì "đơn giản" | Chậm với dữ liệu lớn | Chỉ khi có GIN `gin_trgm_ops` mới nhanh; nhưng vẫn không bỏ dấu. |
| Quên `ANALYZE` sau nạp dữ liệu | Planner chọn `Seq Scan` dù có index | `ANALYZE`. |
| Index bị lệch sau khi đổi `unaccent.rules` | Kết quả sai âm thầm | `REINDEX` (đây là hậu quả của lời hứa `IMMUTABLE`). |
| Test xanh trên H2 mà chưa kiểm | Không chạy được SQL của Postgres | Chỉ `postgresTest`. |
| Tài khoản `Legacy` xuất hiện | `q=legacy` ra user lạ | Quyết định loại hay không (D5) và test. |
| Gõ tiếng Việt kiểu Telex đang dở (`Son Tungf`) | Không ra gì | Là hành vi bình thường; trigram chịu được lỗi nhỏ, không phải mọi lỗi. |

## 10. Kiểm tra thủ công

Tạo dữ liệu: đăng ký user `Sơn Tùng` (qua `register`), upload track tên `Nắng ấm xa dần` (đợi `READY`), thêm một track private tên `Nắng riêng tư`.

| # | Lệnh | Kỳ vọng |
|---|------|---------|
| 1 | `curl -s "$BASE/search?q=nang%20am"` | `tracks` có `Nắng ấm xa dần`; không có track private |
| 2 | `curl -s --get "$BASE/search" --data-urlencode "q=Sơn Tùng"` | user `Sơn Tùng` |
| 3 | `curl -s "$BASE/search?q=son%20tung&type=users"` | `tracks: []`, `users: [...]` |
| 4 | `curl -s "$BASE/search?q=son"` | vẫn ra `Sơn Tùng` |
| 5 | `curl -i "$BASE/search?q=a"` | `400` |
| 6 | `curl -i "$BASE/search"` | `400` |
| 7 | `curl -i "$BASE/search?q=abc&type=foo"` | `400` |
| 8 | `curl -s "$BASE/search?q=%25"` | không lỗi, `tracks`/`users` rỗng (hoặc chỉ cái chứa dấu `%` thật sự) |
| 9 | `curl -s "$BASE/search?q=nang&limit=1"` | tối đa 1 track |
| 10 | SQL: `EXPLAIN SELECT 1 FROM tracks WHERE f_unaccent(lower(title)) % 'nang'` | thấy `idx_tracks_title_trgm` (khi bảng đủ lớn) |

**Kịch bản UI** (tắt `FAKE_SEARCH`): gõ `son tung` vào ô tìm kiếm, đợi ~300 ms (debounce): có tab *Tất cả / Tracks / Users*, từ khoá được tô sáng trong kết quả kể cả khi gõ không dấu;
gõ chuỗi không có kết quả thấy trạng thái trống; xoá chữ thì quay về trang trước.

## 11. Câu hỏi tự kiểm tra

<details><summary>Hiện đáp án gợi ý sau khi tự trả lời</summary>

1. **Trigram là gì? Tính `similarity('son','son tung')` sơ bộ.** Chuỗi 3 ký tự liên tiếp của từ đã đệm; tỉ lệ trigram chung trên hợp. `son`: 4 trigram, `son tung`: 9, chung 4 → 4/9 ≈ 0,44.
2. **Vì sao cần `f_unaccent` mà không dùng `unaccent` trong index?** `unaccent` là `STABLE`; index trên biểu thức chỉ nhận `IMMUTABLE`.
3. **Đánh dấu hàm `IMMUTABLE` có nghĩa là hứa gì? Khi nào lời hứa bị phá?** Cùng đầu vào luôn cùng đầu ra; phá khi đổi từ điển/`unaccent.rules` → phải `REINDEX`.
4. **Vì sao `%` không đủ cho từ khoá ngắn?** Mẫu số là toàn bộ trigram của tiêu đề; từ ngắn trong tiêu đề dài có điểm thấp. `<%` (word similarity) hoặc `LIKE` bù lại.
5. **Vì sao truy vấn phải dùng đúng biểu thức của index?** Planner chỉ khớp index khi biểu thức giống hệt.
6. **GIN khác GiST thế nào?** GIN đọc nhanh/ghi chậm, GiST ngược lại; tiêu đề ít sửa → GIN.
7. **Vì sao không phân trang kết quả tìm kiếm ở v1.0?** Điểm xếp hạng không ổn định cho keyset, nhu cầu lật sâu thấp; giới hạn top-N đủ.
8. **Vì sao tìm kiếm phải kiểm bằng `postgresTest`?** `unaccent`, `pg_trgm`, GIN không có trên H2.

</details>

## 12. Bài tập mở rộng

1. **Tìm theo tên tác giả:** cho `GET /search` cũng khớp track mà *chủ track* có tên khớp (JOIN `users`). Quyết định trọng số: khớp tiêu đề quan trọng hơn khớp tên chủ?
2. **Phân trang bằng keyset theo `(score, id)`:** thử và ghi lại vì sao điểm thay đổi theo từ khoá gây khó, so với `OFFSET`. Hoặc: **gợi ý khi gõ** (prefix autocomplete) với `q%` + `text_pattern_ops`.
