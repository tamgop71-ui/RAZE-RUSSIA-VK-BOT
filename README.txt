RAZE RUSSIA VK BOT v5.0.0

1. Upload bot.php to the repository root.
2. Keep/import the existing database.sql. bot.php also creates missing tables when the MySQL user has CREATE permission.
3. Bothost environment variables:
   VK_TOKEN=your VK group token
   VK_GROUP_ID=241953865
   OWNER_IDS=831772755
   TZ=Europe/Moscow
   MYSQL_HOST=...
   MYSQL_DATABASE=...
   MYSQL_USER=...
   MYSQL_PASSWORD=...
   MYSQL_PORT=3306
4. Start command:
   php bot.php

IMPORTANT:
- Do not put VK_TOKEN or MYSQL_PASSWORD into GitHub.
- PHP 8.2+ and pdo_mysql are required.
- Help button uses inline=true and opens https://vk.ru/@-241953865-cmd
- Every user name produced by nameOf() is a clickable VK mention: [id123|Name].
- If a command needs a target and there is no reply/explicit VK ID, the target defaults to the command author.
- For commands with arguments, explicit target detection is kept separate so arguments are not shifted incorrectly.
- Outgoing messages normalize literal \\n, /n, and control characters so users do not see formatting artifacts.
- Commands accept !, / and . prefixes, repeated prefixes, full-width punctuation, zero-width characters and VK @club suffixes.

EXPECTED STARTUP LOG:
=== RAZE RUSSIA VK BOT v5.0.0 | MYSQL | VK LINKS | TARGET FALLBACK | CLEAN MESSAGES ===
RAZE RUSSIA VK BOT v5.0.0 started.
