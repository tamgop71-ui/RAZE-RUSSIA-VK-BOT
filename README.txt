RAZE RUSSIA VK BOT — VERIFIED FIX BUILD

Build: ROLE/NICK/CASINO/FIXED-2
Date: 2026-10-03

FIXES VERIFIED:
- Added missing chatMembers() function using messages.getConversationMembers.
- !онлайн no longer crashes with "Call to undefined function chatMembers()".
- !онлайн counts VK online profiles only; it no longer treats every admin as online.
- !staff is now registered in command permissions and works for ordinary chat members.
- !админы and !staff use the same administration list.
- BOT INVITED leadership sync uses chatMembers().
- Added !версия / !version to verify that this build is running.
- Existing role/nickname remove buttons and casino repeat button are preserved.

INSTALL:
1. Replace the project files in Bothost with this archive.
2. Keep the existing environment variables, especially VK_TOKEN and MySQL settings.
3. Rebuild/redeploy the container from the repository or upload this project.
4. Restart the bot.
5. Test in VK: !версия, !staff, !админы, !онлайн, !казино 100.

Do not put VK_TOKEN or MYSQL_PASSWORD into this archive. Use Bothost environment variables.
