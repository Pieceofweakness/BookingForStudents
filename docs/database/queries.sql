-- ============================================================
-- BookingForStudents — SQL-запросы для основных операций
-- СУБД: PostgreSQL 16+
-- Использование: backend выполняет эти запросы напрямую (psycopg)
-- ============================================================

--# 1. ПОЛЬЗОВАТЕЛИ (USERS)

-- 1.1 Получить пользователя по email (для логина)
SELECT id, email, password_hash, full_name, role, is_active
FROM users
WHERE email = $1;

-- 1.2 Создать нового пользователя
INSERT INTO users (email, password_hash, full_name, role)
VALUES ($1, $2, $3, $4)
RETURNING id, email, full_name, role, created_at;

-- 1.3 Получить профиль пользователя по id
SELECT id, email, full_name, role, created_at, is_active
FROM users
WHERE id = $1;

-- # 2. СЛОТЫ (SLOTS)

-- 2.1 Получить все опубликованные слоты (свободные и занятые)
SELECT
    s.id,
    s.title,
    s.description,
    s.starts_at,
    s.ends_at,
    s.location,
    s.format,
    s.online_url,
    s.capacity,
    u.full_name AS teacher_name,
    COUNT(b.id) FILTER (WHERE b.status = 'active') AS booked_count,
    s.capacity - COUNT(b.id) FILTER (WHERE b.status = 'active') AS free_seats
FROM slots s
JOIN users u ON u.id = s.teacher_id
LEFT JOIN bookings b ON b.slot_id = s.id
WHERE s.status = 'published'
  AND s.starts_at > NOW()
GROUP BY s.id, u.full_name
ORDER BY s.starts_at ASC;

-- 2.2 Получить слот по id (с деталями)
SELECT
    s.*,
    u.full_name AS teacher_name,
    u.email AS teacher_email,
    COUNT(b.id) FILTER (WHERE b.status = 'active') AS booked_count,
    s.capacity - COUNT(b.id) FILTER (WHERE b.status = 'active') AS free_seats
FROM slots s
JOIN users u ON u.id = s.teacher_id
LEFT JOIN bookings b ON b.slot_id = s.id
WHERE s.id = $1
GROUP BY s.id, u.full_name, u.email;

-- 2.3 Создать слот (преподаватель)
INSERT INTO slots (
    teacher_id, title, description, starts_at, ends_at,
    location, format, online_url, capacity, status
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'published')
RETURNING id, title, starts_at, capacity, status;

-- 2.4 Обновить слот
UPDATE slots
SET title = $2,
    description = $3,
    starts_at = $4,
    ends_at = $5,
    location = $6,
    format = $7,
    online_url = $8,
    capacity = $9,
    updated_at = NOW()
WHERE id = $1
RETURNING id, title, starts_at;

-- 2.5 Отменить слот
UPDATE slots
SET status = 'cancelled', updated_at = NOW()
WHERE id = $1
RETURNING id, status;

-- # 3. ЗАПИСИ (BOOKINGS)

-- 3.1 Записать студента на слот
-- (проверка свободных мест и дублей — на уровне приложения или триггера)
INSERT INTO bookings (slot_id, student_id, status)
VALUES ($1, $2, 'active')
RETURNING id, slot_id, student_id, created_at;

-- 3.2 Получить всех студентов, записавшихся на слот
SELECT
    b.id AS booking_id,
    b.created_at AS booked_at,
    u.id AS student_id,
    u.full_name,
    u.email
FROM bookings b
JOIN users u ON u.id = b.student_id
WHERE b.slot_id = $1
  AND b.status = 'active'
ORDER BY b.created_at ASC;

-- 3.3 Получить все записи конкретного студента
SELECT
    b.id AS booking_id,
    b.status,
    b.created_at AS booked_at,
    s.id AS slot_id,
    s.title,
    s.starts_at,
    s.ends_at,
    s.location,
    s.format,
    u.full_name AS teacher_name
FROM bookings b
JOIN slots s ON s.id = b.slot_id
JOIN users u ON u.id = s.teacher_id
WHERE b.student_id = $1
ORDER BY s.starts_at DESC;

-- 3.4 Отменить запись
UPDATE bookings
SET status = 'cancelled',
    cancelled_at = NOW(),
    cancel_reason = $3
WHERE id = $1 AND student_id = $2
RETURNING id, status, cancelled_at;

