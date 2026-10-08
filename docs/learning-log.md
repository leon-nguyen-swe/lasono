# Learning log

## 2026-10-06: Hai worker lấy trùng một job (`FOR UPDATE SKIP LOCKED`)

**Context**
Hàng đợi job xử lý audio nằm trong PostgreSQL. Nhiều worker chạy song song, và mỗi worker gọi `claimNext` để lấy một job `PENDING`, đổi sang `RUNNING`.

**Symptom**
Test lấy job bằng một luồng thì xanh. Test mới (8 luồng cùng lấy 100 job) lỗi `Found duplicate(s)`: nhiều job bị lấy hai lần, `attempts = 2`. Lỗi xảy ra ổn định ở cả 2 lần chạy đầu.

**How it works (step by step)**
1. Câu SQL cũ có dạng `UPDATE ... WHERE id = (SELECT id ... LIMIT 1)`. Phần `SELECT` chạy trước.
2. Hai worker chạy gần như cùng lúc, cùng thấy job X là `PENDING` và cùng chọn id X.
3. Worker 1 cập nhật dòng X, nên giữ khóa dòng. Worker 2 phải chờ.
4. Worker 1 commit. Worker 2 chạy tiếp với id X đã chọn từ bước 2 (không chọn lại), thấy dòng X vẫn khớp `id = X`, nên cập nhật X lần nữa.
5. Với `FOR UPDATE SKIP LOCKED` ở phần `SELECT`: dòng được chọn bị khóa ngay lúc chọn. Worker khác gặp dòng bị khóa thì bỏ qua và chọn dòng kế tiếp, nên không bao giờ chọn trùng.

**Fix**
Thêm `FOR UPDATE SKIP LOCKED` vào phần `SELECT` của câu lấy job.

**Takeaway**

**Open question**

## 2026-10-07: Khóa ngoại lỗi khi `JdbcTemplate` ghi trong transaction chung với Hibernate

**Context**
Upload tạo track (qua JPA/Hibernate) rồi xếp một job (qua `JdbcTemplate`, SQL thẳng). Ta bọc cả hai trong một `@Transactional` để chúng cùng thành công hoặc cùng bị hoàn tác.

**Symptom**
Unit test (dùng fake) và test rollback đều xanh. Test chạy upload thành công trên PostgreSQL thật lỗi: `violates foreign key constraint "fk_processing_jobs_track"`, `Key (track_id)=(...) is not present in table "tracks"`.

**How it works (step by step)**
1. `@Transactional` mở một transaction, và Hibernate với `JdbcTemplate` dùng chung một kết nối DB.
2. `save(track)` của Hibernate chỉ đưa entity vào bộ nhớ của nó (persistence context). Câu `INSERT INTO tracks` được **hoãn** tới lúc flush (thường là lúc commit).
3. `JdbcTemplate` gửi `INSERT INTO processing_jobs` thẳng tới DB. Hibernate không biết có lệnh này nên không flush trước.
4. DB kiểm tra khóa ngoại ngay khi chạy câu lệnh: dòng `tracks` chưa tồn tại nên bị từ chối.
5. Trước khi có `@Transactional`, mỗi `save` tự commit riêng nên dòng `tracks` đã có sẵn. Vì vậy lỗi chỉ lộ ra sau khi thêm transaction.

**Fix**
Dùng `saveAndFlush` trong adapter của track, để dòng được ghi xuống DB trước khi `save()` trả về.

**Takeaway**

**Open question**


## 2026-10-07: Worker chậm ghi đè kết quả của worker đã nhận job thay nó

**Context**
Job có "lease" (`locked_until`). Nếu worker chạy quá lâu hoặc chết, lease hết hạn và worker khác được claim lại job đó (`attempts` tăng thêm 1). Worker cũ có thể vẫn đang chạy, rồi gọi `complete` hoặc `fail` sau khi worker mới đã nhận job.

**Symptom**
Chưa thấy trên máy thật; test mô phỏng bằng tay lộ ra: `complete` và `fail` cũ chỉ cập nhật theo `id`, nên worker chậm (lượt 1) đổi job của worker mới (lượt 2) sang `DONE`, hoặc đưa nó về `PENDING` kèm lỗi cũ.

