# Задачі Java-розробника

Сервіси: **identity-service** (порт 8081) і **project-service** (порт 8082).
Стек: Java 21, Spring Boot 4, Spring Security, Spring Data JPA, Spring AMQP, Flyway, PostgreSQL, JUnit 5, Testcontainers.

Перед стартом кожної задачі напишіть ментору її ID і свій план.

> **Spring Boot 4 і старі туторіали.** Більшість статей в інтернеті — про Spring Boot 3. Головні відмінності, на які наткнетесь: Jackson 3 (пакети `tools.jackson.*` замість `com.fasterxml.jackson.*`, хоча анотації лишились у `com.fasterxml.jackson.annotation`), Spring Security 7, Hibernate 7. Якщо приклад із туторіала не компілюється — спершу перевірте, чи не в цьому справа. Якщо потрібна бібліотека ще не підтримує Boot 4 — пишіть ментору, вирішимо разом.

## Спринт 1 · Вхід і перша дошка

### JV-01 · Каркас identity-service
**Розмір:** S · **Залежить від:** SH-02

**Що зробити**
- Згенерувати проєкт через start.spring.io: Web, Security, OAuth2 Client, OAuth2 Resource Server, Data JPA, PostgreSQL Driver, Flyway, Actuator, Validation.
- Підключення до `identity_db` під користувачем `identity_svc`, налаштування через змінні середовища.
- Flyway-міграція `V1__users.sql` з таблицями `users` і `user_skills` (схема в `DATABASE.md`).
- `GET /health` (Actuator з `management.endpoints.web.base-path=/`), springdoc OpenAPI.
- Пакети `api`, `domain`, `infrastructure` (див. `CONVENTIONS.md`).

**Готово, коли**
- [ ] Сервіс стартує, `GET /health` → `UP`, таблиці створені міграцією.
- [ ] Є один тест на Testcontainers, який піднімає PostgreSQL і перевіряє, що контекст стартує.

**Чого навчишся:** структура Spring Boot-проєкту, Flyway, Testcontainers з `@ServiceConnection`.

### JV-02 · Вхід через GitHub
**Розмір:** L · **Залежить від:** JV-01, CS-01 (для перевірки через gateway)

**Що зробити**
- Зареєструвати GitHub OAuth App (GitHub → Settings → Developer settings). Callback URL: `http://localhost:8080/api/auth/callback/github`. Client ID і secret — тільки в `.env`.
- Налаштувати `spring.security.oauth2.client.registration.github` зі scope `read:user,user:email`.
- Шляхи (у Spring Security 7 тільки lambda-стиль конфігурації):
  - `oauth2Login(o -> o.authorizationEndpoint(a -> a.baseUri("/api/auth")) ...)` → вхід стартує з `/api/auth/github`;
  - `.redirectionEndpoint(r -> r.baseUri("/api/auth/callback/*"))` і в `application.yml` `redirect-uri: "{baseUrl}/api/auth/callback/{registrationId}"`.
- `server.forward-headers-strategy=framework`, щоб `{baseUrl}` був адресою gateway, а не `localhost:8081`.
- Власний `AuthenticationSuccessHandler`:
  1. знайти користувача за GitHub `id` (не за логіном!) або створити нового;
  2. оновити логін, ім'я, аватар;
  3. якщо пошта прихована — взяти основну з `GET https://api.github.com/user/emails`;
  4. зберегти GitHub access token зашифрованим (AES-GCM, ключ з `GITHUB_TOKEN_ENCRYPTION_KEY`) у `github_tokens`;
  5. видати refresh-токен (задача JV-03; поки можна заглушку) і зробити redirect на `FRONTEND_URL`.
- Після успішного входу інвалідувати HTTP-сесію: вона потрібна Spring тільки на час OAuth-танцю.

**Готово, коли**
- [ ] Перехід на `http://localhost:8080/api/auth/github` → сторінка GitHub → повернення на `FRONTEND_URL`.
- [ ] Повторний вхід того самого користувача не створює дубль.
- [ ] Користувач, який змінив логін на GitHub, після входу залишається тим самим записом.
- [ ] У базі токен GitHub лежить зашифрованим.

