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
