# board-service

Канбан-дошки проєктів: колонки, картки, коментарі, оновлення в реальному часі.

| | |
|---|---|
| Мова | C# · .NET 10 |
| Ключові бібліотеки | ASP.NET Core Minimal API, SignalR, EF Core + Npgsql, RabbitMQ.Client |
| Порт | 8083 |
| База даних | `board_db` (користувач `board_svc`) |
| Власник | C#-розробник |
| Задачі | CS-03, CS-05, CS-06, CS-07 |

## Події

- **Публікує:** `board.card-created`, `board.card-moved`, `board.card-completed`, `board.card-reopened`, `board.comment-added`
- **Слухає:** `user.*`, `project.*`

## Як запустити

_Заповнити в CS-03._
