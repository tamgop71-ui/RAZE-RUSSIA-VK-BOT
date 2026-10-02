<?php
declare(strict_types=1);

/*
 * RAZE RUSSIA VK BOT
 * Bothost / VK Groups Long Poll
 * FIX: messages.send НЕ использует reply_to
 */

fwrite(STDOUT, "=== RAZE RUSSIA BOT V5 - NO REPLY_TO ===\n");

$token = trim((string)getenv('VK_TOKEN'));
$groupId = (int)getenv('VK_GROUP_ID');

$ownerIds = array_values(
    array_filter(
        array_map(
            'intval',
            preg_split('/[,;\s]+/', trim((string)getenv('OWNER_IDS')) ?: '')
        )
    )
);

date_default_timezone_set(
    trim((string)getenv('TZ')) ?: 'Europe/Moscow'
);

if ($token === '' || $groupId <= 0) {
    fwrite(STDERR, "ERROR: VK_TOKEN or VK_GROUP_ID is not configured\n");
    exit(1);
}

if (!extension_loaded('pdo_sqlite')) {
    fwrite(STDERR, "ERROR: pdo_sqlite extension is not loaded\n");
    exit(1);
}

/*
|--------------------------------------------------------------------------
| VK API
|--------------------------------------------------------------------------
*/

function vk(string $method, array $params = []): array
{
    global $token;

    $params['access_token'] = $token;
    $params['v'] = '5.199';

    $url = 'https://api.vk.com/method/' .
        $method .
        '?' .
        http_build_query($params);

    $context = stream_context_create([
        'http' => [
            'timeout' => 35,
            'ignore_errors' => true
        ]
    ]);

    $response = @file_get_contents(
        $url,
        false,
        $context
    );

    if ($response === false) {
        return [
            'error' => [
                'error_msg' => 'VK API request failed'
            ]
        ];
    }

    $json = json_decode($response, true);

    if (!is_array($json)) {
        return [
            'error' => [
                'error_msg' => 'Invalid VK API response'
            ]
        ];
    }

    return $json;
}

/*
|--------------------------------------------------------------------------
| SEND MESSAGE
|--------------------------------------------------------------------------
|
| ВАЖНО:
| Здесь НЕТ reply_to.
|
*/

function sendMessage(int $peerId, string $message): bool
{
    $params = [
        'peer_id' => $peerId,
        'random_id' => random_int(
            -2147483648,
            2147483647
        ),
        'message' => $message
    ];

    $result = vk('messages.send', $params);

    if (isset($result['error'])) {
        fwrite(
            STDERR,
            "SEND ERROR: " .
            json_encode(
                $result['error'],
                JSON_UNESCAPED_UNICODE
            ) .
            "\n"
        );

        return false;
    }

    fwrite(
        STDOUT,
        "SENT to {$peerId}, message_id=" .
        ($result['response'] ?? 'unknown') .
        "\n"
    );

    return true;
}

/*
|--------------------------------------------------------------------------
| STARTUP CHECK
|--------------------------------------------------------------------------
*/

function startupCheck(): void
{
    global $groupId;

    $result = vk(
        'groups.getById',
        [
            'group_id' => $groupId
        ]
    );

    if (isset($result['error'])) {
        fwrite(
            STDERR,
            "VK getById ERROR: " .
            json_encode(
                $result['error'],
                JSON_UNESCAPED_UNICODE
            ) .
            "\n"
        );

        return;
    }

    $group = $result['response']['groups'][0] ?? [];

    fwrite(
        STDOUT,
        "VK group: " .
        ($group['name'] ?? 'unknown') .
        " (#{$groupId})\n"
    );

    $settings = vk(
        'groups.setLongPollSettings',
        [
            'group_id' => $groupId,
            'api_version' => '5.199',

            'enabled' => 1,

            'message_new' => 1,
            'message_reply' => 0,
            'message_allow' => 0,
            'message_deny' => 0,
            'message_edit' => 0,
            'message_event' => 0,
            'message_typing_state' => 0,

            'message_reaction_event' => 0,
            'message_reaction_new' => 0,
            'message_reaction_remove' => 0
        ]
    );

    if (isset($settings['error'])) {
        fwrite(
            STDERR,
            "Long Poll settings ERROR: " .
            json_encode(
                $settings['error'],
                JSON_UNESCAPED_UNICODE
            ) .
            "\n"
        );
    } else {
        fwrite(
            STDOUT,
            "Long Poll: message_new enabled\n"
        );
    }
}

