V7 DEPLOY CHECKLIST
[ ] bot.php at repository root
[ ] Dockerfile used for build (PHP 8.2 + pdo_mysql + mbstring)
[ ] Bothost environment variables set outside GitHub
[ ] MySQL credentials verified and database reachable
[ ] database.sql imported for fresh installation (not required for an existing bot; runtime creates missing tables)
[ ] logs show v7.0.0 banner
[ ] /версия responds with v7.0.0
[ ] /пинг responds
[ ] /help responds
[ ] /staff responds
[ ] /addws tested with explicit ID, Reply and no target in a test chat
[ ] /sysrole 80 tested (sets priority 80 for the author)
[ ] /sysrole ID 80 and Reply /sysrole 80 tested
[ ] /sysban and /sysunban tested on a test user
[ ] /sysmute and /sysunmute tested on a test user
[ ] /syskick and /sysstaff tested
[ ] /report test created; super-access private-message permissions checked
[ ] /reports, /взять, /ответ, /закрыть tested
[ ] /editcmd and /geditcmd tested in a test chat
