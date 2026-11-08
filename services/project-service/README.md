# project-service

Навчальні заклади, проєкти, учасники, заявки, ролі «шукаємо», ліміти, пошук.

| | |
|---|---|
| Мова | Java 21 · Spring Boot 4 |
| Ключові бібліотеки | Spring Data JPA, Spring Security (Resource Server), Spring AMQP, Spring Mail, Flyway |
| Порт | 8082 |
| База даних | `project_db` (користувач `project_svc`) |
| Власник | Java-розробник |
| Задачі | JV-05, JV-06, JV-07, JV-08, JV-09, JV-10 |

## Події

- **Публікує:** `project.created`, `project.updated`, `project.archived`, `project.member-joined`, `project.member-left`
- **Слухає:** `user.*`, `activity.project-status-changed`

## Як запустити

_Заповнити в JV-05._
