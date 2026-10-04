RAZE RUSSIA VK BOT — FINAL BUILD

Bothost / PHP 8.2 / SQLite / VK Groups Long Poll

INSTALL
1. Replace bot.php.
2. Do NOT delete data/raze.sqlite.
3. Keep VK_TOKEN in Bothost environment.
4. Keep VK_GROUP_ID=241953865, OWNER_IDS=831772755, TZ=Europe/Moscow.

CHECKED/FIXED
- Existing command handlers retained.
- 128 case labels, 128 unique labels.
- No duplicate PHP functions.
- PHP syntax passes.
- !help / !помощь / !команды / !start use a compact button to the RAZE command post.
- !admin / !gadmin = senior administrator role (priority 80).
- VK chat owner/admin roles synchronize on invite events.
- !welcome is sent when a member joins if configured.
- !pin calls messages.pin; !unpin calls messages.unpin.
- SQLite database is preserved.

LIVE LIMITATION
The archive was statically tested here. A real VK API/Long Poll test requires the live token and Bothost runtime, so no claim of live execution is made.
