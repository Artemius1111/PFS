# activity-service

Внесок кожного учасника, портфоліо, стрічка подій проєкту, автоматичний статус активності.

| | |
|---|---|
| Мова | C# · .NET 10 |
| Ключові бібліотеки | ASP.NET Core, Dapper, Npgsql, DbUp, RabbitMQ.Client |
| Порт | 8084 |
| База даних | `activity_db` (користувач `activity_svc`) |
| Власник | C#-розробник |
| Задачі | CS-08, CS-09, CS-10, CS-11 |

## Події

- **Публікує:** `activity.project-status-changed`
- **Слухає:** `user.*`, `project.*`, `board.*`

## Як запустити

_Заповнити в CS-08._
