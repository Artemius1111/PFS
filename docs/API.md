# REST API

Усі запити йдуть через gateway: `http://localhost:8080`. Формати, помилки й пагінація — розділ 9 у [ARCHITECTURE.md](ARCHITECTURE.md).

Позначки: 🔓 — без токена, 🔑 — потрібен JWT, 👑 — тільки OWNER проєкту, 🎓 — TEACHER або ADMIN закладу.

## Маршрути gateway

| Префікс шляху | Куди | Порт |
|---|---|---|
| `/api/auth/**`, `/api/users/**`, `/api/dev/**` | identity-service | 8081 |
| `/api/institutions/**`, `/api/projects/**` | project-service | 8082 |
| `/api/boards/**`, `/hubs/board/**` | board-service | 8083 |
| `/api/portfolio/**`, `/api/activity/**` | activity-service | 8084 |
| `/health/{service}` | `/health` відповідного сервісу (YARP-трансформація `PathSet`) | — |

`/.well-known/**` у identity назовні **не** відкриваємо: сервіси ходять туди напряму всередині мережі.

## identity-service

| Метод | Шлях | Доступ | Що робить |
|---|---|---|---|
| GET | `/api/auth/github` | 🔓 | Почати вхід: redirect на GitHub |
| GET | `/api/auth/callback/github` | 🔓 | Колбек GitHub. Ставить refresh-cookie, redirect на фронтенд |
| POST | `/api/auth/refresh` | cookie | Новий access-токен: `{ "accessToken": "...", "expiresIn": 900 }` |
| POST | `/api/auth/logout` | cookie | Відкликати refresh-токен, видалити cookie |
| GET | `/api/users/me` | 🔑 | Мій профіль |
| PATCH | `/api/users/me` | 🔑 | Змінити `displayName`, `bio`, `skills[]` |
| GET | `/api/users/{login}` | 🔑 | Публічний профіль за GitHub-логіном |
| GET | `/api/users/me/github-repos` | 🔑 | Мої публічні репозиторії з GitHub |
| PUT | `/api/users/me/showcase-repos` | 🔑 | Вибрати до 6 репозиторіїв для портфоліо |
| POST | `/api/dev/token` | 🔓, тільки профіль `dev` | Тестовий JWT: `{ "login": "test-user" }` |
| GET | `/.well-known/openid-configuration` | внутрішній | `issuer` і `jwks_uri` |
| GET | `/.well-known/jwks.json` | внутрішній | Публічний ключ для перевірки JWT |

Приклад `GET /api/users/me`:

```json
{
  "id": "0f8b3c2e-6a1d-4f7e-9b0a-2d4c6e8f1a3b",
  "githubLogin": "taras-dev",
  "displayName": "Тарас",
  "avatarUrl": "https://avatars.githubusercontent.com/u/123",
  "bio": "Backend на Java, вчу Spring",
  "skills": ["Java", "Spring Boot", "PostgreSQL"],
  "showcaseRepos": [
    { "name": "weather-bot", "url": "https://github.com/taras-dev/weather-bot", "language": "Java", "stars": 3 }
  ],
  "createdAt": "2026-11-05T21:00:00Z"
}
```

## project-service

### Навчальні заклади

| Метод | Шлях | Доступ | Що робить |
|---|---|---|---|
| GET | `/api/institutions?query=&region=&page=&size=` | 🔑 | Пошук закладів |
| GET | `/api/institutions/{id}` | 🔑 | Картка закладу |
| GET | `/api/institutions/mine` | 🔑 | Заклади, де я учасник |
| POST | `/api/institutions/{id}/join` | 🔑 | Вступити. Тіло: `{ "email": "...", "message": "..." }`. Якщо домен пошти збігається з доменом закладу — надсилається код, інакше створюється заявка |
| POST | `/api/institutions/{id}/verify-email` | 🔑 | Підтвердити код: `{ "code": "482913" }` |
| GET | `/api/institutions/{id}/members` | 🔑 | Учасники закладу |
| GET | `/api/institutions/{id}/join-requests` | 🎓 | Заявки на вступ |
| POST | `/api/institutions/{id}/join-requests/{requestId}/approve` | 🎓 | Схвалити |
| POST | `/api/institutions/{id}/join-requests/{requestId}/reject` | 🎓 | Відхилити |
| GET | `/api/institutions/{id}/projects?query=&stack=&openRole=&status=` | 🔑 | Проєкти всередині закладу |

### Проєкти

