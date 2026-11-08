# Бази даних

Одна PostgreSQL, чотири бази. У кожного сервісу свій користувач БД, який має доступ **тільки до своєї бази** (див. `infra/postgres/init.sql`).

| База | Сервіс | Користувач | Міграції |
|---|---|---|---|
| `identity_db` | identity | `identity_svc` | Flyway |
| `project_db` | project | `project_svc` | Flyway |
| `board_db` | board | `board_svc` | EF Core Migrations |
| `activity_db` | activity | `activity_svc` | DbUp (SQL-скрипти) |

Загальні правила:

- Таблиці й колонки — `snake_case`, таблиці в множині.
- Первинні ключі — `uuid` (генерує застосунок). Виняток — журнали з `bigint generated always as identity`.
- Час — `timestamptz`, завжди UTC.
- Enum зберігаємо як `varchar` з `CHECK`, а не як тип PostgreSQL: так простіше міграції й мапінг в обох мовах.
- Кожен сервіс-споживач має таблицю `processed_events (event_id uuid primary key, processed_at timestamptz not null)`.
- Копії чужих даних (read model) мають суфікс `_refs` і змінюються **тільки** обробниками подій.

Нижче — схема як перелік колонок. Міграції пишете самі: це частина задач.

## identity_db

**users**
- `id uuid PK`
- `github_id bigint NOT NULL UNIQUE` — шукаємо користувача саме за ним, бо логін на GitHub можна змінити
- `github_login varchar(39) NOT NULL UNIQUE`
- `display_name varchar(100) NOT NULL`
- `avatar_url text`
- `email varchar(255)` — може бути null, якщо пошта на GitHub прихована
- `bio varchar(500)`
- `created_at timestamptz NOT NULL`, `updated_at timestamptz NOT NULL`

**user_skills**
- `user_id uuid FK → users(id) ON DELETE CASCADE`
- `skill varchar(50) NOT NULL`
- PK (`user_id`, `skill`)

**user_showcase_repos**
- `user_id uuid FK → users(id) ON DELETE CASCADE`
- `github_repo_id bigint NOT NULL`
- `name varchar(100) NOT NULL`, `url text NOT NULL`, `language varchar(50)`, `stars int NOT NULL DEFAULT 0`
- `position smallint NOT NULL`
- PK (`user_id`, `github_repo_id`)

**github_tokens**
- `user_id uuid PK FK → users(id) ON DELETE CASCADE`
- `access_token_encrypted text NOT NULL` — AES-GCM, ключ зі змінної середовища
- `scopes varchar(200)`
- `is_valid boolean NOT NULL DEFAULT true` — false, якщо GitHub відповів 401
- `updated_at timestamptz NOT NULL`

**refresh_tokens**
- `id uuid PK`
- `user_id uuid FK → users(id) ON DELETE CASCADE`
- `token_hash varchar(64) NOT NULL UNIQUE` — SHA-256 від токена, сам токен не зберігаємо
- `expires_at timestamptz NOT NULL`, `revoked_at timestamptz`
- `created_at timestamptz NOT NULL`, `user_agent varchar(300)`
- індекс по `user_id`

## project_db

**institutions**
- `id uuid PK`
- `edbo_id varchar(20) UNIQUE` — ідентифікатор у реєстрі ЄДЕБО, якщо є
- `name varchar(500) NOT NULL`, `short_name varchar(200)`
- `type varchar(30) NOT NULL CHECK (type IN ('HIGHER','PROFESSIONAL_PRE_HIGHER','VOCATIONAL','SCHOOL'))`
- `region varchar(100)`, `city varchar(100)`
- `email_domain varchar(100)` — наприклад `rcit.ukr.education`, може бути null
- `created_at timestamptz NOT NULL`

**institution_members**
- `institution_id uuid FK → institutions(id)`
- `user_id uuid NOT NULL`
- `role varchar(20) NOT NULL CHECK (role IN ('STUDENT','TEACHER','ADMIN'))`
- `verified_by varchar(20) NOT NULL CHECK (verified_by IN ('EMAIL_DOMAIN','ADMIN_APPROVAL','MANUAL'))`
- `joined_at timestamptz NOT NULL`
- PK (`institution_id`, `user_id`)

**institution_join_requests**
- `id uuid PK`, `institution_id uuid FK`, `user_id uuid NOT NULL`
- `message varchar(500)`
- `status varchar(20) NOT NULL CHECK (status IN ('PENDING','APPROVED','REJECTED'))`
- `created_at timestamptz NOT NULL`, `decided_by uuid`, `decided_at timestamptz`
- унікальний частковий індекс (`institution_id`, `user_id`) `WHERE status = 'PENDING'`

**email_verification_codes**
- `id uuid PK`, `user_id uuid NOT NULL`, `institution_id uuid FK`
- `email varchar(255) NOT NULL`
- `code_hash varchar(64) NOT NULL`
- `attempts smallint NOT NULL DEFAULT 0` — після 5 спроб код недійсний
- `expires_at timestamptz NOT NULL` — 15 хвилин
- `used_at timestamptz`

