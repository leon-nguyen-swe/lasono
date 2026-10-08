# Thuật ngữ

> Ngắn gọn, kèm ví dụ trong LaSono. Theo thứ tự chữ cái. `→` chỉ thuật ngữ liên quan.

**ACID.** Bốn bảo đảm của một transaction: *Atomicity* (làm hết hoặc không làm gì), *Consistency* (ràng buộc luôn đúng), *Isolation* (các transaction đồng thời không thấy dở dang của nhau), *Durability* (đã commit thì không mất).
Ví dụ: like và `like_count` nằm trong một transaction nên cùng commit hoặc cùng rollback.

**Anti-corruption layer (ACL).** Lớp dịch giữa hai mô hình để mô hình ngoài không "làm hỏng" mô hình của mình. Ví dụ: `TrackLookupAdapter` của `engagement` gọi use case của `track` và dịch kết quả sang `TrackFacts`, nên `engagement` không bao giờ biết `GetTrackResult`.

**At-least-once.** Một thông điệp được giao *ít nhất một lần* (có thể lặp), nên bên nhận phải idempotent. Outbox thường cho bảo đảm này. → *idempotency*, *outbox*

**Atomic (nguyên tử).** Không thể bị chia nhỏ ở mức quan sát: `UPDATE t SET n = n + 1` là một bước nguyên tử, còn "đọc n, cộng 1 trong Java, ghi lại" là ba bước có khoảng hở. → *lost update*

**Bitmap scan.** Cách PostgreSQL dùng một hoặc nhiều index để đánh dấu các trang đĩa cần đọc, rồi đọc chúng một lượt. `BitmapOr` kết hợp nhiều index (guide 06).

**Cardinality (lực lượng).** Số giá trị khác nhau của một cột (hoặc số dòng một bước trả về). Planner dùng để chọn kế hoạch; `ANALYZE` cập nhật thống kê.

**CHECK constraint.** Ràng buộc DB kiểm điều kiện cho từng dòng: `CHECK (like_count >= 0)`. Lưới an toàn cuối cùng sau domain và use case.

**Connection pool.** Nhóm kết nối DB dùng lại (HikariCP trong Spring Boot). Hết kết nối thì request phải chờ. Chỉ số `hikaricp_connections_active` cho thấy mức dùng.

**Counter phi chuẩn hoá (denormalized counter).** Số lưu sẵn thay vì đếm mỗi lần đọc: `tracks.like_count`. Đọc nhanh, đổi lại phải giữ nó đúng khi ghi (cập nhật nguyên tử, cùng transaction) và có thể đối soát. → *reconciliation*

**CQRS (Command Query Responsibility Segregation).** Tách mô hình *ghi* (lệnh, giữ bất biến) và mô hình *đọc* (truy vấn tối ưu cho màn hình). Module `discovery` là một read model "nhẹ".

**Deadlock.** Hai transaction mỗi bên giữ khoá mà bên kia cần, nên chờ nhau mãi. PostgreSQL phát hiện sau ~1 giây và huỷ một bên (lỗi SQLSTATE `40P01`). Tránh bằng thứ tự lấy khoá cố định. Ví dụ: A follow B và B follow A cùng lúc (guide 03).

**Dependency inversion (đảo phụ thuộc).** Module cấp cao định nghĩa interface (port), module cấp thấp cài nó, nên phụ thuộc lúc biên dịch chỉ đi một chiều. Ví dụ: `track` định nghĩa `ViewerLikesReader`, `engagement` cài nó.

**Domain event.** Một sự thật đã xảy ra trong domain, viết ở thì quá khứ: `TrackLiked`. Người phát không biết ai nghe. → *shared kernel*, *outbox*

**Eventual consistency (nhất quán cuối cùng).** Dữ liệu ở nhiều nơi sẽ khớp nhau *sau một lúc*, không phải ngay. Trái với ACID trong một transaction. LaSono tránh nó cho bộ đếm bằng sự kiện đồng bộ cùng transaction.

**EXPLAIN / EXPLAIN ANALYZE.** Lệnh cho xem kế hoạch truy vấn của PostgreSQL (`ANALYZE`: chạy thật và đo). Đọc: loại quét (`Seq Scan`, `Index Scan`, `Bitmap Index Scan`), `actual time`, `rows`, `Rows Removed by Filter`, `Sort Method` (guide 05).