**Чого навчишся:** OAuth 2.0 Authorization Code flow на практиці, Spring Security filter chain, шифрування секретів.

**Підказка ментора:** якщо після колбеку бачите помилку `authorization_request_not_found` — сесія загубилась між запитом і колбеком. Найчастіше причина в тому, що на GitHub і в браузері різні хости (`localhost` проти `127.0.0.1`) або запит пройшов повз gateway.

### JV-03 · Видача і перевірка JWT
**Розмір:** M · **Залежить від:** JV-02

**Що зробити**
- RSA-ключ (2048 біт): у `dev` генерується при старті, якщо файла немає; в інших профілях читається з `JWT_PRIVATE_KEY_PATH`.
- Видача access-токенів через `NimbusJwtEncoder`: RS256, 15 хвилин, claims `sub`, `login`, `iss`, `aud=projecthub`, у заголовку — `kid`.
- `GET /.well-known/jwks.json` (тільки публічна частина ключа!) і `GET /.well-known/openid-configuration` з полями `issuer` і `jwks_uri`.
- Refresh-токени: таблиця `refresh_tokens`, cookie `HttpOnly; SameSite=Lax; Path=/api/auth`, 30 днів, у БД — SHA-256 хеш.
- `POST /api/auth/refresh` з ротацією: старий токен відкликається, видається новий. Якщо прийшов уже відкликаний токен — відкликати **всі** токени користувача (ознака крадіжки).
- `POST /api/auth/logout`.
- Resource Server у самому identity: `/api/users/**` вимагає валідний JWT.
- `POST /api/dev/token` — тільки в профілі `dev` (`@Profile("dev")`): створює або знаходить тестового користувача за логіном і повертає JWT. Цим ендпоінтом користуватиметься C#-розробник.

**Готово, коли**
- [ ] Токен проходить перевірку на jwt.io публічним ключем з JWKS.
- [ ] Повторне використання старого refresh-токена відкликає всю сесію.
- [ ] Поза профілем `dev` `/api/dev/token` повертає 404.
- [ ] C#-розробник підтвердив, що board-service приймає ваші токени.

**Чого навчишся:** як влаштований JWT, асиметричний підпис, ротація refresh-токенів.

## Спринт 2 · Проєкти і події

### JV-04 · Профіль користувача
**Розмір:** S · **Залежить від:** JV-03

**Що зробити**
- `GET /api/users/me`, `PATCH /api/users/me` (`displayName`, `bio`, `skills`), `GET /api/users/{login}`.
- Навички — `@ElementCollection` на таблицю `user_skills`, не більше 15, кожна до 50 символів.
- Валідація через Bean Validation, помилки у форматі ProblemDetails (`spring.mvc.problemdetails.enabled=true` + `@RestControllerAdvice`).
- Відповіді — DTO (`record`), не сутності.

**Готово, коли**
- [ ] Тести через `@WebMvcTest` + `jwt()` з spring-security-test: успіх, 400 на невалідних даних, 401 без токена.

**Чого навчишся:** DTO проти сутностей, валідація, єдиний формат помилок.

### JV-05 · Каркас project-service і проєкти
**Розмір:** M · **Залежить від:** JV-01 (як зразок), JV-03

**Що зробити**
- Новий сервіс за зразком identity. Resource Server: перевірка JWT через `jwk-set-uri` identity.
- Міграції для `institutions`, `projects`, `project_stack`, `project_members`. Окремою міграцією — 2–3 тестові заклади (повний імпорт буде в JV-08).
- `POST /api/projects`, `GET /api/projects/{id}`, `PATCH /api/projects/{id}`, `POST /api/projects/{id}/archive`, `GET /api/projects/mine`.
- При створенні власник автоматично стає учасником з роллю `OWNER`.
- Тільки OWNER може змінювати й архівувати. Перевірка — у доменному сервісі, не в контролері.

