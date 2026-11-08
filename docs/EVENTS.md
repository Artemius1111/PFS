# Події (RabbitMQ)

Це контракт між Java і C#. Якщо змінюєте подію — спершу правка тут і погодження з напарником, потім код.

## Топологія

- Один exchange типу **topic**: `projecthub.events` (durable).
- Routing key = тип події, наприклад `project.member-joined`.
- У кожного сервісу-споживача своя durable-черга:

| Черга | Ключі прив'язки |
|---|---|
| `project-service.events` | `user.*`, `activity.project-status-changed` |
| `board-service.events` | `user.*`, `project.*` |
| `activity-service.events` | `user.*`, `project.*`, `board.*` |

- Dead-letter: exchange `projecthub.dlx` (fanout) → черга `<service>.events.dlq`. У кожної основної черги аргумент `x-dead-letter-exchange = projecthub.dlx`.
- Помилка обробки → `nack` без повтору → повідомлення падає в DLQ. На MVP DLQ розбираємо вручну в панелі RabbitMQ (http://localhost:15672). Автоматичні повтори — Фаза 2.

## Конверт

Кожна подія — JSON такого вигляду:

```json
{
  "eventId": "9c4e7a10-3b2d-4f61-8a9e-0d1c2b3a4f5e",
  "type": "project.member-joined",
  "version": 1,
  "occurredAt": "2026-11-05T21:00:00Z",
  "producer": "project-service",
  "correlationId": "b1f0c6d2-...",
  "data": { }
}
```

Властивості AMQP-повідомлення: `content_type = application/json`, `message_id = eventId`, `type = type`, `delivery_mode = 2` (persistent).

## Правила

1. **camelCase**, UUID рядком, час UTC ISO-8601 з `Z`, enum рядком `UPPER_SNAKE_CASE`.
2. **Тільки додаємо поля.** Споживач ігнорує невідомі поля: System.Text.Json робить це за замовчуванням, у Spring Boot Jackson теж. Якщо треба змінити або видалити поле — нова версія (`version: 2`) і період, коли публікуються обидві.
3. **Ідемпотентність.** Подія може прийти двічі. Споживач записує `eventId` у таблицю `processed_events` **в тій самій транзакції**, що й зміни. Якщо такий `eventId` уже є — пропускає подію.
4. **Порядок не гарантований.** Якщо в події є час (`lastActivityAt`, `occurredAt`), не перезаписуйте новіші дані старішими.
5. **Публікація після коміту.** Спершу транзакція в БД, потім відправка. Між ними подію можна втратити — це закриє Outbox у Фазі 2.
6. **Розбираємо конверт самі.** Повідомлення приймаємо як рядок або байти, парсимо конверт і диспетчеризуємо за `type`. Так однаково в обох мовах і не залежить від службових заголовків бібліотек: Spring AMQP додає `__TypeId__`, а C# його не надсилає.

## Каталог подій

| Тип | Хто публікує | Хто слухає | Коли |
|---|---|---|---|
| `user.registered` | identity | project, board, activity | Перший вхід користувача |
| `user.updated` | identity | project, board, activity | Змінились ім'я або аватар |
| `project.created` | project | board, activity | Створено проєкт |
| `project.updated` | project | activity | Змінилась назва |
| `project.archived` | project | board, activity | Проєкт архівовано |
| `project.member-joined` | project | board, activity | Учасник доданий, зокрема OWNER при створенні |
| `project.member-left` | project | board, activity | Учасник вийшов або виключений |
| `board.card-created` | board | activity | Створено картку |
| `board.card-moved` | board | activity | Картку переміщено між колонками |
| `board.card-completed` | board | activity | Картка потрапила в колонку з `isDone = true` |
| `board.card-reopened` | board | activity | Картка вийшла з done-колонки |
| `board.comment-added` | board | activity | Додано коментар |
| `activity.project-status-changed` | activity | project | Проєкт став неактивним або знову активним |

## Поле `data` для кожної події

### user.registered, user.updated

```json
{
  "userId": "0f8b3c2e-6a1d-4f7e-9b0a-2d4c6e8f1a3b",
  "githubLogin": "taras-dev",
  "displayName": "Тарас",
  "avatarUrl": "https://avatars.githubusercontent.com/u/123"
}
```

### project.created

```json
{
  "projectId": "a7c2...",
  "institutionId": "6b1e...",
  "ownerId": "0f8b...",
  "title": "Розклад пар для коледжу"
}
```

Одразу після неї публікується `project.member-joined` для власника з `projectRole = OWNER`.

### project.updated

```json
{ "projectId": "a7c2...", "title": "Розклад пар v2" }
```

### project.archived

```json
{ "projectId": "a7c2...", "archivedAt": "2026-12-01T10:00:00Z" }
```

### project.member-joined

```json
{
  "projectId": "a7c2...",
  "userId": "5d3a...",
  "projectRole": "MEMBER",
  "specialty": "FRONTEND",
  "joinedAt": "2026-11-12T15:30:00Z"
}
```

`projectRole`: `OWNER` або `MEMBER`.

### project.member-left

```json
{ "projectId": "a7c2...", "userId": "5d3a...", "reason": "REMOVED" }
```

`reason`: `LEFT` або `REMOVED`.

### board.card-created

```json
{
  "projectId": "a7c2...",
  "boardId": "e2f1...",
  "cardId": "77b0...",
  "title": "Сторінка входу",
  "createdBy": "0f8b...",
  "assigneeId": "5d3a..."
}
```

### board.card-moved

```json
{
  "projectId": "a7c2...",
  "cardId": "77b0...",
  "fromColumnId": "c1...",
  "toColumnId": "c2...",
  "movedBy": "5d3a..."
}
```

### board.card-completed

```json
{
  "projectId": "a7c2...",
  "cardId": "77b0...",
  "title": "Сторінка входу",
  "assigneeId": "5d3a...",
  "completedBy": "5d3a...",
  "completedAt": "2026-11-20T19:05:00Z",
  "labels": ["frontend"]
}
```

Внесок зараховується `assigneeId`. Якщо виконавця немає — тому, хто перемістив (`completedBy`).

### board.card-reopened

```json
{ "projectId": "a7c2...", "cardId": "77b0...", "assigneeId": "5d3a...", "completedBy": "5d3a..." }
```

### board.comment-added

```json
{ "projectId": "a7c2...", "cardId": "77b0...", "commentId": "1a2b...", "authorId": "0f8b..." }
```

### activity.project-status-changed

```json
{
  "projectId": "a7c2...",
  "status": "INACTIVE",
  "lastActivityAt": "2026-10-01T12:00:00Z"
}
```

`status`: `ACTIVE` або `INACTIVE`. project-service не змінює статус проєктів у стані `ARCHIVED`.
