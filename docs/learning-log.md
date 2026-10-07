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
