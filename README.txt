RAZE RUSSIA VK BOT v3.1.0
==========================

ГОТОВАЯ ВЕРСИЯ ДЛЯ BOTHOST + GITHUB + PHP 8.2 + MYSQL.

КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ
------------------------
В этой версии НЕТ keyboard вообще.
В этой версии НЕТ reply_to вообще.
messages.send отправляет только peer_id + random_id + message.

Ошибка из старой версии:
error_code 911 / "Keyboard format is invalid: inline property should be boolean"
исключена из кода.

VK в API 5.199 требует boolean для поля keyboard.inline; мы вообще не используем
keyboard, чтобы команды не зависели от формата клавиатуры.

УСТАНОВКА С НУЛЯ
----------------
1. Удали старый bot.php из GitHub-репозитория.
2. Залей НОВЫЙ bot.php из этого архива.
3. Импортируй database.sql в НОВУЮ MySQL БД.
4. В Bothost укажи репозиторий и ветку main.
5. Команда запуска: php bot.php
6. Перезапусти/Rebuild контейнер.

ВАЖНО: не смешивай этот bot.php со старым файлом. Старый файл мог содержать
keyboard и именно он даёт ошибку 911.

ENV
---
MYSQL_DATABASE = имя БД
MYSQL_HOST     = адрес MySQL
MYSQL_PASSWORD = пароль MySQL
MYSQL_PORT     = 3306
MYSQL_USER     = пользователь MySQL
OWNER_IDS      = 831772755
VK_GROUP_ID    = 241953865
VK_TOKEN       = токен сообщества
TZ             = Europe/Moscow

VK_TOKEN и MYSQL_PASSWORD не загружать в GitHub.

ПРОВЕРКА ПОСЛЕ ЗАПУСКА
-----------------------
В логах первая строка должна быть:
=== RAZE RUSSIA VK BOT v3.1.0 | MYSQL | NO KEYBOARD | NO REPLY_TO ===

Затем:
RAZE RUSSIA VK BOT FULL BUILD started.
VK group: RAZE RUSSIA: чат-менеджер (#241953865)
Long Poll: message_new enabled

ПЕРВЫЕ КОМАНДЫ
--------------
/help
/staff
/myid
/thereid
/admin 123456789
/staff
/sysrole 123456789 100
/sysstaff

ПОДДЕРЖКА
---------
Команды принимаются с !, / или .
Например:
!help
/help
.help
!помощь
/команды

Также убирается суффикс VK вида @club...

НЕ ПЕРЕДАВАЙ МНЕ ТОКЕН
-----------------------
Если нужны дальнейшие исправления, достаточно прислать лог Bothost.
Токен не нужен.