**Готово, коли**
- [ ] Чужий користувач отримує 403 на `PATCH` і `archive`.
- [ ] Юніт-тести правил доступу без бази даних.

**Чого навчишся:** проєктування агрегату з дочірніми сутностями в JPA, де живуть бізнес-правила.

### JV-06 · Події: публікація і споживання
**Розмір:** M · **Залежить від:** JV-05, SH-03

**Що зробити**
- Спільний для обох Java-сервісів підхід (можна скопіювати клас, окрема бібліотека поки не потрібна):
  - `EventEnvelope` (record) за форматом з `EVENTS.md`;
  - `EventPublisher` поверх `RabbitTemplate`, який виставляє `message_id`, `type`, `content_type`.
- Оголосити exchange `projecthub.events`, `projecthub.dlx` і свою чергу з DLX як `@Bean`.
- Публікувати **після коміту**: доменна подія Spring → `@TransactionalEventListener(phase = AFTER_COMMIT)` → RabbitMQ.
- identity: `user.registered`, `user.updated`.
- project: `project.created`, `project.updated`, `project.archived`, `project.member-joined` (для власника при створенні).
- project слухає `user.*` → `user_refs`. Приймати як `String`, розбирати конверт вручну, диспетчеризувати за `type`.
- Ідемпотентність: `processed_events` у тій самій транзакції.

**Готово, коли**
- [ ] Після створення проєкту подія видна в панелі RabbitMQ з правильним конвертом.
- [ ] Інтеграційний тест (Testcontainers RabbitMQ + PostgreSQL): та сама подія двічі обробляється один раз.
- [ ] C#-розробник підтвердив, що board-service розбирає ваші події.

**Чого навчишся:** асинхронна взаємодія, ідемпотентність, чому «зберегти і відправити» — не атомарно.

## Спринт 3 · Команди, заклади, realtime

### JV-07 · Учасники, заявки, ролі «шукаємо», ліміти
**Розмір:** L · **Залежить від:** JV-06

**Що зробити**
- Ролі «шукаємо»: `GET/POST/DELETE /api/projects/{id}/open-roles`.
- Заявки: подати, переглянути (OWNER), схвалити, відхилити, свої заявки (`/api/projects/join-requests/mine`). Одна активна заявка на проєкт від користувача.
- Схвалення → запис у `project_members` + `project.member-joined`.
- Вихід і виключення → `project.member-left`.
- Ліміти: не більше 3 власних і 5 приєднань серед проєктів не в статусі `ARCHIVED`. Перевіряти і при подачі заявки, і при схваленні (за цей час користувач міг приєднатися деінде).
- Гонка: два схвалення одночасно можуть обидва пройти перевірку ліміту. Захист — `SELECT pg_advisory_xact_lock(hashtext(:userId))` на початку транзакції.

**Готово, коли**
- [ ] Юніт-тести всіх правил лімітів (без бази).
- [ ] Інтеграційний тест: 6-те приєднання → 422 у форматі ProblemDetails.
- [ ] Бонус: тест, що два паралельні схвалення не перевищують ліміт.

**Чого навчишся:** бізнес-правила, конкурентний доступ, advisory locks.

### JV-08 · Навчальні заклади
**Розмір:** L · **Залежить від:** JV-05

**Що зробити**
- **Імпорт.** Дослідити API реєстру закладів ЄДЕБО (`registry.edbo.gov.ua`). Якщо швидко не виходить — на MVP достатньо JSON-файла з 20–30 закладами вашої області в `src/main/resources/seed/institutions.json`, який завантажується при старті, якщо таблиця порожня. Повний імпорт — окрема задача Фази 2.
- `GET /api/institutions` з пошуком за назвою і регіоном, `GET /api/institutions/{id}`, `GET /api/institutions/mine`.
- **Вступ через пошту:** якщо домен введеної пошти збігається з `email_domain` закладу — 6-значний код (`SecureRandom`), у БД тільки хеш, 15 хвилин, максимум 5 спроб. Лист через `spring-boot-starter-mail` на Mailpit (`localhost:1025`).
- **Вступ через заявку:** якщо домену немає або він не збігається — заявка, яку схвалює TEACHER або ADMIN закладу.
- Першого ADMIN закладу на MVP призначаємо вручну SQL-скриптом — так і запишіть у README сервісу.
- Створювати проєкт можна тільки в закладі, де ти підтверджений учасник.