**How it works (step by step)**
1. Worker A claim job: `status = RUNNING`, `attempts = 1`, lease 10 phút. A cầm bản `ProcessingJob` có `attempts = 1`.
2. A chạy quá 10 phút. Lease hết hạn nhưng job vẫn `RUNNING`.
3. Worker B claim: điều kiện `RUNNING AND locked_until <= now() AND attempts < max_attempts` đúng, nên `attempts = 2` và lease mới.
4. A xong và gọi `complete`. Câu lệnh `WHERE id = ?` khớp dòng của B, nên ghi đè.
5. Với `WHERE id = ? AND status = 'RUNNING' AND attempts = ?`: A cầm `attempts = 1` còn dòng là `2`, không khớp dòng nào, nên không đổi gì. `fail` thấy "0 dòng" và trả `LEASE_LOST`, để use case không đánh dấu track `FAILED` nhầm.
6. Nếu lease đã hết nhưng chưa ai claim lại, `attempts` vẫn khớp và A vẫn được `complete` (việc đã xong thì giữ).

**Fix**
`complete` và `fail` nhận cả `ProcessingJob` đã claim và dùng `attempts` làm "token" trong điều kiện `WHERE`.

**Takeaway**

**Open question**


## 2026-10-08: Thu hồi refresh token bị hoàn tác vì exception (`noRollbackFor`)

**Context**
Refresh token được xoay vòng và chia theo "family". Nếu một token đã dùng rồi mà bị đưa ra lần nữa (dấu hiệu bị đánh cắp), use case thu hồi cả family rồi ném `InvalidRefreshTokenException` để controller trả `401`. Cả hàm nằm trong một `@Transactional`.

**Symptom**
Người gọi nhận đúng `401`, nhưng trong DB các token của family vẫn chưa bị thu hồi, nên token mới mà kẻ trộm vừa nhận vẫn dùng được. Test "dùng lại token cũ thì cả family bị thu hồi" chạy trên PostgreSQL thật sẽ đỏ nếu bỏ `noRollbackFor`.

**How it works (step by step)**
1. Spring bọc method có `@Transactional` bằng một proxy: mở transaction trước khi gọi, commit hoặc rollback sau khi method kết thúc.
2. `revokeFamily` chạy `UPDATE` trong cùng transaction đó. Thay đổi này chỉ tồn tại trong transaction, chưa ai khác thấy.
3. Method ném `InvalidRefreshTokenException`. Mặc định proxy rollback với mọi `RuntimeException`, nên `UPDATE` ở bước 2 bị hủy.
4. Exception vẫn lan ra controller và thành `401`, nên nhìn từ ngoài mọi thứ đều "đúng".
5. Với `noRollbackFor = InvalidRefreshTokenException.class`, proxy commit dù có exception này, nên việc thu hồi được giữ lại và người gọi vẫn thấy `401`.
6. Đánh đổi: mọi thay đổi khác đã làm trước khi ném exception cũng được commit. Ở đây chỉ có việc thu hồi, nên an toàn.

**Fix**
`@Transactional(noRollbackFor = InvalidRefreshTokenException.class)` trên `RefreshSessionUseCase.execute`. Một mutation (bỏ `noRollbackFor`) làm test trên PostgreSQL thật đỏ, nên test này thật sự bảo vệ chỗ đó.

**Takeaway**

**Open question**


## 2026-10-08: Token hết hạn làm hỏng cả route công khai

**Context**
`GET /api/v1/tracks` là route công khai (`permitAll`). Khi đã đăng nhập, app gửi kèm `Authorization: Bearer <token>` (để người dùng thấy cả track riêng tư của mình). Access token sống 15 phút.

**Symptom**
Sau 15 phút, danh sách track trả `401` dù ai cũng được xem. Một lần đăng nhập gửi kèm token cũ cũng bị `401`, trong khi `/auth/login` không cần token.

**How it works (step by step)**
1. Bộ lọc xác thực bearer của Spring Security chạy **trước** bước kiểm tra quyền (`permitAll` nằm ở bước sau).
2. Nếu request không có header `Authorization`, bộ lọc bỏ qua, request là "ẩn danh", và `permitAll` cho qua.
3. Nếu có header, bộ lọc xác thực token ngay. Token sai hoặc hết hạn thì bộ lọc trả `401` luôn và không bao giờ tới bước `permitAll`.
4. Vì vậy "route công khai" chỉ có nghĩa là không cần token, không có nghĩa là một token hỏng được bỏ qua.

**Fix**
Backend: với `/api/v1/auth/**` bearer resolver trả `null`, tức là bỏ qua header (đăng nhập với token cũ vẫn chạy). App: khi gặp `401` thì làm mới token một lần rồi gửi lại một lần; riêng đọc hồ sơ công khai thì không gửi token.

**Takeaway**

**Open question**
