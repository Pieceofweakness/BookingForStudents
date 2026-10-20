-- ============================================================
-- BookingForStudents — инициализация базы данных
-- СУБД: PostgreSQL 16+
-- Соответствует ER-диаграмме (docs/data/er_diagram.puml), 3НФ
-- ============================================================

-- 1. ENUM-типы
CREATE TYPE user_role AS ENUM ('student', 'teacher', 'admin');
CREATE TYPE slot_format AS ENUM ('offline', 'online', 'hybrid');
CREATE TYPE slot_status AS ENUM ('draft', 'published', 'cancelled', 'completed');
CREATE TYPE booking_status AS ENUM ('active', 'cancelled', 'attended');
CREATE TYPE waitlist_status AS ENUM ('waiting', 'notified', 'converted', 'expired');
CREATE TYPE notification_type AS ENUM (
    'booking_confirmed',
    'booking_cancelled',
    'reminder',
    'waitlist_promoted'
);
CREATE TYPE notification_status AS ENUM ('pending', 'sent', 'failed');

-- 2. Пользователи
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role user_role NOT NULL DEFAULT 'student',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- 3. Слоты мероприятий
CREATE TABLE slots (
    id BIGSERIAL PRIMARY KEY,
    teacher_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    location VARCHAR(255),
    format slot_format NOT NULL DEFAULT 'offline',
    online_url VARCHAR(500),
    capacity INTEGER NOT NULL CHECK (capacity > 0),
    is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
    recurrence_rule VARCHAR(255),
    status slot_status NOT NULL DEFAULT 'draft',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_slot_time CHECK (ends_at > starts_at)
);

-- 4. Записи
CREATE TABLE bookings (
    id BIGSERIAL PRIMARY KEY,
    slot_id BIGINT NOT NULL REFERENCES slots(id) ON DELETE CASCADE,
    student_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status booking_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cancelled_at TIMESTAMPTZ,
    cancel_reason VARCHAR(500),
    CONSTRAINT uq_student_slot UNIQUE (slot_id, student_id)
);

-- 5. Лист ожидания
CREATE TABLE waitlist (
    id BIGSERIAL PRIMARY KEY,
    slot_id BIGINT NOT NULL REFERENCES slots(id) ON DELETE CASCADE,
    student_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notified_at TIMESTAMPTZ,
    status waitlist_status NOT NULL DEFAULT 'waiting',
    CONSTRAINT uq_waitlist_student_slot UNIQUE (slot_id, student_id)
);

-- 6. История уведомлений
CREATE TABLE notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    booking_id BIGINT REFERENCES bookings(id) ON DELETE SET NULL,
    type notification_type NOT NULL,
    sent_at TIMESTAMPTZ,
    status notification_status NOT NULL DEFAULT 'pending',
    error_message TEXT
);

-- 7. Индексы для производительности
CREATE INDEX idx_slots_teacher ON slots(teacher_id);
CREATE INDEX idx_slots_starts_at ON slots(starts_at);
CREATE INDEX idx_slots_status ON slots(status);
CREATE INDEX idx_bookings_student ON bookings(student_id);
CREATE INDEX idx_bookings_slot ON bookings(slot_id);
CREATE INDEX idx_waitlist_slot ON waitlist(slot_id);
CREATE INDEX idx_notifications_user ON notifications(user_id);