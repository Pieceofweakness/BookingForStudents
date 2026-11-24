import psycopg2
import pytest


@pytest.fixture
def db():
    conn = psycopg2.connect(
        host="localhost",
        database="BookingForStudents",
        user="postgres",
        password="1234",
    )
    yield conn
    # Откатываем изменения после каждого теста, чтобы база оставалась чистой
    conn.rollback()
    conn.close()


def test_create_booking(db):
    """Позитивный тест: создание записи."""
    with db.cursor() as cur:
        # 1. Создаем преподавателя (обязательно указываем ID, чтобы потом к нему обратиться)
        cur.execute(
            """
            INSERT INTO users (id, email, password_hash, full_name, role)
            VALUES (10, 'teacher@test.com', 'hash', 'Преподаватель', 'teacher')
        """
        )

        # 2. Создаем студента
        cur.execute(
            """
            INSERT INTO users (id, email, password_hash, full_name, role)
            VALUES (20, 'student@test.com', 'hash', 'Студент', 'student')
        """
        )

        # 3. Создаем слот, привязывая его к созданному преподавателю (id=10)
        cur.execute(
            """
            INSERT INTO slots (id, teacher_id, title, starts_at, ends_at, capacity, status)
            VALUES (100, 10, 'Test Slot', '2026-12-01 10:00', '2026-12-01 11:00', 2, 'published')
        """
        )

        # 4. Теперь можем создать запись, привязывая её к слоту (100) и студенту (20)
        cur.execute(
            """
            INSERT INTO bookings (slot_id, student_id, status)
            VALUES (100, 20, 'active')
            RETURNING id
        """
        )
        booking = cur.fetchone()

        assert booking is not None
        assert booking[0] > 0


def test_duplicate_booking_fails(db):
    """Негативный тест: дублирующая запись должна вызвать ошибку."""
    with db.cursor() as cur:
        # Создаем те же сущности, что и в первом тесте
        cur.execute(
            "INSERT INTO users (id, email, password_hash, full_name, role) VALUES (10, 't@t.com', 'h', 'T', 'teacher')"
        )
        cur.execute(
            "INSERT INTO users (id, email, password_hash, full_name, role) VALUES (20, 's@s.com', 'h', 'S', 'student')"
        )
        cur.execute(
            "INSERT INTO slots (id, teacher_id, title, starts_at, ends_at, capacity, status) VALUES (100, 10, 'Slot', '2026-12-01 10:00', '2026-12-01 11:00', 2, 'published')"
        )

        # Первая запись
        cur.execute("INSERT INTO bookings (slot_id, student_id, status) VALUES (100, 20, 'active')")

        # Вторая такая же запись должна упасть с ошибкой UniqueViolation (так как в init.sql есть ограничение uq_student_slot)
        with pytest.raises(psycopg2.errors.UniqueViolation):
            cur.execute("INSERT INTO bookings (slot_id, student_id, status) VALUES (100, 20, 'active')")


def test_add_to_waitlist(db):
    """Тест проверяет, что реальный запрос из queries.sql (4.1) правильно считает позицию в очереди."""
    with db.cursor() as cur:
        # Подготовка данных
        cur.execute(
            "INSERT INTO users (id, email, password_hash, full_name, role) VALUES (30, 't2@t.com', 'h', 'T2', 'teacher')"
        )
        cur.execute(
            "INSERT INTO users (id, email, password_hash, full_name, role) VALUES (40, 's1@s.com', 'h', 'S1', 'student')"
        )
        cur.execute(
            "INSERT INTO users (id, email, password_hash, full_name, role) VALUES (50, 's2@s.com', 'h', 'S2', 'student')"
        )
        cur.execute(
            "INSERT INTO slots (id, teacher_id, title, starts_at, ends_at, capacity, status) VALUES (200, 30, 'Slot 2', '2026-12-02 10:00', '2026-12-02 11:00', 1, 'published')"
        )

        # Вставляем первого студента, используя реальный запрос 4.1 из queries.sql
        cur.execute(
            """
            INSERT INTO waitlist (slot_id, student_id, position, status)
            VALUES (200, 40, (SELECT COALESCE(MAX(position), 0) + 1 FROM waitlist WHERE slot_id = 200), 'waiting')
        """
        )

        # Вставляем второго студента, используя тот же запрос
        cur.execute(
            """
            INSERT INTO waitlist (slot_id, student_id, position, status)
            VALUES (200, 50, (SELECT COALESCE(MAX(position), 0) + 1 FROM waitlist WHERE slot_id = 200), 'waiting')
            RETURNING position
        """
        )

        # Проверяем, что база сама посчитала позицию как 2
        second_student_position = cur.fetchone()[0]
        assert second_student_position == 2
