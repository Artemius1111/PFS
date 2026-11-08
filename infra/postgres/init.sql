-- Створення баз і користувачів для локальної розробки.
-- Паролі тут НЕ секретні і працюють тільки на вашому комп'ютері.
-- Скрипт виконується лише на порожньому томі. Після змін:
--   docker compose down -v && docker compose up -d

CREATE USER identity_svc WITH PASSWORD 'identity_dev';
CREATE USER project_svc  WITH PASSWORD 'project_dev';
CREATE USER board_svc    WITH PASSWORD 'board_dev';
CREATE USER activity_svc WITH PASSWORD 'activity_dev';

CREATE DATABASE identity_db OWNER identity_svc;
CREATE DATABASE project_db  OWNER project_svc;
CREATE DATABASE board_db    OWNER board_svc;
CREATE DATABASE activity_db OWNER activity_svc;

-- Кожен сервісний користувач підключається тільки до своєї бази.
REVOKE CONNECT ON DATABASE identity_db FROM PUBLIC;
REVOKE CONNECT ON DATABASE project_db  FROM PUBLIC;
REVOKE CONNECT ON DATABASE board_db    FROM PUBLIC;
REVOKE CONNECT ON DATABASE activity_db FROM PUBLIC;
