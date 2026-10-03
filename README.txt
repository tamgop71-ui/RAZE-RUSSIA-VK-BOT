RAZE RUSSIA VK BOT — CLEAN MYSQL BUILD

1. Import database.sql into your existing MySQL/MariaDB database. Do NOT add CREATE DATABASE.
2. Upload the project to GitHub/Bothost.
3. Set environment variables:
   VK_TOKEN=your VK community token
   VK_GROUP_ID=241953865
   OWNER_IDS=831772755
   TZ=Europe/Moscow
   MYSQL_HOST=your remote MySQL host
   MYSQL_PORT=3306
   MYSQL_DATABASE=your database name
   MYSQL_USER=your database user
   MYSQL_PASSWORD=your database password
4. Start the container.

The bot requires PHP 8.2+ with pdo_mysql.
The bot creates/updates its tables automatically and writes runtime diagnostics to data/bot.log.
Never put the VK token or database password into GitHub files.