-- 3.5 Проверить, не записан ли студент уже на этот слот
SELECT id, status
FROM bookings
WHERE slot_id = $1 AND student_id = $2 AND status = 'active';

-- 3.6 Посчитать количество активных записей на слот
SELECT COUNT(*) AS active_count
FROM bookings
WHERE slot_id = $1 AND status = 'active';

-- # 4. ЛИСТ ОЖИДАНИЯ (WAITLIST)

-- 4.1 Добавить студента в лист ожидания (в конец очереди)
INSERT INTO waitlist (slot_id, student_id, position, status)
VALUES (
    $1,
    $2,
    (SELECT COALESCE(MAX(position), 0) + 1 FROM waitlist WHERE slot_id = $1),
    'waiting'
)
RETURNING id, slot_id, student_id, position;

-- 4.2 Получить лист ожидания для слота
SELECT
    w.id,
    w.position,
    w.created_at,
    w.status,
    u.id AS student_id,
    u.full_name,
    u.email
FROM waitlist w
JOIN users u ON u.id = w.student_id
WHERE w.slot_id = $1
ORDER BY w.position ASC;

-- 4.3 Взять первого из очереди (при освобождении места)
SELECT id, student_id, position
FROM waitlist
WHERE slot_id = $1 AND status = 'waiting'
ORDER BY position ASC
LIMIT 1
FOR UPDATE;  -- блокировка строки для безопасной обработки

-- 4.4 Перевести из листа ожидания в запись (в транзакции)
-- Шаг 1: создать booking
INSERT INTO bookings (slot_id, student_id, status)
SELECT slot_id, student_id, 'active'
FROM waitlist
WHERE id = $1
RETURNING id, slot_id, student_id;

-- Шаг 2: обновить статус в waitlist
UPDATE waitlist
SET status = 'converted', notified_at = NOW()
WHERE id = $1;

-- 4.5 Позиция студента в очереди
SELECT position
FROM waitlist
WHERE slot_id = $1 AND student_id = $2 AND status = 'waiting';


-- # 5. УВЕДОМЛЕНИЯ (NOTIFICATIONS)
 
-- 5.1 Записать уведомление в историю (перед отправкой)
INSERT INTO notifications (user_id, booking_id, type, status)
VALUES ($1, $2, $3, 'pending')
RETURNING id;

-- 5.2 Отметить уведомление как отправленное
UPDATE notifications
SET status = 'sent', sent_at = NOW()
WHERE id = $1;

-- 5.3 Отметить уведомление как провалившееся
UPDATE notifications
SET status = 'failed', error_message = $2
WHERE id = $1;

-- 5.4 Получить все уведомления пользователя
SELECT id, type, status, sent_at, error_message
FROM notifications
WHERE user_id = $1
ORDER BY sent_at DESC NULLS LAST;


-- # 6. СЛОЖНЫЕ / АНАЛИТИЧЕСКИЕ ЗАПРОСЫ 

-- 6.1 Топ-5 популярных слотов (по числу записей)
SELECT
    s.id,
    s.title,
    s.starts_at,
    COUNT(b.id) AS booked_count,
    s.capacity
FROM slots s
LEFT JOIN bookings b ON b.slot_id = s.id AND b.status = 'active'
WHERE s.status = 'published'
GROUP BY s.id
ORDER BY booked_count DESC
LIMIT 5;

-- 6.2 Расписание преподавателя (его слоты с числом записей)
SELECT
    s.id,
    s.title,
    s.starts_at,
    s.ends_at,
    s.status,
    COUNT(b.id) FILTER (WHERE b.status = 'active') AS booked,
    s.capacity
FROM slots s
LEFT JOIN bookings b ON b.slot_id = s.id
WHERE s.teacher_id = $1
GROUP BY s.id
ORDER BY s.starts_at DESC;

-- 6.3 Проверка пересечения слотов по времени и месту
-- (для валидации при создании слота)
SELECT id, title, starts_at, ends_at, location
FROM slots
WHERE teacher_id = $1
  AND status IN ('draft', 'published')
  AND id != COALESCE($2, -1)             -- исключить текущий слот при редактировании
  AND (
      (starts_at, ends_at) OVERLAPS ($3::timestamptz, $4::timestamptz)
  )
  AND location IS NOT DISTINCT FROM $5;

-- 6.4 Статистика по слотам для администратора
SELECT
    status,
    COUNT(*) AS count
FROM slots
GROUP BY status;