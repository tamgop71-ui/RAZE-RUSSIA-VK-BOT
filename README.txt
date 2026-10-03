RAZE RUSSIA BOT — SimpleVK 3 / Bothost

Что изменено:
- Транспорт VK Groups Long Poll переведён на SimpleVK 3.
- SimpleVK устанавливается Composer автоматически при Docker-сборке.
- PHP 8.2 + SQLite.
- Сохранена существующая БД data/raze.sqlite.
- messages.send НЕ использует reply_to.
- /kick, /ban, /mute, /warn и английские алиасы поддерживаются.
- /sysrole доступна только OWNER_IDS и выдаёт superuser-доступ.
- Старые команды и структура БД перенесены из предыдущей версии.

ENV в Bothost:
VK_TOKEN=новый токен сообщества
VK_GROUP_ID=241953865
OWNER_IDS=831772755
TZ=Europe/Moscow

ВАЖНО:
Не загружайте data/raze.sqlite в GitHub. Если база уже есть в контейнере Bothost — не удаляйте /app/data.

Запуск:
1. Commit всех файлов в GitHub.
2. Bothost -> Update from Git.
3. Rebuild/пересборка контейнера.
4. Restart/запуск.
5. В логах должно быть:
   === RAZE RUSSIA BOT / SimpleVK 3 ===
   SimpleVK Long Poll transport enabled.

Команды проверки:
!пинг
!myid
/sysrole
/kick ID
/ban ID 7 причина
/mute ID 10 причина
/warn ID причина

Для kick/ban сообщество должно иметь права управления участниками беседы.