/*
|--------------------------------------------------------------------------
| DATABASE
|--------------------------------------------------------------------------
*/

$dbPath = __DIR__ . '/data/raze.sqlite';

if (!is_dir(dirname($dbPath))) {
    mkdir(
        dirname($dbPath),
        0775,
        true
    );
}

$pdo = new PDO(
    'sqlite:' . $dbPath,
    null,
    null,
    [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
    ]
);

$pdo->exec('PRAGMA journal_mode=WAL');
$pdo->exec('PRAGMA busy_timeout=5000');

$pdo->exec("
CREATE TABLE IF NOT EXISTS roles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    priority INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS chat_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    role_id INTEGER NOT NULL DEFAULT 1,
    nickname TEXT,
    immunity INTEGER NOT NULL DEFAULT 0,
    last_seen TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(peer_id,user_id)
);

CREATE TABLE IF NOT EXISTS chat_settings (
    peer_id INTEGER PRIMARY KEY,
    rules TEXT,
    welcome TEXT,
    silence_until TEXT,
    games_enabled INTEGER NOT NULL DEFAULT 0,
    automod_enabled INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS warnings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    moderator_id INTEGER NOT NULL,
    reason TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    moderator_id INTEGER NOT NULL,
    days INTEGER NOT NULL,
    reason TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TEXT
);

CREATE TABLE IF NOT EXISTS mutes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    moderator_id INTEGER NOT NULL,
    minutes INTEGER NOT NULL,
    reason TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TEXT
);

CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id INTEGER NOT NULL,
    actor_id INTEGER NOT NULL,
    target_id INTEGER,
    action TEXT NOT NULL,
    details TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS nicknames (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    nickname TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(peer_id,user_id)
);

CREATE TABLE IF NOT EXISTS reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    text TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS report_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    text TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
");

