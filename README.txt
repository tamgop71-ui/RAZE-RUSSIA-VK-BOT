RAZE RUSSIA VK BOT — KICK/BAN FIX

Replace bot.php in GitHub with the new bot.php.
Do not replace data/raze.sqlite.
Then Bothost: Update from Git -> rebuild -> restart.

Important VK permission:
The community must be an administrator of the VK conversation and have permission to manage the conversation/members. Without that VK will return an API error.

Supported target formats:
/кик 123
!kick 123
.kick @id123
,kick vk.com/id123
Reply to a user's message and send: /kick

Ban:
/бан 123 7 причина
!ban 123 7 причина
Reply to a user's message: /ban 7 причина
Ban is stored in SQLite and the user is immediately removed from the VK conversation. VK does not provide a generic permanent chat-ban method through this API; the bot therefore enforces the ban in its own database.
