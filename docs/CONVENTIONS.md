# Домовленості

## Структура репозиторію

```
projecthub/
├── README.md
├── docker-compose.yml
├── .env.example
├── docs/                    документація і задачі
├── infra/postgres/          скрипт створення баз
├── services/
│   ├── gateway/             C#
│   ├── identity-service/    Java
│   ├── project-service/     Java
│   ├── board-service/       C#
│   ├── activity-service/    C#
│   └── shared-dotnet/       спільна бібліотека для C#-сервісів (з'явиться в CS-02)
└── .github/
    ├── workflows/           CI (задача SH-04)
    └── pull_request_template.md
```

Java-сервіси — окремі Gradle- або Maven-проєкти (оберіть одне на обидва і не змішуйте). C#-сервіси — проєкти в одному solution `services/ProjectHub.sln`.

## Мова

- **Код, назви, коміти, гілки, PR-заголовки — англійською.** Це піде в портфоліо, і його читатимуть роботодавці.
- **Документація в `docs/` — українською.**
- Тексти для користувача (помилки, листи) — поки англійською в коді; локалізацію зробимо разом із фронтендом.

## Гілки

- `main` — захищена: тільки через PR, мінімум 1 схвалення, CI зелений.
- Гілка на задачу: `<тип>/<ID>-<коротко>`, наприклад:
  - `feat/JV-03-jwt-issuing`
  - `feat/CS-07-signalr-hub`
  - `fix/CS-05-board-not-created`
  - `chore/SH-04-ci`

## Коміти

Формат [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(identity): issue RS256 access tokens
fix(board): keep card order after move between columns
test(project): cover 3-project ownership limit
docs: describe board.card-completed event
chore(ci): add dotnet build job
```

Типи: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`. Область у дужках — назва сервісу без `-service`.

## Pull Request

- Одна задача — один PR. Великий PR (більше ~400 змінених рядків) розбивайте.
- У описі — ID задачі і як перевірити (шаблон заповнюється автоматично).
- Рев'юер — **інший** учасник. Рев'ю протягом 48 годин.
- Рев'юер не мусить знати мову ідеально: питання «а навіщо тут це?» — теж рев'ю. Так і вчиться друга мова.
- Злиття — `Squash and merge`, щоб історія `main` була чистою.

## Іменування

| Що | Як | Приклад |
|---|---|---|
| Сервіси, папки | kebab-case | `board-service` |
| Java-пакети | `ua.projecthub.<service>.<layer>` | `ua.projecthub.project.domain` |
| C#-простори імен | `ProjectHub.<Service>.<Layer>` | `ProjectHub.Board.Api` |
| Таблиці й колонки | snake_case | `project_members.joined_at` |
| JSON | camelCase | `lastActivityAt` |
| REST-шляхи | kebab-case, іменники в множині | `/api/projects/{id}/join-requests` |
| Події | `<домен>.<дія-через-дефіс>` | `board.card-completed` |

## Структура коду всередині сервісу

Не беремо складну «чисту архітектуру» з десятьма шарами. Достатньо трьох:

- `api` — контролери / endpoints, DTO запитів і відповідей;
- `domain` — сутності, бізнес-правила (ліміти, хто що може), сервіси;
- `infrastructure` — репозиторії, БД, RabbitMQ, GitHub-клієнт.

Правило: бізнес-правило (наприклад, «не більше 3 проєктів») живе в `domain` і покривається юніт-тестом без бази.

## Порти

| Сервіс | Порт |
|---|---|
| gateway | 8080 |
| identity-service | 8081 |
| project-service | 8082 |
| board-service | 8083 |
| activity-service | 8084 |
| PostgreSQL | 5433 на хості → 5432 у контейнері |
| RabbitMQ | 5672, панель 15672 |
| Mailpit | SMTP 1025, веб 8025 |
| Frontend (dev) | 5173 |

## Змінні середовища і секрети

- Справжні значення — тільки в `.env` (він у `.gitignore`) або в user secrets / налаштуваннях IDE.
- Шаблон із порожніми значеннями — `.env.example`. Додали нову змінну — додайте її й туди.
- Приватний ключ JWT, GitHub client secret, ключ шифрування токенів **ніколи** не потрапляють у git. Випадково закомітили — одразу перевипустіть секрет: видалення з історії не допоможе, бо його вже могли скопіювати.
- Паролі в `infra/postgres/init.sql` — тільки для локальної розробки.

## Логи

- Структуровані логи з `correlationId` у кожному рядку.
- Ніколи не логувати токени, коди підтвердження, паролі, повні email.

## Тести

- Бізнес-правила — юніт-тести (JUnit 5 / xUnit).
- Робота з БД і RabbitMQ — інтеграційні тести на Testcontainers (є для Java і .NET).
- Для кожного ендпоінта з правами — хоча б один тест «чужий користувач отримує 403».

## Definition of Done

Задача готова, коли:

- [ ] код у `main` через PR, рев'ю від напарника пройдено;
- [ ] CI зелений;
- [ ] бізнес-правила покриті тестами;
- [ ] змінені контракти оновлені в `docs/API.md` / `docs/EVENTS.md`;
- [ ] у README сервісу написано, як його запустити;
- [ ] немає секретів у коді.