**Готово, коли**
- [ ] Лист із кодом видно в Mailpit, правильний код додає в заклад, 6-та спроба відхиляється.
- [ ] Не можна створити проєкт у чужому закладі.

**Чого навчишся:** робота з зовнішніми даними, відправка пошти, безпечні одноразові коди.

## Спринт 4 · Пошук і портфоліо

### JV-09 · Пошук проєктів
**Розмір:** M · **Залежить від:** JV-07, JV-08

**Що зробити**
- Міграція: згенерована колонка `search_vector` і GIN-індекс (див. `DATABASE.md`).
- `GET /api/projects/search` і `GET /api/institutions/{id}/projects` з фільтрами: `q`, `stack`, `openRole`, `institutionId`, `status`.
- Запит через `websearch_to_tsquery('simple', :q)`, сортування: спершу `ACTIVE`, потім `ts_rank`, потім `last_activity_at DESC`. Архівовані не показувати, якщо їх не просили явно.
- Пагінація у форматі `{ items, page, size, total }`.
- `search_vector` в сутність не мапити — це native query.

**Готово, коли**
- [ ] `EXPLAIN ANALYZE` показує використання GIN-індексу (покажіть ментору).
- [ ] Неактивний проєкт стоїть нижче за активний з тим самим збігом.

**Чого навчишся:** повнотекстовий пошук у PostgreSQL, індекси, читання плану запиту.

### JV-10 · Статус проєкту з activity-service
**Розмір:** S · **Залежить від:** JV-06, CS-11

**Що зробити**
- Слухати `activity.project-status-changed`: оновлювати `status` і `last_activity_at`.
- Проєкти `ARCHIVED` не чіпати.
- Якщо подія старіша за вже збережений `last_activity_at` — ігнорувати (порядок подій не гарантований).

**Готово, коли**
- [ ] Тест: подія `INACTIVE` зі старшою датою, що прийшла після `ACTIVE`, не перезаписує статус.

### JV-11 · GitHub-репозиторії в портфоліо
**Розмір:** M · **Залежить від:** JV-02

**Що зробити**
- GitHub-клієнт через `RestClient` або декларативний інтерфейс `@HttpExchange` (HTTP Service Clients — нове в Spring Boot 4).
- `GET /api/users/me/github-repos` — публічні репозиторії: назва, посилання, мова, зірки, дата оновлення. Кеш на 10 хвилин.
- `PUT /api/users/me/showcase-repos` — вибрати до 6 репозиторіїв у портфоліо (таблиця `user_showcase_repos`).
- GitHub відповів 401 → `is_valid = false`, клієнту — помилка «увійдіть знову через GitHub». Ліміт запитів GitHub (403/429) — зрозуміла помилка, а не 500.
- Вибрані репозиторії показуються в `GET /api/users/{login}`.

**Готово, коли**
- [ ] Тести з підробленим GitHub (наприклад, WireMock): успіх, 401, 403 з лімітом.

**Чого навчишся:** інтеграція із зовнішнім API, кешування, обробка збоїв чужого сервісу.

## Фаза 2 (після MVP)

- **JV-12 · Transactional Outbox** — події пишуться в таблицю `outbox` у тій самій транзакції, окремий планувальник відправляє їх у RabbitMQ.
- **JV-13 · Кабінет викладача** — викладач створює завдання для групи, проєкти-команди прив'язуються до завдання.
- **JV-14 · Повний імпорт закладів з ЄДЕБО** за розкладом.
