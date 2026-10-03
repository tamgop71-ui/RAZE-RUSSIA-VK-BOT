RAZE RUSSIA VK BOT — MySQL version

Что изменено:
- SQLite полностью заменён на MySQL/MariaDB.
- База может находиться на ДРУГОМ хостинге.
- Бот подключается к ней по интернету.
- Таблицы создаются автоматически при первом запуске.
- database.sql можно импортировать в уже созданную БД.
- VK_TOKEN, VK_GROUP_ID и OWNER_IDS остаются переменными Bothost.

1. СОЗДАЙ БАЗУ
На хостинге БД создай пустую MySQL/MariaDB базу.
Если CREATE DATABASE запрещён — просто создай базу через панель хостинга и выбери её в phpMyAdmin.

2. ИМПОРТИРУЙ database.sql
Открой phpMyAdmin -> нужная база -> Импорт -> database.sql.
В файле НЕТ CREATE DATABASE.

3. ПОЛУЧИ ДАННЫЕ
Нужны:
MYSQL_HOST
MYSQL_PORT (обычно 3306)
MYSQL_DATABASE
MYSQL_USER
MYSQL_PASSWORD

Важно: MYSQL_HOST — это адрес MySQL-сервера, а не обязательно адрес сайта.
Если хостинг пишет localhost, 127.0.0.1 или внутренний адрес — такой адрес может работать только внутри того же хостинга. Для Bothost нужен внешний доступ к MySQL.

4. BOTHOST ENV
Оставь существующие:
VK_TOKEN=...
VK_GROUP_ID=241953865
OWNER_IDS=831772755
TZ=Europe/Moscow

Добавь:
MYSQL_HOST=адрес_mysql
MYSQL_PORT=3306
MYSQL_DATABASE=имя_базы
MYSQL_USER=пользователь
MYSQL_PASSWORD=пароль

Также поддерживаются альтернативные имена:
DB_HOST, DB_PORT, DB_DATABASE, DB_USER, DB_PASSWORD.

5. СЕТЕВОЙ ДОСТУП
Самое важное: внешний MySQL должен принимать подключения с Bothost.
Если хостинг БД имеет настройку Remote MySQL / Remote connections / Allowed hosts — добавь IP/сеть Bothost согласно инструкции хостинга.
Если внешний доступ запрещён, бот из Bothost к этой БД подключиться не сможет.

6. ЗАПУСК
После сохранения переменных перезапусти контейнер.

В логе должно появиться примерно:
START DB MYSQL HOST=... DB=...
RAZE RUSSIA VK BOT started (Bothost / Long Poll).

Если соединение не удалось:
ERROR: MySQL connection failed: ...

7. DATA
SQLite больше НЕ используется.
Папка /app/data теперь нужна только для bot.log.
База находится на MySQL-хостинге.

ВАЖНО
Не удаляй старую SQLite-базу до проверки новой версии. Эта версия не читает SQLite — если в старой базе были данные, их нужно отдельно переносить в MySQL.