| Метод | Шлях | Доступ | Що робить |
|---|---|---|---|
| POST | `/api/projects` | 🔑 | Створити проєкт (ліміт 3 власних) |
| GET | `/api/projects/search?q=&stack=&openRole=&institutionId=&status=&page=&size=` | 🔑 | Пошук по всій платформі |
| GET | `/api/projects/mine` | 🔑 | Мої проєкти: власні й ті, де я учасник |
| GET | `/api/projects/{id}` | 🔑 | Картка проєкту |
| PATCH | `/api/projects/{id}` | 👑 | Змінити опис, стек, посилання |
| POST | `/api/projects/{id}/archive` | 👑 | Архівувати |
| GET | `/api/projects/{id}/members` | 🔑 | Учасники |
| DELETE | `/api/projects/{id}/members/{userId}` | 👑 | Виключити учасника |
| POST | `/api/projects/{id}/leave` | 🔑 | Вийти з проєкту (OWNER вийти не може) |
| GET | `/api/projects/{id}/open-roles` | 🔑 | Ролі «шукаємо» |
| POST | `/api/projects/{id}/open-roles` | 👑 | Додати роль: `{ "specialty": "FRONTEND", "description": "React, 5 год/тиждень" }` |
| DELETE | `/api/projects/{id}/open-roles/{roleId}` | 👑 | Прибрати роль |
| POST | `/api/projects/{id}/join-requests` | 🔑 | Подати заявку: `{ "specialty": "FRONTEND", "message": "..." }` (ліміт 5 приєднань) |
| GET | `/api/projects/{id}/join-requests` | 👑 | Заявки в проєкт |
| POST | `/api/projects/{id}/join-requests/{requestId}/approve` | 👑 | Схвалити |
| POST | `/api/projects/{id}/join-requests/{requestId}/reject` | 👑 | Відхилити |
| GET | `/api/projects/join-requests/mine` | 🔑 | Мої заявки і їхній статус |

Приклад `POST /api/projects`:

```json
{
  "institutionId": "6b1e...",
  "title": "Розклад пар для коледжу",
  "description": "Телеграм-бот і сайт з розкладом...",
  "stack": ["Java", "Spring Boot", "React"],
  "repoUrl": "https://github.com/team/schedule",
  "teamChatUrl": "https://t.me/+abc123"
}
```

Помилка ліміту (422):

```json
{
  "type": "https://projecthub.dev/errors/project-limit",
  "title": "Project limit reached",
  "status": 422,
  "detail": "You already own 3 active projects. Archive one to create a new one.",
  "limit": 3
}
```

Значення `specialty`: `FRONTEND`, `BACKEND`, `FULLSTACK`, `MOBILE`, `QA`, `DESIGN`, `DEVOPS`, `PM`, `OTHER`.

## board-service

| Метод | Шлях | Доступ | Що робить |
|---|---|---|---|
| GET | `/api/boards/by-project/{projectId}` | 🔑 | Дошка з колонками й картками |
| POST | `/api/boards/{boardId}/columns` | учасник | Додати колонку: `{ "name": "Review", "isDone": false }` |
| PATCH | `/api/boards/{boardId}/columns/{columnId}` | учасник | Перейменувати або перемістити |
| DELETE | `/api/boards/{boardId}/columns/{columnId}` | 👑 | Видалити порожню колонку |
| POST | `/api/boards/{boardId}/cards` | учасник | Створити картку |
| GET | `/api/boards/{boardId}/cards/{cardId}` | 🔑 | Картка з коментарями |
| PATCH | `/api/boards/{boardId}/cards/{cardId}` | учасник | Змінити назву, опис, виконавця, мітки |
| POST | `/api/boards/{boardId}/cards/{cardId}/move` | учасник | Перемістити: `{ "toColumnId": "...", "afterCardId": "..." }` |
| DELETE | `/api/boards/{boardId}/cards/{cardId}` | учасник | Видалити картку |
| POST | `/api/boards/{boardId}/cards/{cardId}/comments` | учасник | Коментар: `{ "text": "..." }` |
| PATCH | `/api/boards/{boardId}/cards/{cardId}/comments/{commentId}` | автор | Редагувати свій коментар |
| DELETE | `/api/boards/{boardId}/cards/{cardId}/comments/{commentId}` | автор або 👑 | Видалити коментар |

«Учасник» — OWNER або MEMBER проєкту, до якого належить дошка.

Приклад `POST /api/boards/{boardId}/cards`:

```json
{
  "columnId": "c1...",
  "title": "Сторінка входу",
  "description": "Кнопка «Увійти через GitHub», редирект після входу",
  "assigneeId": "0f8b...",
  "labels": ["frontend"]
}
```

### SignalR-хаб `/hubs/board`

| Напрям | Метод | Дані |
|---|---|---|
| клієнт → сервер | `JoinBoard` | `boardId` |
| клієнт → сервер | `LeaveBoard` | `boardId` |
| сервер → клієнт | `CardCreated`, `CardUpdated` | картка повністю |
| сервер → клієнт | `CardMoved` | `{ cardId, toColumnId, position }` |
| сервер → клієнт | `CardDeleted` | `{ cardId }` |
| сервер → клієнт | `ColumnsChanged` | список колонок |
| сервер → клієнт | `CommentAdded` | коментар |

## activity-service

| Метод | Шлях | Доступ | Що робить |
|---|---|---|---|
| GET | `/api/portfolio/{userId}` | 🔑 | Внесок користувача по всіх проєктах |
| GET | `/api/activity/projects/{projectId}/feed?page=&size=` | 🔑 | Стрічка подій проєкту |
| GET | `/api/activity/projects/{projectId}/contributors` | 🔑 | Внесок кожного учасника проєкту |

Приклад `GET /api/portfolio/{userId}`:

```json
{
  "userId": "0f8b...",
  "totals": { "projects": 2, "cardsCompleted": 17, "comments": 41 },
  "projects": [
    {
      "projectId": "a7c2...",
      "title": "Розклад пар для коледжу",
      "projectStatus": "ACTIVE",
      "specialty": "FRONTEND",
      "cardsCompleted": 12,
      "comments": 30,
      "firstActivityAt": "2026-11-10T09:12:00Z",
      "lastActivityAt": "2026-12-20T18:40:00Z"
    }
  ]
}
```
