RAZE RUSSIA VK BOT v4.0.0

1. Upload bot.php to the repository root.
2. Import database.sql into the MySQL database, or let bot.php create missing tables if the DB user has CREATE permission.
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
- The help button uses inline=true as a real boolean.
- Help button opens: https://vk.ru/@-241953865-cmd
- Commands accept !, / and . prefixes, repeated prefixes, full-width punctuation, and VK @club suffixes.

EXPECTED STARTUP LOG:
=== RAZE RUSSIA VK BOT v4.0.0 | MYSQL | HELP BUTTON | ROBUST COMMAND PARSER ===
RAZE RUSSIA VK BOT v4.0.0 started.
