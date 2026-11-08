# Задачі C#-розробника

Сервіси: **gateway** (порт 8080), **board-service** (8083), **activity-service** (8084) і спільна бібліотека **ProjectHub.ServiceDefaults**.
Стек: .NET 10, ASP.NET Core, YARP, SignalR, EF Core + Npgsql, Dapper, RabbitMQ.Client 7, xUnit, Testcontainers.

Перед стартом кожної задачі напишіть ментору її ID і свій план.

> **.NET 10, а не 8 чи 9.** Підтримка .NET 8 і 9 закінчується 10 листопада 2026 року. Якщо туторіал написаний для .NET 6–8, він майже завжди працює і на 10, але шаблон `webapi` тепер створює проєкт без Swagger UI: OpenAPI-документ дає `Microsoft.AspNetCore.OpenApi`, а інтерфейс можна додати пакетом `Scalar.AspNetCore`.

## Спринт 1 · Вхід і перша дошка

### CS-01 · Gateway на YARP
**Розмір:** S · **Залежить від:** SH-02

**Що зробити**
- `services/ProjectHub.sln`, проєкт `ProjectHub.Gateway` (`dotnet new web`), пакет `Yarp.ReverseProxy`.
- `AddReverseProxy().LoadFromConfig(...)` + `MapReverseProxy()`. Маршрути й кластери — в `appsettings.json` за таблицею з `API.md`. Одна route — один шаблон шляху, тому для кожного префікса окрема route.
- `/health/{service}` → `/health` сервісу через трансформацію `PathSet`.
- CORS: тільки `FRONTEND_URL`, `AllowCredentials()` (потрібно для refresh-cookie).
- Middleware `X-Correlation-Id`: якщо заголовка немає — згенерувати, додати у відповідь і передати далі.
- Адреси сервісів: `localhost:808x` локально; у Docker перевизначаються змінними середовища на кшталт `ReverseProxy__Clusters__identity__Destinations__d1__Address`.

**Готово, коли**
- [ ] Демо Спринту 0 проходить: `/health/identity` і решта повертають 200 через gateway.
- [ ] У відповіді завжди є `X-Correlation-Id`.

**Чого навчишся:** reverse proxy, конфігурація ASP.NET Core, middleware pipeline.

### CS-02 · ServiceDefaults і перевірка JWT
**Розмір:** M · **Залежить від:** CS-01

**Що зробити**
- Бібліотека `services/shared-dotnet/ProjectHub.ServiceDefaults` з методами-розширеннями, які підключатимуть усі C#-сервіси:
  - `AddProjectHubAuthentication()` — JwtBearer;
  - `AddProjectHubProblemDetails()` — єдиний формат помилок;
  - `MapProjectHubHealth()` — `GET /health`.
- JwtBearer:
  - `MetadataAddress = "{IDENTITY_URL}/.well-known/openid-configuration"`, у dev `RequireHttpsMetadata = false`;
  - `ValidAudience = "projecthub"`;
  - `MapInboundClaims = false` — інакше `sub` перетвориться на довгу назву claim зі схеми Microsoft і ви будете довго шукати, куди він подівся.
- Поки JV-03 не готова: тестові токени через `dotnet user-jwts create --audience projecthub --name test-user`. Перемикання на справжні токени — тільки зміною конфігурації, без зміни коду.
- У gateway: route-рівнева авторизація YARP (`AuthorizationPolicy`): `/api/auth/**` і `/health/**` — `anonymous`, усе інше — `default`.
- Хелпер `User.GetUserId()`, що дістає `Guid` із claim `sub`.

**Готово, коли**
- [ ] Без токена `/api/boards/...` через gateway → 401, з токеном → проходить.
- [ ] Після готовності JV-03 board-service приймає токени identity, а `user-jwts` вимкнено.

**Чого навчишся:** як влаштована перевірка JWT в ASP.NET Core, спільний код між сервісами без копіпасту.

### CS-03 · Каркас board-service і дошка
**Розмір:** L · **Залежить від:** CS-02

**Що зробити**
- Проєкт `ProjectHub.Board`, EF Core + `Npgsql.EntityFrameworkCore.PostgreSQL`, пакет `EFCore.NamingConventions` з `UseSnakeCaseNamingConvention()` — таблиці й колонки будуть у `snake_case`, як у `DATABASE.md`.
- Сутності `Board`, `BoardColumn`, `Card`, `CardLabel`, перша міграція.
- Endpoints (Minimal API з `MapGroup`): дошка за проєктом, CRUD колонок, CRUD карток, переміщення картки.
- **Порядок карток — дробовий індекс:** нова картка в кінці = `max + 1000`; між двома = `(a + b) / 2`; якщо проміжок став меншим за `1e-6` — перенумерувати колонку з кроком 1000. Так переміщення змінює один рядок, а не всю колонку.
- Тимчасовий `POST /api/boards/dev` (тільки Development) — створити дошку з колонками To Do / In Progress / Done. Видалите в CS-05, коли дошки створюватимуться з подій.
- Права поки спрощені: будь-який залогінений. Справжні — в CS-05.