**projects**
- `id uuid PK`
- `institution_id uuid NOT NULL FK → institutions(id)`
- `owner_id uuid NOT NULL`
- `title varchar(120) NOT NULL`
- `description text NOT NULL`
- `repo_url text`, `team_chat_url text`
- `status varchar(20) NOT NULL CHECK (status IN ('ACTIVE','INACTIVE','ARCHIVED'))`
- `last_activity_at timestamptz NOT NULL`
- `created_at timestamptz NOT NULL`, `updated_at timestamptz NOT NULL`
- `search_vector tsvector GENERATED ALWAYS AS (setweight(to_tsvector('simple', coalesce(title,'')), 'A') || setweight(to_tsvector('simple', coalesce(description,'')), 'B')) STORED`
- індекси: GIN по `search_vector`; по `institution_id`; по `owner_id`

Конфігурація `simple`, бо вбудованого українського стемера в PostgreSQL немає. Для пошуку з помилками в назві — бонус: розширення `pg_trgm`.

**project_stack**
- `project_id uuid FK → projects(id) ON DELETE CASCADE`
- `tag varchar(40) NOT NULL`
- PK (`project_id`, `tag`), індекс по `tag`

**project_members**
- `project_id uuid FK → projects(id) ON DELETE CASCADE`
- `user_id uuid NOT NULL`
- `project_role varchar(10) NOT NULL CHECK (project_role IN ('OWNER','MEMBER'))`
- `specialty varchar(20)`
- `joined_at timestamptz NOT NULL`
- PK (`project_id`, `user_id`), індекс по `user_id`

**open_roles**
- `id uuid PK`, `project_id uuid FK ON DELETE CASCADE`
- `specialty varchar(20) NOT NULL`
- `description varchar(300)`
- `created_at timestamptz NOT NULL`

**project_join_requests**
- `id uuid PK`, `project_id uuid FK`, `user_id uuid NOT NULL`
- `specialty varchar(20)`, `message varchar(500)`
- `status varchar(20) NOT NULL CHECK (status IN ('PENDING','APPROVED','REJECTED','CANCELLED'))`
- `created_at timestamptz NOT NULL`, `decided_at timestamptz`
- унікальний частковий індекс (`project_id`, `user_id`) `WHERE status = 'PENDING'`

**user_refs** — копія з подій `user.*`
- `user_id uuid PK`, `github_login varchar(39)`, `display_name varchar(100)`, `avatar_url text`

**processed_events**

Як рахуються ліміти:
- **3 власних**: `project_members` з `project_role = 'OWNER'`, де проєкт не `ARCHIVED`.
- **5 приєднань**: `project_members` з `project_role = 'MEMBER'`, де проєкт не `ARCHIVED`.

## board_db

**boards**
- `id uuid PK`
- `project_id uuid NOT NULL UNIQUE`
- `is_read_only boolean NOT NULL DEFAULT false` — true після `project.archived`
- `created_at timestamptz NOT NULL`

**board_columns**
- `id uuid PK`, `board_id uuid FK → boards(id) ON DELETE CASCADE`
- `name varchar(50) NOT NULL`
- `position int NOT NULL`
- `is_done boolean NOT NULL DEFAULT false` — картки в цій колонці вважаються виконаними
- `created_at timestamptz NOT NULL`

**cards**
- `id uuid PK`
- `board_id uuid FK → boards(id) ON DELETE CASCADE`
- `column_id uuid FK → board_columns(id)`
- `title varchar(200) NOT NULL`, `description text`
- `assignee_id uuid`
- `position double precision NOT NULL` — дробовий індекс для порядку, див. задачу CS-03
- `created_by uuid NOT NULL`
- `created_at timestamptz NOT NULL`, `updated_at timestamptz NOT NULL`
- `completed_at timestamptz`
- індекс (`column_id`, `position`)

**card_labels**
- `card_id uuid FK → cards(id) ON DELETE CASCADE`
- `label varchar(30) NOT NULL`
- PK (`card_id`, `label`)

**card_comments**
- `id uuid PK`, `card_id uuid FK → cards(id) ON DELETE CASCADE`
- `author_id uuid NOT NULL`
- `text varchar(2000) NOT NULL`
- `created_at timestamptz NOT NULL`, `edited_at timestamptz`

**project_member_refs** — копія з подій `project.member-*`
- `project_id uuid`, `user_id uuid`, `project_role varchar(10) NOT NULL`
- PK (`project_id`, `user_id`)

**user_refs**, **processed_events**

## activity_db

**activity_log**
- `id bigint GENERATED ALWAYS AS IDENTITY PK`
- `event_id uuid NOT NULL UNIQUE`
- `project_id uuid NOT NULL`, `actor_id uuid`
- `type varchar(60) NOT NULL`
- `payload jsonb NOT NULL`
- `occurred_at timestamptz NOT NULL`
- індекс (`project_id`, `occurred_at DESC`)

**contributions**
- `user_id uuid`, `project_id uuid`
- `specialty varchar(20)`
- `cards_completed int NOT NULL DEFAULT 0 CHECK (cards_completed >= 0)`
- `comments int NOT NULL DEFAULT 0`
- `first_activity_at timestamptz`, `last_activity_at timestamptz`
- PK (`user_id`, `project_id`)

**project_refs** — копія з подій `project.*` плюс власний облік активності
- `project_id uuid PK`, `institution_id uuid`, `title varchar(120)`
- `status varchar(20) NOT NULL` — `ACTIVE`, `INACTIVE`, `ARCHIVED`
- `last_activity_at timestamptz NOT NULL`

**user_refs**, **processed_events**