**Fan-out on read.** Tính kết quả *khi đọc* (JOIN follows với tracks). Đơn giản, luôn đúng, đọc tốn hơn. Ví dụ: feed của LaSono v1.0.

**Fan-out on write.** Chép kết quả *khi ghi* cho từng người nhận (một dòng `feed_items` mỗi follower). Đọc rẻ, ghi đắt, phức tạp khi unfollow/xoá ("celebrity problem": một người có triệu follower).

**GIN (Generalized Inverted Index).** Loại index lưu "phần tử → danh sách dòng chứa nó"; dùng cho mảng, JSON, và trigram (`gin_trgm_ops`). Đọc nhanh, ghi chậm hơn B-tree.

**Idempotency (tính lặp được).** Gọi 1 hay nhiều lần cho trạng thái cuối giống nhau. `PUT /like` lần 2 vẫn `200`, bộ đếm không đổi. Không có nghĩa "không báo lỗi". Cách làm: `INSERT … ON CONFLICT DO NOTHING` + chỉ phát sự kiện khi thật sự đổi.

**IDOR (Insecure Direct Object Reference).** Lỗ hổng: truy cập đối tượng bằng id mà không kiểm tra nó thuộc phạm vi/quyền của người gọi. Ví dụ: xoá comment của track khác bằng cách ghép sai `trackId` (guide 04).

**Immutable / Stable / Volatile (hàm PostgreSQL).** `IMMUTABLE`: cùng đầu vào luôn cùng đầu ra mãi mãi (được dùng trong index). `STABLE`: không đổi trong một câu lệnh (`unaccent`). `VOLATILE`: có thể đổi bất cứ lúc nào (`random()`).

**Index (chỉ mục).** Cấu trúc phụ giúp tìm dòng nhanh, đổi lại ghi chậm hơn và tốn chỗ. Biến thể: *nhiều cột* (thứ tự cột quan trọng), *một phần* (`WHERE …`), *trên biểu thức* (`f_unaccent(lower(title))`). Tạo khi có số đo chứng minh.

**Isolation level (mức cô lập).** Mức độ transaction đồng thời nhìn thấy nhau. PostgreSQL mặc định `READ COMMITTED`: mỗi câu lệnh thấy dữ liệu đã commit tại lúc nó bắt đầu. Mức cao hơn: `REPEATABLE READ`, `SERIALIZABLE`.

**Keyset pagination (phân trang theo khoá).** Trang sau bắt đầu "sau giá trị của dòng cuối trang trước": `WHERE (created_at, id) < (:c, :id) ORDER BY created_at DESC, id DESC LIMIT n`. Không trùng/sót khi có dữ liệu mới, và nhanh với index. Trái với *offset pagination*. Cần *tie-breaker* (khoá phụ).

**Lost update (cập nhật bị mất).** Hai người đọc cùng giá trị cũ rồi cùng ghi giá trị mới tính từ nó; một thay đổi biến mất. Ví dụ: hai like đồng thời, `like_count` chỉ +1. Cách tránh: cập nhật nguyên tử trong SQL (`n = n + 1`), khoá hàng, hoặc khoá lạc quan (version).

**Modular monolith.** Một ứng dụng triển khai một khối, nhưng chia thành module có ranh giới rõ (LaSono: `track`, `identity`, `engagement`, `discovery`). Ranh giới được ArchUnit bảo vệ.

**MVCC (Multi-Version Concurrency Control).** PostgreSQL giữ nhiều phiên bản của dòng để người đọc không chặn người ghi. Là lý do `READ COMMITTED` thấy "phiên bản đã commit mới nhất".

**N+1.** Một truy vấn lấy N dòng rồi N truy vấn nữa cho từng dòng. Cách sửa: một truy vấn `IN (...)` cho cả trang (`likedAmong`, `findDurationsByTrackIds`).

**Offset pagination.** `LIMIT n OFFSET k`. Dễ nhưng trùng/sót khi dữ liệu thay đổi và chậm khi `k` lớn. → *keyset*