**Готово, коли**
- [ ] Інтеграційні тести через `WebApplicationFactory` + `Testcontainers.PostgreSql`: створення, переміщення між колонками, порядок після 3 переміщень правильний.
- [ ] Юніт-тести алгоритму дробового індексу, зокрема перенумерації.

**Чого навчишся:** EF Core і міграції, Minimal API, алгоритм впорядкування, з яким працюють справжні канбан-дошки.

## Спринт 2 · Проєкти і події

### CS-04 · Події в ServiceDefaults
**Розмір:** M · **Залежить від:** CS-02, SH-03

**Що зробити**
- `RabbitMQ.Client` 7.x — повністю асинхронний API: `CreateConnectionAsync`, `CreateChannelAsync`, `BasicPublishAsync`, `AsyncEventingBasicConsumer`. Старі туторіали з `IModel` і синхронними методами вже не підходять.
- `EventEnvelope` (record) за `EVENTS.md`, серіалізація `System.Text.Json` з `JsonSerializerDefaults.Web` (camelCase).
- `IEventPublisher` — виставляє `MessageId`, `Type`, `ContentType`, persistent.
- `EventConsumerService : BackgroundService`:
  - при старті оголошує exchange, DLX, свою чергу і прив'язки;
  - `BasicQosAsync(prefetchCount: 10)`;
  - для кожного повідомлення — новий DI-scope (бо `DbContext` scoped), розбір конверта, пошук `IEventHandler` за `type`;
  - успіх → `BasicAckAsync`; виняток → лог + `BasicNackAsync(requeue: false)` → DLQ;
  - невідомий `type` → ack і рядок у лог (подія просто не для нас).
- Хелпер ідемпотентності над `processed_events`.

**Готово, коли**
- [ ] Інтеграційний тест з `Testcontainers.RabbitMq`: опублікована подія доходить до обробника; подія, що кидає виняток, опиняється в DLQ.

**Чого навчишся:** брокер повідомлень зсередини, ack/nack, dead-letter, фонові сервіси.

### CS-05 · board-service слухає події
**Розмір:** M · **Залежить від:** CS-04, JV-06

**Що зробити**
- Обробники:
  - `project.created` → дошка з колонками To Do, In Progress, Done (`isDone = true`);
  - `project.member-joined` / `member-left` → `project_member_refs`;
  - `project.archived` → `is_read_only = true`;
  - `user.registered` / `user.updated` → `user_refs`.
- Права: змінювати дошку можуть тільки OWNER і MEMBER проєкту (за `project_member_refs`), дивитись — будь-який залогінений. Архівована дошка — тільки читання.
- Видалити тимчасовий `POST /api/boards/dev`.

**Підказка ментора:** якщо JV-06 ще не готова, не чекайте — публікуйте тестові події вручну з панелі RabbitMQ: Exchanges → `projecthub.events` → Publish message, routing key `project.created`, тіло — приклад із `EVENTS.md`.

**Готово, коли**
- [ ] Створення проєкту в project-service → дошка з'являється в board-service.
- [ ] Тести: не-учасник отримує 403 на зміну картки; після `member-left` колишній учасник теж отримує 403.

**Чого навчишся:** read model, eventual consistency, авторизація за даними, які прийшли з іншого сервісу.

### CS-06 · Коментарі й події дошки
**Розмір:** M · **Залежить від:** CS-05

**Що зробити**
- Коментарі: додати, редагувати свій, видалити свій (OWNER може видалити будь-який). Не більше 2000 символів.
- Публікувати після `SaveChangesAsync`:
  - `board.card-created`, `board.card-moved`, `board.comment-added`;
  - `board.card-completed` — коли картка **входить** у колонку з `isDone = true` (заповнити `completed_at`);
  - `board.card-reopened` — коли **виходить** з неї (очистити `completed_at`).
- Переміщення всередині тієї самої done-колонки не генерує `completed` повторно.

**Готово, коли**
- [ ] Тести на всі переходи: To Do → Done, Done → In Progress, Done → Done.
- [ ] C#-логіка подій узгоджена з `EVENTS.md` (покажіть приклад повідомлення з панелі RabbitMQ ментору).

## Спринт 3 · Команди, заклади, realtime

### CS-07 · Realtime через SignalR
**Розмір:** M · **Залежить від:** CS-05

**Що зробити**
- `BoardHub` з `[Authorize]` на `/hubs/board`. `JoinBoard(boardId)` перевіряє доступ і додає в групу `board:{boardId}`, `LeaveBoard` прибирає.
- Розсилка з REST-endpoints через `IHubContext<BoardHub>` **після** успішного збереження. Події — таблиця в `API.md`.
- `JwtBearerEvents.OnMessageReceived`: для шляхів `/hubs/...` брати токен із `?access_token=`.
- Перевірити, що YARP прокидає WebSocket (за замовчуванням так).
- Тестова сторінка `wwwroot/board-test.html` (тільки Development): клієнт SignalR із CDN, поле для токена й `boardId`, список подій.

