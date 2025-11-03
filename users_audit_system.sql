-- =====================================
--  🌍  НАСТРОЙКА ТАЙМЗОНЫ БАЗЫ ДАННЫХ
-- =====================================

-- Устанавливаем временную зону для текущей базы данных
ALTER DATABASE example_db SET timezone TO 'Europe/Moscow';

-- Устанавливаем временную зону для планировщика cron
ALTER SYSTEM SET cron.timezone = 'Europe/Moscow';

-- =====================================
-- 1️⃣ СОЗДАНИЕ ОСНОВНЫХ ТАБЛИЦ
-- =====================================

-- Основная таблица пользователей
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name TEXT,
    email TEXT,
    role TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица аудита для отслеживания изменений пользователей
CREATE TABLE IF NOT EXISTS users_audit (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    changed_by TEXT,
    field_changed TEXT,
    old_value TEXT,
    new_value TEXT
);

-- =====================================
-- 2️⃣ ФУНКЦИЯ ЛОГИРОВАНИЯ ИЗМЕНЕНИЙ
-- =====================================

-- Функция для автоматического логирования изменений в таблице users
CREATE OR REPLACE FUNCTION log_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    -- Обновляем поле updated_at при любых изменениях
    NEW.updated_at = CURRENT_TIMESTAMP;
    
    -- Логируем изменения имени
    IF OLD.name IS DISTINCT FROM NEW.name THEN
        INSERT INTO users_audit (user_id, changed_by, field_changed, old_value, new_value)
        VALUES (NEW.id, CURRENT_USER, 'name', OLD.name, NEW.name); 
    END IF;

    -- Логируем изменения email
    IF OLD.email IS DISTINCT FROM NEW.email THEN
        INSERT INTO users_audit (user_id, changed_by, field_changed, old_value, new_value)
        VALUES (NEW.id, CURRENT_USER, 'email', OLD.email, NEW.email);
    END IF;

    -- Логируем изменения роли
    IF OLD.role IS DISTINCT FROM NEW.role THEN
        INSERT INTO users_audit (user_id, changed_by, field_changed, old_value, new_value)
        VALUES (NEW.id, CURRENT_USER, 'role', OLD.role, NEW.role);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================
-- 3️⃣ ТРИГГЕР ДЛЯ АУДИТА ИЗМЕНЕНИЙ
-- =====================================

-- Удаляем триггер если он существует
DROP TRIGGER IF EXISTS users_audit_trigger ON users;

-- Создаем триггер для автоматического логирования изменений
CREATE TRIGGER users_audit_trigger
    BEFORE UPDATE ON users 
    FOR EACH ROW
    EXECUTE FUNCTION log_user_changes();

-- =====================================
-- 4️⃣ ФУНКЦИЯ ЭКСПОРТА АУДИТА В CSV
-- =====================================

-- Функция для экспорта данных аудита за вчерашний день в CSV файл
CREATE OR REPLACE FUNCTION export_audit_to_csv() RETURNS void AS $outers$
DECLARE
    path TEXT := '/tmp/users_audit_export' || to_char(NOW(), 'YYYYMMDD_HH24MI') || '.csv';
BEGIN
    EXECUTE format(
    $inner$
    COPY (
    SELECT user_id, field_changed, old_value, new_value, changed_by, changed_at
    FROM users_audit
    WHERE changed_at >= CURRENT_DATE - INTERVAL '1 day'
      AND changed_at < CURRENT_DATE
    ORDER BY changed_at
    ) TO '%s' WITH CSV HEADER
    $inner$, path
    );
END;
$outers$ LANGUAGE plpgsql;


-- =====================================
-- 5️⃣ НАСТРОЙКА ПЛАНИРОВЩИКА ЗАДАЧ
-- =====================================

-- Создаем cron-задачу для ежедневного экспорта в 3:00 утра
SELECT cron.schedule(
    'daily-audit-export',  -- имя задания
    '0 3 * * *',           -- каждый день в 3:00 утра
    'SELECT export_audit_to_csv();'
);


-- Проверяем, что cron-задача успешно добавлена
SELECT * FROM cron.job;

-- =====================================
-- 🔍 ТЕСТОВЫЕ ДАННЫЕ И ПРОВЕРКИ
-- =====================================

-- Добавляем тестового пользователя
INSERT INTO users (name, email, role) VALUES ('Alice', 'alice@example.com', 'user');
-- SELECT * FROM users;

-- Вносим изменения для проверки работы триггера аудита
UPDATE users SET name = 'Alice Smith', email = 'alice.smith@example.com' WHERE name = 'Alice';
-- SELECT * FROM users_audit;

-- Запускаем экспорт вручную для тестирования:
SELECT export_audit_to_csv();

