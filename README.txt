RAZE RUSSIA VK BOT
===================

Установка на Bothost
1. Распакуйте RAZE-RUSSIA-VK-BOT.zip в папку проекта/бота.
2. Переименуйте config.php.example в config.php.
3. В config.php укажите:
   - токен сообщества VK;
   - ID владельца бота;
   - host/port/database/username/password MySQL.
4. Импортируйте database.sql через phpMyAdmin. CREATE DATABASE внутри файла НЕТ.
5. В настройках сообщества VK включите Callback API / события сообщений
   согласно режиму, который предоставляет ваш хостинг.
6. Укажите callback/endpoint из Bothost, если он предоставлен хостингом.
7. Запустите bot.php либо назначьте его стартовым файлом согласно панели Bothost.

Команды:
!помощь, !пинг, !правила, !роли, !админы, !онлайн, !myid
!мут, !унмут, !кик, !пред, !унварн, !предупреждения, !getwarn
!бан, !унбан, !getban, !getmute
!ник, !сник, !рник, !нлист, !безников
!role, !removerole, !помощник, !модер
!gban, !gunban, !grole, !gm, !removegm, !gms
!admin, !gadmin, !newrole, !delrole
!welcome, !setrules, !delrules, !неактив
!givemoney, !setlog
/report, /reports, /getreport, /getdialog

Примечание:
Для VK API нужны права сообщества, необходимые для чтения сообщений
и управления беседой. Сам бот не хранит токен в database.sql.