**Готово, коли**
- [ ] Дві вкладки з тестовою сторінкою: переміщення картки через REST в одній миттєво видно в іншій.
- [ ] Без токена до хабу не підключитись.

**Чого навчишся:** WebSocket, SignalR-групи, як автентифікація працює для довгих з'єднань.

### CS-08 · Каркас activity-service
**Розмір:** M · **Залежить від:** CS-04

**Що зробити**
- Проєкт `ProjectHub.Activity`: Dapper + Npgsql, міграції через DbUp (`dbup-postgresql`) зі SQL-скриптів, вбудованих у збірку.
- Таблиці `activity_log`, `contributions`, `project_refs`, `user_refs`, `processed_events`.
- Обробники `user.*`, `project.*`, `board.*` → запис у `activity_log` (payload — `jsonb`) і оновлення `project_refs.last_activity_at`.

**Готово, коли**
- [ ] Будь-яка дія на дошці з'являється в `activity_log` з правильним `project_id` і `actor_id`.

**Чого навчишся:** Dapper і «сирий» SQL, міграції без ORM, `jsonb`.

### CS-09 · Підрахунок внеску
**Розмір:** M · **Залежить від:** CS-08, CS-06

**Що зробити**
- `board.card-completed` → `cards_completed + 1` для `assigneeId` (або `completedBy`, якщо виконавця немає).
- `board.card-reopened` → `- 1`, але не нижче нуля (`GREATEST(cards_completed - 1, 0)`).
- `board.comment-added` → `comments + 1`.
- `project.member-joined` → рядок у `contributions` зі `specialty`.
- Upsert: `INSERT ... ON CONFLICT (user_id, project_id) DO UPDATE SET ...`.
- Запис у `processed_events` і оновлення лічильників — в одній `NpgsqlTransaction`.

**Готово, коли**
- [ ] Тест: та сама подія `card-completed` двічі → лічильник +1.
- [ ] Тест: completed → reopened → completed → лічильник 1.

**Чого навчишся:** атомарні оновлення лічильників, upsert, ідемпотентність на практиці.

## Спринт 4 · Пошук і портфоліо

### CS-10 · API портфоліо і стрічки
**Розмір:** M · **Залежить від:** CS-09

**Що зробити**
- `GET /api/portfolio/{userId}` — підсумки і внесок по кожному проєкту з назвою і статусом (`contributions` JOIN `project_refs`).
- `GET /api/activity/projects/{projectId}/feed` — стрічка з пагінацією, імена авторів з `user_refs`.
- `GET /api/activity/projects/{projectId}/contributors` — таблиця внеску учасників проєкту.
- Формат відповідей — приклади в `API.md`.

**Готово, коли**
- [ ] Відповідь портфоліо збирається одним SQL-запитом, а не циклом запитів (покажіть ментору).
- [ ] Бонус: keyset-пагінація стрічки замість `OFFSET`.

### CS-11 · Автостатус проєкту
**Розмір:** M · **Залежить від:** CS-08

**Що зробити**
- `InactivityJob : BackgroundService` з `PeriodicTimer` (у dev — раз на хвилину, у проді — раз на годину).
- Знаходить `ACTIVE` проєкти з `last_activity_at` старшим за `Activity:InactivityDays` (за замовчуванням 30) → `INACTIVE` + `activity.project-status-changed`.
- Будь-яка нова активність у `INACTIVE` проєкті → одразу `ACTIVE` + подія (в обробнику, а не чекати джобу).
- Час — тільки через `TimeProvider`, ніякого `DateTime.UtcNow` у логіці.

**Готово, коли**
- [ ] Тест з `FakeTimeProvider` (`Microsoft.Extensions.TimeProvider.Testing`): «прокрутили» 31 день → проєкт `INACTIVE`, нова картка → `ACTIVE`.

**Чого навчишся:** фонові задачі, тестування коду, що залежить від часу.

### CS-12 · Захист gateway і дошки
**Розмір:** S · **Залежить від:** CS-01, CS-06

**Що зробити**
- Rate limiting (`AddRateLimiter`): на зміни — 60 запитів на хвилину на користувача (`sub`), на анонімні — за IP. Прив'язка до маршрутів YARP через `RateLimiterPolicy`.
- Обмеження розміру тіла запиту.
- У board: не більше 20 колонок і 1000 карток на дошку, мітки — до 30 символів, не більше 10 на картку.

**Готово, коли**
- [ ] 61-й запит за хвилину → 429 у форматі ProblemDetails.

## Фаза 2 (після MVP)

- **CS-13 · Transactional Outbox** у board і activity.
- **CS-14 · Синхронізація з GitHub Issues** через Octokit.NET: прив'язка дошки до репозиторію, картка ↔ issue, вебхук з перевіркою підпису HMAC SHA-256.
- **CS-15 · Статистика для викладача** по командах одного завдання (у парі з JV-13).
