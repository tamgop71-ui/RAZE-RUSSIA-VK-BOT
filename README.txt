RAZE RUSSIA VK BOT - FULL COMMAND BUILD

Bothost:
1. Upload these files to the GitHub repository connected to Bothost.
2. Enable Use custom Dockerfile.
3. Main file: bot.php.
4. Rebuild from Git.
5. Set VK_TOKEN, VK_GROUP_ID, OWNER_IDS and TZ in environment variables.

IMPORTANT:
- Do not send VK_TOKEN to anyone.
- The bot uses Groups Long Poll, no callback URL is required.
- messages.send intentionally does NOT send reply_to.
- SQLite is created in /app/data/raze.sqlite and old database tables are migrated automatically.

The command dispatcher covers the command groups supplied by the project specification. Some VK actions (kick, delete, pin, admin changes) additionally require the community bot to have the corresponding rights in the conversation.
