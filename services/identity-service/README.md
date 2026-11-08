# identity-service

Вхід через GitHub, користувачі, профілі, видача JWT.

| | |
|---|---|
| Мова | Java 21 · Spring Boot 4 |
| Ключові бібліотеки | Spring Security (OAuth2 Client, Resource Server), Spring Data JPA, Spring AMQP, Flyway |
| Порт | 8081 |
| База даних | `identity_db` (користувач `identity_svc`) |
| Власник | Java-розробник |
| Задачі | JV-01, JV-02, JV-03, JV-04, JV-06, JV-11 |

## Події

- **Публікує:** `user.registered`, `user.updated`
- **Слухає:** —

## Як запустити

_Заповнити в JV-01._
