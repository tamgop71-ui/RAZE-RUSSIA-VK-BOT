RAZE RUSSIA VK BOT — BOTHOST

1) Upload these files to the root of your GitHub repository.
2) In Bothost choose VK + PHP and use the repository branch main.
3) If Bothost offers “Use custom Dockerfile”, enable it. The included Dockerfile starts bot.php with PHP CLI and PDO SQLite.
4) Add environment variables:
VK_TOKEN = token of your VK community
VK_GROUP_ID = numeric ID of the VK community
OWNER_IDS = owner VK ID(s), separated by commas
TZ = Europe/Moscow
5) Start/redeploy the bot.

The bot uses VK Groups Long Poll, so it does not need a domain or callback URL.
The SQLite database is created automatically at data/raze.sqlite on first start.
Do NOT put VK_TOKEN in GitHub.

Commands:
!помощь !пинг !myid !правила !роли !админы !онлайн
!сник !ник !рник
!пред !унварн !мут !унмут
!бан !унбан !кик
!роль !снятьроль

FIX: обработка VK Groups Long Poll message_new учитывает вложенный объект message. Поддерживаются команды с префиксами ! / . и без разницы для help/start/ping/id.