**ON CONFLICT (upsert).** `INSERT … ON CONFLICT (cột) DO NOTHING | DO UPDATE`. Cho phép "chèn nếu chưa có" trong một câu, không race. Số dòng bị ảnh hưởng cho biết có thật sự chèn hay không.

**Outbox.** Bảng ghi sự kiện *trong cùng transaction* với dữ liệu; một tiến trình riêng đọc và gửi đi. Giải quyết "dual write" (ghi DB và gửi hệ thống ngoài không thể cùng nguyên tử). Giải thích ở guide 01, chưa làm ở v1.0. Hàng đợi `processing_jobs` của Phase 3 là họ hàng gần.

**Partial index.** Index chỉ chứa các dòng thoả điều kiện: `… WHERE visibility = 'PUBLIC' AND status = 'READY'`. Nhỏ hơn, nhanh hơn cho truy vấn khớp đúng điều kiện đó.

**Port & adapter (hexagonal).** *Port* là interface do lõi (Application/Domain) định nghĩa; *adapter* là cài đặt ở rìa (JDBC, HTTP, ffmpeg). Lõi không biết công nghệ.

**Race condition.** Kết quả phụ thuộc thứ tự thời gian của các luồng đồng thời. Ví dụ: "kiểm tra đã like chưa rồi chèn" bị hai request chen vào giữa. Cách chặn: ràng buộc DB + `ON CONFLICT`, khoá hàng.

**Read model.** Mô hình dữ liệu tối ưu cho việc đọc một màn hình, có thể JOIN nhiều bảng, không chứa quy tắc nghiệp vụ. → *CQRS*

**Reconciliation (đối soát).** So sánh số lưu sẵn với số tính lại (`like_count` với `COUNT(*)`) và sửa nếu lệch; thường là job định kỳ.

**Row lock (khoá hàng).** Khoá một dòng đến hết transaction: `SELECT … FOR UPDATE`, hoặc ngầm khi `UPDATE`. Người sau phải chờ. `SKIP LOCKED` bỏ qua dòng đang khoá (hàng đợi job Phase 3).

**Rule of three.** Chỉ trừu tượng hoá khi thấy lặp lần thứ ba (cursor ở track, engagement, discovery → `shared.paging`).

**Shared kernel.** Phần mô hình dùng chung mà nhiều module cùng chấp nhận phụ thuộc và cùng giữ nhỏ. Ở LaSono: `com.lasono.shared.event`.

**Similarity / word_similarity (pg_trgm).** `similarity(a,b)` = trigram chung / trigram hợp, trong [0,1]. `word_similarity(q, text)` so `q` với phần giống nhất của `text`, hợp với từ khoá ngắn trong tiêu đề dài. Ngưỡng toán tử `%` là `pg_trgm.similarity_threshold` (mặc định 0,3).

**SQLSTATE.** Mã lỗi 5 ký tự chuẩn của SQL: `23505` vi phạm unique, `23514` vi phạm CHECK, `40P01` deadlock.

**Tie-breaker (khoá phụ).** Cột thêm vào `ORDER BY` để thứ tự là xác định khi cột chính trùng. Ví dụ: `id` sau `created_at`/`position_ms`.

**Transaction.** Nhóm thao tác DB coi như một khối (ACID). Trong Spring: `@Transactional` (qua proxy: gọi từ cùng class thì không có tác dụng).

**Trigram.** Chuỗi 3 ký tự liên tiếp của một từ đã đệm hai dấu cách đầu và một dấu cách cuối: `son` → `"  s"`, `" so"`, `son`, `on `. Nền tảng của `pg_trgm` (guide 06).

**Unaccent.** Extension PostgreSQL bỏ dấu (`Đặng` → `Dang`). `STABLE`, nên cần wrapper `IMMUTABLE` để dùng trong index.

**Unique constraint.** Ràng buộc không cho hai dòng trùng giá trị (hoặc bộ giá trị). Tên ràng buộc (`uq_users_email`) giúp code nhận ra lỗi nào đã xảy ra.

**Write skew / phantom.** Các hiện tượng của mức cô lập thấp khi hai transaction đọc một tập rồi ghi dựa trên nó. Không gặp ở Phase 5-6 nếu bạn dùng ràng buộc DB; nhắc đến để biết vì sao `SERIALIZABLE` tồn tại.