$pdo->exec("
INSERT OR IGNORE INTO roles(id,name,priority)
VALUES
(1,'Участник',0),
(2,'Помощник',20),
(3,'Модератор',40),
(4,'Администратор',60),
(5,'Ст. администратор',80),
(6,'Владелец',100)
");

/*
|--------------------------------------------------------------------------
| DATABASE FUNCTIONS
|--------------------------------------------------------------------------
*/

function ensureUser(
    PDO $pdo,
    int $peerId,
    int $userId
): void {
    $stmt = $pdo->prepare("
        INSERT INTO chat_users(
            peer_id,
            user_id,
            role_id
        )
        VALUES(?,?,1)

        ON CONFLICT(peer_id,user_id)
        DO UPDATE SET
            last_seen=CURRENT_TIMESTAMP
    ");

    $stmt->execute([
        $peerId,
        $userId
    ]);
}

function getPriority(
    PDO $pdo,
    int $peerId,
    int $userId
): int {
    $stmt = $pdo->prepare("
        SELECT r.priority
        FROM chat_users u
        JOIN roles r ON r.id=u.role_id
        WHERE u.peer_id=?
          AND u.user_id=?
    ");

    $stmt->execute([
        $peerId,
        $userId
    ]);

    return (int)($stmt->fetchColumn() ?: 0);
}

function logAction(
    PDO $pdo,
    int $peerId,
    int $actorId,
    ?int $targetId,
    string $action,
    string $details = ''
): void {
    $stmt = $pdo->prepare("
        INSERT INTO logs(
            peer_id,
            actor_id,
            target_id,
            action,
            details
        )
        VALUES(?,?,?,?,?)
    ");

    $stmt->execute([
        $peerId,
        $actorId,
        $targetId,
        $action,
        $details
    ]);
}

function expirePunishments(PDO $pdo): void
{
    $pdo->exec("
        UPDATE bans
        SET active=0
        WHERE active=1
          AND expires_at IS NOT NULL
          AND expires_at<=datetime('now')
    ");

    $pdo->exec("
        UPDATE mutes
        SET active=0
        WHERE active=1
          AND expires_at IS NOT NULL
          AND expires_at<=datetime('now')
    ");
}

/*
|--------------------------------------------------------------------------
| COMMAND PARSER
|--------------------------------------------------------------------------
*/

function parseCommand(string $text): array
{
    $text = trim($text);

    if ($text === '') {
        return ['', []];
    }

    /*
     * Поддержка:
     *
     * /ping
     * !ping
     * .ping
     * ping
     */

    $text = preg_replace(
        '/^[!\/.]+/u',
        '',
        $text
    );

    $parts = preg_split(
        '/\s+/u',
        $text
    );

    $command = mb_strtolower(
        (string)array_shift($parts)
    );

    return [
        $command,
        $parts
    ];
}

/*
|--------------------------------------------------------------------------
| TARGET USER
|--------------------------------------------------------------------------
*/

function getTarget(
    array $message,
    array $args
): ?int {

    /*
     * Ответ на сообщение.
     */

    if (
        isset($message['reply_message']) &&
        is_array($message['reply_message']) &&
        isset($message['reply_message']['from_id'])
    ) {
        return abs(
            (int)$message['reply_message']['from_id']
        );
    }

    /*
     * [id123|Имя]
     */

    if (
        !empty($args[0]) &&
        preg_match(
            '/^\[id(\d+)\|/i',
            $args[0],
            $matches
        )
    ) {
        return (int)$matches[1];
    }

    /*
     * Просто ID.
     */

    if (
        !empty($args[0]) &&
        preg_match(
            '/^(?:id)?(\d+)$/i',
            $args[0],
            $matches
        )
    ) {
        return (int)$matches[1];
    }

    return null;
}

/*
|--------------------------------------------------------------------------
| MESSAGE HANDLER
|--------------------------------------------------------------------------
*/

function handleMessage(
    PDO $pdo,
    array $message
): void {

    global $ownerIds;

    $peerId = (int)(
        $message['peer_id'] ?? 0
    );

    $fromId = (int)(
        $message['from_id'] ?? 0
    );

    $text = trim(
        (string)(
            $message['text'] ?? ''
        )
    );

    fwrite(
        STDOUT,
        "EVENT message_new " .
        "peer={$peerId} " .
        "from={$fromId} " .
        "text=" .
        json_encode(
            $text,
            JSON_UNESCAPED_UNICODE
        ) .
        "\n"
    );

    if ($peerId <= 0 || $fromId <= 0) {
        return;
    }

    ensureUser(
        $pdo,
        $peerId,
        $fromId
    );

    expirePunishments($pdo);

    [
        $command,
        $args
    ] = parseCommand($text);

    if ($command === '') {
        return;
    }

    /*
     * Уровень пользователя.
     */

    $level = getPriority(
        $pdo,
        $peerId,
        $fromId
    );

    /*
     * OWNER_IDS всегда получает уровень 100.
     */

    if (
        in_array(
            $fromId,
            $ownerIds,
            true
        )
    ) {
        $level = 100;
    }

    /*
     * Минимальные права.
     */

    $required = [

        'пинг' => 0,
        'ping' => 0,

        'myid' => 0,
        'id' => 0,

        'помощь' => 0,
        'help' => 0,
        'start' => 0,
        'команды' => 0,
        'commands' => 0,

        'правила' => 0,
        'rules' => 0,

        'роли' => 0,
        'roles' => 0,

        'админы' => 0,
        'admins' => 0,

        'онлайн' => 0,
        'online' => 0,

        'сник' => 20,
        'ник' => 20,
        'рник' => 20,

        'пред' => 20,
        'варн' => 20,
        'унварн' => 20,

        'мут' => 20,
        'унмут' => 20,

        'кик' => 20,

        'бан' => 40,
        'унбан' => 40,

        'роль' => 60,
        'снятьроль' => 60
    ];

    if (!isset($required[$command])) {
        return;
    }

    if (
        $level <
        $required[$command]
    ) {
        sendMessage(
            $peerId,
            '❌ Недостаточно прав.'
        );

        return;
    }

    /*
     * НЕ используем conversation_message_id.
     * НЕ используем reply_to.
     */

    switch ($command) {

        /*
         * PING
         */

        case 'пинг':
        case 'ping':

            sendMessage(
                $peerId,
                '🏓 RAZE RUSSIA BOT: онлайн'
            );

            break;

        /*
         * MY ID
         */

        case 'myid':
        case 'id':

            sendMessage(
                $peerId,
                "🆔 Ваш VK ID: {$fromId}"
            );

            break;

        /*
         * HELP
         */

        case 'помощь':
        case 'help':
        case 'start':
        case 'команды':
        case 'commands':

            sendMessage(
                $peerId,
                "RAZE RUSSIA — команды\n\n" .
                "/ping\n" .
                "/myid\n" .
                "/помощь\n" .
                "/правила\n" .
                "/роли\n" .
                "/админы\n" .
                "/онлайн\n\n" .
                "Администрация:\n" .
                "/сник\n" .
                "/ник\n" .
                "/рник\n" .
                "/пред\n" .
                "/унварн\n" .
                "/мут\n" .
                "/унмут\n" .
                "/бан\n" .
                "/унбан\n" .
                "/кик\n" .
                "/роль\n" .
                "/снятьроль"
            );

            break;

        /*
         * ONLINE
         */

        case 'онлайн':
        case 'online':

            sendMessage(
                $peerId,
                '🟢 Бот онлайн.'
            );

            break;

        /*
         * ROLES
         */

        case 'роли':
        case 'roles':

            $rows = $pdo
                ->query("
                    SELECT name,priority
                    FROM roles
                    ORDER BY priority DESC
                ")
                ->fetchAll();

            $result = "👑 Роли:\n";

            foreach ($rows as $row) {
                $result .=
                    "• " .
                    $row['name'] .
                    " — " .
                    $row['priority'] .
                    "\n";
            }

            sendMessage(
                $peerId,
                $result
            );

            break;

        /*
         * ADMINS
         */

        case 'админы':
        case 'admins':

            $stmt = $pdo->prepare("
                SELECT
                    u.user_id,
                    r.name
                FROM chat_users u
                JOIN roles r
                    ON r.id=u.role_id
                WHERE u.peer_id=?
                  AND r.priority>0
                ORDER BY r.priority DESC
            ");

            $stmt->execute([
                $peerId
            ]);

            $result =
                "👮 Администрация:\n";

            foreach ($stmt as $row) {

                $result .=
                    "• [id" .
                    $row['user_id'] .
                    "|VK " .
                    $row['user_id'] .
                    "] — " .
                    $row['name'] .
                    "\n";
            }

            sendMessage(
                $peerId,
                $result
            );

            break;

        /*
         * RULES
         */

        case 'правила':
        case 'rules':

            $stmt = $pdo->prepare("
                SELECT rules
                FROM chat_settings
                WHERE peer_id=?
            ");

            $stmt->execute([
                $peerId
            ]);

            $rules =
                (string)(
                    $stmt->fetchColumn()
                    ?: 'Правила ещё не настроены.'
                );

            sendMessage(
                $peerId,
                $rules
            );

            break;

        /*
         * NICK
         */

        case 'сник':
        case 'ник':

            $targetId = getTarget(
                $message,
                $args
            );

            if ($targetId) {
                $nickname = trim(
                    implode(
                        ' ',
                        array_slice(
                            $args,
                            1
                        )
                    )
                );
            } else {
                $targetId = $fromId;

                $nickname = trim(
                    implode(
                        ' ',
                        $args
                    )
                );
            }

            if ($nickname === '') {

                sendMessage(
                    $peerId,
                    'Использование: /сник Ник'
                );

                break;
            }

            $stmt = $pdo->prepare("
                INSERT INTO nicknames(
                    peer_id,
                    user_id,
                    nickname
                )
                VALUES(?,?,?)

                ON CONFLICT(peer_id,user_id)
                DO UPDATE SET
                    nickname=excluded.nickname
            ");

            $stmt->execute([
                $peerId,
                $targetId,
                $nickname
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'nickname',
                $nickname
            );

            sendMessage(
                $peerId,
                "✅ Ник установлен: {$nickname}"
            );

            break;

        /*
         * REMOVE NICK
         */

        case 'рник':

            $targetId =
                getTarget(
                    $message,
                    $args
                ) ?? $fromId;

            $stmt = $pdo->prepare("
                DELETE FROM nicknames
                WHERE peer_id=?
                  AND user_id=?
            ");

            $stmt->execute([
                $peerId,
                $targetId
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'remove_nickname'
            );

            sendMessage(
                $peerId,
                '✅ Ник удалён.'
            );

            break;

        /*
         * WARN
         */

        case 'пред':
        case 'варн':

            $targetId =
                getTarget(
                    $message,
                    $args
                );

            if ($targetId) {
                $reason =
                    trim(
                        implode(
                            ' ',
                            array_slice(
                                $args,
                                1
                            )
                        )
                    );
            } else {
                $targetId = $fromId;

                $reason =
                    trim(
                        implode(
                            ' ',
                            $args
                        )
                    );
            }

            if ($reason === '') {
                $reason = 'Без причины';
            }

            $stmt = $pdo->prepare("
                INSERT INTO warnings(
                    peer_id,
                    user_id,
                    moderator_id,
                    reason
                )
                VALUES(?,?,?,?)
            ");

            $stmt->execute([
                $peerId,
                $targetId,
                $fromId,
                $reason
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'warn',
                $reason
            );

            sendMessage(
                $peerId,
                "⚠️ Предупреждение выдано.\n" .
                "Причина: {$reason}"
            );

            break;

        /*
         * UNWARN
         */

        case 'унварн':

            $targetId =
                getTarget(
                    $message,
                    $args
                ) ?? $fromId;

            $stmt = $pdo->prepare("
                UPDATE warnings
                SET active=0
                WHERE peer_id=?
                  AND user_id=?
                  AND active=1
            ");

            $stmt->execute([
                $peerId,
                $targetId
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'unwarn'
            );

            sendMessage(
                $peerId,
                '✅ Предупреждения сняты.'
            );

            break;

        /*
         * MUTE
         */

        case 'мут':

            $targetId =
                getTarget(
                    $message,
                    $args
                );

            if (!$targetId) {

                sendMessage(
                    $peerId,
                    'Использование: /мут [id] [минуты] [причина] или ответом на сообщение.'
                );

                break;
            }

            $minutes =
                (int)(
                    $args[1] ?? 0
                );

            if ($minutes <= 0) {

                sendMessage(
                    $peerId,
                    'Укажи количество минут.'
                );

                break;
            }

            $reason = trim(
                implode(
                    ' ',
                    array_slice(
                        $args,
                        2
                    )
                )
            );

            if ($reason === '') {
                $reason = 'Без причины';
            }

            $expires =
                date(
                    'Y-m-d H:i:s',
                    time() +
                    ($minutes * 60)
                );

            $stmt = $pdo->prepare("
                INSERT INTO mutes(
                    peer_id,
                    user_id,
                    moderator_id,
                    minutes,
                    reason,
                    expires_at
                )
                VALUES(?,?,?,?,?,?)
            ");

            $stmt->execute([
                $peerId,
                $targetId,
                $fromId,
                $minutes,
                $reason,
                $expires
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'mute',
                $reason
            );

            sendMessage(
                $peerId,
                "🔇 Мут на {$minutes} мин.\n" .
                "До: {$expires}"
            );

            break;

        /*
         * UNMUTE
         */

        case 'унмут':

            $targetId =
                getTarget(
                    $message,
                    $args
                ) ?? $fromId;

            $stmt = $pdo->prepare("
                UPDATE mutes
                SET active=0
                WHERE peer_id=?
                  AND user_id=?
                  AND active=1
            ");

            $stmt->execute([
                $peerId,
                $targetId
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'unmute'
            );

            sendMessage(
                $peerId,
                '🔊 Мут снят.'
            );

            break;

        /*
         * BAN
         */

        case 'бан':

            $targetId =
                getTarget(
                    $message,
                    $args
                );

            if (!$targetId) {

                sendMessage(
                    $peerId,
                    'Использование: /бан [id] [дни] [причина] или ответом на сообщение.'
                );

                break;
            }

            $days =
                (int)(
                    $args[1] ?? 0
                );

            if ($days <= 0) {

                sendMessage(
                    $peerId,
                    'Укажи количество дней.'
                );

                break;
            }

            $reason = trim(
                implode(
                    ' ',
                    array_slice(
                        $args,
                        2
                    )
                )
            );

            if ($reason === '') {
                $reason = 'Без причины';
            }

            $expires =
                date(
                    'Y-m-d H:i:s',
                    time() +
                    ($days * 86400)
                );

            $stmt = $pdo->prepare("
                INSERT INTO bans(
                    peer_id,
                    user_id,
                    moderator_id,
                    days,
                    reason,
                    expires_at
                )
                VALUES(?,?,?,?,?,?)
            ");

            $stmt->execute([
                $peerId,
                $targetId,
                $fromId,
                $days,
                $reason,
                $expires
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'ban',
                $reason
            );

            sendMessage(
                $peerId,
                "🔨 Бан на {$days} дн.\n" .
                "До: {$expires}\n" .
                "Причина: {$reason}"
            );

            break;

        /*
         * UNBAN
         */

        case 'унбан':

            $targetId =
                getTarget(
                    $message,
                    $args
                ) ?? $fromId;

            $stmt = $pdo->prepare("
                UPDATE bans
                SET active=0
                WHERE peer_id=?
                  AND user_id=?
                  AND active=1
            ");

            $stmt->execute([
                $peerId,
                $targetId
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'unban'
            );

            sendMessage(
                $peerId,
                '✅ Бан снят.'
            );

            break;

        /*
         * KICK
         */

        case 'кик':

            $targetId =
                getTarget(
                    $message,
                    $args
                );

            if (!$targetId) {

                sendMessage(
                    $peerId,
                    'Укажи ID или ответь на сообщение.'
                );

                break;
            }

            $chatId =
                $peerId - 2000000000;

            $result = vk(
                'messages.removeChatUser',
                [
                    'chat_id' => $chatId,
                    'member_id' => $targetId
                ]
            );

            if (isset($result['response'])) {

                logAction(
                    $pdo,
                    $peerId,
                    $fromId,
                    $targetId,
                    'kick'
                );

                sendMessage(
                    $peerId,
                    '👢 Пользователь исключён.'
                );

            } else {

                sendMessage(
                    $peerId,
                    '❌ VK: ' .
                    (
                        $result['error']['error_msg']
                        ?? 'ошибка'
                    )
                );
            }

            break;

        /*
         * ROLE
         */

        case 'роль':

            $targetId =
                getTarget(
                    $message,
                    $args
                );

            if (!$targetId) {

                sendMessage(
                    $peerId,
                    'Укажи ID или ответь на сообщение.'
                );

                break;
            }

            $roleName = trim(
                implode(
                    ' ',
                    array_slice(
                        $args,
                        1
                    )
                )
            );

            if ($roleName === '') {

                sendMessage(
                    $peerId,
                    'Укажи роль.'
                );

                break;
            }

            $stmt = $pdo->prepare("
                SELECT id,priority
                FROM roles
                WHERE name=?
            ");

            $stmt->execute([
                $roleName
            ]);

            $role = $stmt->fetch();

            if (!$role) {

                sendMessage(
                    $peerId,
                    '❌ Такой роли нет.'
                );

                break;
            }

            if (
                $level <=
                (int)$role['priority']
            ) {

                sendMessage(
                    $peerId,
                    '❌ Нельзя выдать роль, равную или выше своей.'
                );

                break;
            }

            $stmt = $pdo->prepare("
                INSERT INTO chat_users(
                    peer_id,
                    user_id,
                    role_id
                )
                VALUES(?,?,?)

                ON CONFLICT(peer_id,user_id)
                DO UPDATE SET
                    role_id=excluded.role_id
            ");

            $stmt->execute([
                $peerId,
                $targetId,
                $role['id']
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'role',
                $roleName
            );

            sendMessage(
                $peerId,
                "👑 Роль {$roleName} выдана."
            );

            break;

        /*
         * REMOVE ROLE
         */

        case 'снятьроль':

            $targetId =
                getTarget(
                    $message,
                    $args
                ) ?? $fromId;

            $stmt = $pdo->prepare("
                UPDATE chat_users
                SET role_id=1
                WHERE peer_id=?
                  AND user_id=?
            ");

            $stmt->execute([
                $peerId,
                $targetId
            ]);

            logAction(
                $pdo,
                $peerId,
                $fromId,
                $targetId,
                'remove_role'
            );

            sendMessage(
                $peerId,
                '✅ Роль снята.'
            );

            break;
    }
}

/*
|--------------------------------------------------------------------------
| LONG POLL
|--------------------------------------------------------------------------
*/

function getLongPollServer(): array
{
    global $groupId;

    for ($i = 0; $i < 5; $i++) {

        $result = vk(
            'groups.getLongPollServer',
            [
                'group_id' => $groupId
            ]
        );

        if (isset($result['response'])) {
            return $result['response'];
        }

        sleep(2);
    }

    throw new RuntimeException(
        'Cannot get VK Long Poll server'
    );
}

/*
|--------------------------------------------------------------------------
| START
|--------------------------------------------------------------------------
*/

fwrite(
    STDOUT,
    "RAZE RUSSIA VK BOT V5 started - NO REPLY_TO.\n"
);

startupCheck();

/*
|--------------------------------------------------------------------------
| MAIN LOOP
|--------------------------------------------------------------------------
*/

while (true) {

    try {

        $serverData =
            getLongPollServer();

        $key =
            $serverData['key'];

        $server =
            $serverData['server'];

        $ts =
            $serverData['ts'];

        while (true) {

            $url =
                $server .
                '?act=a_check' .
                '&key=' .
                rawurlencode($key) .
                '&wait=25' .
                '&ts=' .
                rawurlencode($ts);

            $context =
                stream_context_create([
                    'http' => [
                        'timeout' => 35,
                        'ignore_errors' => true
                    ]
                ]);

            $response =
                @file_get_contents(
                    $url,
                    false,
                    $context
                );

            if ($response === false) {
                throw new RuntimeException(
                    'Long Poll connection failed'
                );
            }

            $data =
                json_decode(
                    $response,
                    true
                );

            if (!is_array($data)) {
                throw new RuntimeException(
                    'Invalid Long Poll response'
                );
            }

            if (isset($data['ts'])) {
                $ts = $data['ts'];
            }

            if (isset($data['failed'])) {
                break;
            }

            foreach (
                ($data['updates'] ?? [])
                as $event
            ) {

                if (
                    ($event['type'] ?? '')
                    !== 'message_new'
                ) {
                    continue;
                }

                $message =
                    $event['object'] ?? [];

                /*
                 * Новая структура VK:
                 *
                 * object.message
                 */

                if (
                    isset($message['message']) &&
                    is_array($message['message'])
                ) {
                    $message =
                        $message['message'];
                }

                handleMessage(
                    $pdo,
                    $message
                );
            }
        }

    } catch (Throwable $e) {

        fwrite(
            STDERR,
            'WARN: ' .
            $e->getMessage() .
            "\n"
        );

        sleep(3);
    }
}
