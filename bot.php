<?php
declare(strict_types=1);

/**
 * RAZE RUSSIA BOT — VK Long Poll, PHP 8.2
 * Улучшенная версия: исправлены баги, добавлены полезные функции, стабильный Long Poll.
 */
date_default_timezone_set(getenv('TZ') ?: 'Europe/Moscow');

function envv(string $key, string $default = ''): string {
    $value = getenv($key);
    return $value === false ? $default : trim((string)$value);
}

$token      = envv('VK_TOKEN');
$groupId    = (int)envv('VK_GROUP_ID', '0');
$ownerIds   = array_values(array_filter(array_map('intval', preg_split('/[\s,;]+/', envv('OWNER_IDS')) ?: [])));
$apiVersion = envv('VK_API_VERSION', '5.199');
$dbPath     = envv('DB_PATH', __DIR__ . '/data/raze.sqlite');
$pollWait   = max(1, min(25, (int)envv('LONGPOLL_WAIT', '25')));

if ($token === '' || $groupId < 1) {
    fwrite(STDERR, "ERROR: set VK_TOKEN and VK_GROUP_ID environment variables.\n");
    exit(1);
}
if (!extension_loaded('pdo_sqlite') || !function_exists('curl_init')) {
    fwrite(STDERR, "ERROR: PHP extensions pdo_sqlite and curl are required.\n");
    exit(1);
}
if (!is_dir(dirname($dbPath))) {
    mkdir(dirname($dbPath), 0775, true);
}

$pdo = new PDO('sqlite:' . $dbPath, null, null, [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);
$pdo->exec('PRAGMA journal_mode=WAL');
$pdo->exec('PRAGMA busy_timeout=5000');
$pdo->exec('PRAGMA foreign_keys=ON');

$pdo->exec(<<<'SQL'
CREATE TABLE IF NOT EXISTS roles (
    user_id    INTEGER PRIMARY KEY,
    role       TEXT    NOT NULL DEFAULT 'Участник',
    priority   INTEGER NOT NULL DEFAULT 0,
    granted_by INTEGER NOT NULL DEFAULT 0,
    created_at TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS superusers (
    user_id    INTEGER PRIMARY KEY,
    granted_by INTEGER NOT NULL,
    created_at TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS warnings (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL,
    actor_id   INTEGER NOT NULL,
    reason     TEXT    NOT NULL,
    created_at TEXT    NOT NULL,
    active     INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS mutes (
    user_id    INTEGER PRIMARY KEY,
    actor_id   INTEGER NOT NULL,
    reason     TEXT    NOT NULL,
    expires_at INTEGER NOT NULL DEFAULT 0,
    created_at TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS bans (
    user_id    INTEGER PRIMARY KEY,
    actor_id   INTEGER NOT NULL,
    reason     TEXT    NOT NULL,
    expires_at INTEGER NOT NULL DEFAULT 0,
    created_at TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS reports (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id     INTEGER NOT NULL,
    user_id     INTEGER NOT NULL,
    message     TEXT    NOT NULL,
    status      TEXT    NOT NULL DEFAULT 'open',
    assigned_to INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT    NOT NULL,
    closed_at   TEXT
);
CREATE TABLE IF NOT EXISTS nicknames (
    user_id    INTEGER PRIMARY KEY,
    nickname   TEXT    NOT NULL,
    updated_by INTEGER NOT NULL,
    updated_at TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_log (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id    INTEGER NOT NULL DEFAULT 0,
    actor_id   INTEGER NOT NULL,
    action     TEXT    NOT NULL,
    target_id  INTEGER NOT NULL DEFAULT 0,
    details    TEXT    NOT NULL DEFAULT '',
    created_at TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS flood (
    user_id    INTEGER PRIMARY KEY,
    count      INTEGER NOT NULL DEFAULT 0,
    window_start INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_warnings_user ON warnings(user_id, active);
CREATE INDEX IF NOT EXISTS idx_audit_target ON audit_log(target_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);
SQL);

/* ─────────────────────── Helpers ─────────────────────── */

function nowstr(): string {
    return date('Y-m-d H:i:s');
}

function audit(PDO $pdo, int $peer, int $actor, string $action, int $target = 0, string $details = ''): void {
    $s = $pdo->prepare('INSERT INTO audit_log(peer_id,actor_id,action,target_id,details,created_at) VALUES(?,?,?,?,?,?)');
    $s->execute([$peer, $actor, $action, $target, mb_substr($details, 0, 1000), nowstr()]);
}

function vk(string $method, array $params = []): array {
    global $token, $apiVersion;
    $params['access_token'] = $token;
    $params['v'] = $apiVersion;
    $ch = curl_init('https://api.vk.com/method/' . $method);
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => http_build_query($params),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT        => 25,
        CURLOPT_SSL_VERIFYPEER => true,
    ]);
    $body = curl_exec($ch);
    $err  = curl_error($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($body === false || $err !== '') {
        throw new RuntimeException("VK request failed: " . $err);
    }
    $data = json_decode($body, true);
    if (!is_array($data)) {
        throw new RuntimeException("Invalid VK response (HTTP {$code})");
    }
    if (isset($data['error'])) {
        $e = $data['error'];
        throw new RuntimeException('VK API ' . ($e['error_code'] ?? '?') . ': ' . ($e['error_msg'] ?? 'unknown error'));
    }
    return $data['response'] ?? [];
}

function sendMsg(int $peer, string $text, array $extra = []): void {
    try {
        vk('messages.send', array_merge([
            'peer_id'   => $peer,
            'message'   => mb_substr($text, 0, 3500),
            'random_id' => random_int(1, PHP_INT_MAX >> 1),
        ], $extra));
    } catch (Throwable $e) {
        error_log('[sendMsg] ' . $e->getMessage());
    }
}

function deleteMsg(int $messageId): void {
    if ($messageId < 1) return;
    try {
        vk('messages.delete', ['message_ids' => $messageId, 'delete_for_all' => 1]);
    } catch (Throwable $e) {
        error_log('[deleteMsg] ' . $e->getMessage());
    }
}

function kickFromChat(int $peer, int $userId): string {
    if ($peer < 2000000000) {
        return ' (не беседа)';
    }
    try {
        vk('messages.removeChatUser', [
            'chat_id' => $peer - 2000000000,
            'user_id' => $userId,
        ]);
        return ' Пользователь удалён из беседы.';
    } catch (Throwable $e) {
        return ' VK не разрешил удалить: ' . $e->getMessage();
    }
}

function priorityFor(PDO $pdo, int $userId, array $owners): int {
    if (in_array($userId, $owners, true)) return 1000;
    $s = $pdo->prepare('SELECT 1 FROM superusers WHERE user_id=?');
    $s->execute([$userId]);
    if ($s->fetchColumn()) return 900;
    $s = $pdo->prepare('SELECT priority FROM roles WHERE user_id=?');
    $s->execute([$userId]);
    $p = $s->fetchColumn();
    return $p === false ? 0 : (int)$p;
}

function roleName(PDO $pdo, int $userId, array $owners): string {
    if (in_array($userId, $owners, true)) return 'Владелец';
    $s = $pdo->prepare('SELECT 1 FROM superusers WHERE user_id=?');
    $s->execute([$userId]);
    if ($s->fetchColumn()) return 'Супердоступ';
    $s = $pdo->prepare('SELECT role FROM roles WHERE user_id=?');
    $s->execute([$userId]);
    return (string)($s->fetchColumn() ?: 'Участник');
}

function getNickname(PDO $pdo, int $userId): ?string {
    $s = $pdo->prepare('SELECT nickname FROM nicknames WHERE user_id=?');
    $s->execute([$userId]);
    $n = $s->fetchColumn();
    return $n === false ? null : (string)$n;
}

function activeWarns(PDO $pdo, int $userId): int {
    $s = $pdo->prepare('SELECT COUNT(*) FROM warnings WHERE user_id=? AND active=1');
    $s->execute([$userId]);
    return (int)$s->fetchColumn();
}

function formatDuration(int $seconds): string {
    if ($seconds <= 0) return 'навсегда';
    if ($seconds >= 86400) return round($seconds / 86400, 1) . ' дн.';
    if ($seconds >= 3600)  return round($seconds / 3600, 1) . ' ч.';
    if ($seconds >= 60)    return round($seconds / 60) . ' мин.';
    return $seconds . ' сек.';
}

function parseDuration(string $raw): int {
    $raw = trim(mb_strtolower($raw));
    if ($raw === '' || $raw === '0' || $raw === 'perm' || $raw === 'permanent' || $raw === 'навсегда') {
        return 0; // permanent
    }
    // support 1d2h30m, 10m, 2h, 5s
    if (!preg_match_all('/(\d+)\s*([smhd])/u', $raw, $matches, PREG_SET_ORDER)) {
        return -1; // invalid
    }
    $total = 0;
    foreach ($matches as $m) {
        $n = (int)$m[1];
        $total += match ($m[2]) {
            's' => $n,
            'm' => $n * 60,
            'h' => $n * 3600,
            'd' => $n * 86400,
            default => 0,
        };
    }
    return $total > 0 ? $total : -1;
}

function getTarget(array $msg, array $args): int {
    // Prefer reply / forward
    if (!empty($msg['reply_message']['from_id'])) {
        $id = (int)$msg['reply_message']['from_id'];
        if ($id > 0) return $id;
    }
    if (!empty($msg['fwd_messages'][0]['from_id'])) {
        $id = (int)$msg['fwd_messages'][0]['from_id'];
        if ($id > 0) return $id;
    }
    if (isset($args[0])) {
        $a = (string)$args[0];
        if (preg_match('/^-?\d+$/', $a)) return abs((int)$a);
        if (preg_match('/(?:vk\.com\/)?(?:id|club)?(\d+)/i', $a, $m)) return (int)$m[1];
        if (preg_match('/\[id(\d+)\|/', $a, $m)) return (int)$m[1]; // [id123|Name]
    }
    return 0;
}

function cleanExpired(PDO $pdo): void {
    $now = time();
    $pdo->exec("DELETE FROM mutes WHERE expires_at > 0 AND expires_at <= {$now}");
    $pdo->exec("DELETE FROM bans  WHERE expires_at > 0 AND expires_at <= {$now}");
}

function isMuted(PDO $pdo, int $userId): ?array {
    $s = $pdo->prepare('SELECT * FROM mutes WHERE user_id=?');
    $s->execute([$userId]);
    $row = $s->fetch();
    if (!$row) return null;
    if ((int)$row['expires_at'] > 0 && (int)$row['expires_at'] <= time()) {
        $pdo->prepare('DELETE FROM mutes WHERE user_id=?')->execute([$userId]);
        return null;
    }
    return $row;
}

function isBanned(PDO $pdo, int $userId): ?array {
    $s = $pdo->prepare('SELECT * FROM bans WHERE user_id=?');
    $s->execute([$userId]);
    $row = $s->fetch();
    if (!$row) return null;
    if ((int)$row['expires_at'] > 0 && (int)$row['expires_at'] <= time()) {
        $pdo->prepare('DELETE FROM bans WHERE user_id=?')->execute([$userId]);
        return null;
    }
    return $row;
}

function checkFlood(PDO $pdo, int $userId, int $limit = 8, int $window = 10): bool {
    // returns true if flooded
    $now = time();
    $s = $pdo->prepare('SELECT count, window_start FROM flood WHERE user_id=?');
    $s->execute([$userId]);
    $row = $s->fetch();
    if (!$row || ($now - (int)$row['window_start']) > $window) {
        $pdo->prepare('INSERT INTO flood(user_id,count,window_start) VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET count=1,window_start=excluded.window_start')
            ->execute([$userId, 1, $now]);
        return false;
    }
    $count = (int)$row['count'] + 1;
    $pdo->prepare('UPDATE flood SET count=? WHERE user_id=?')->execute([$count, $userId]);
    return $count > $limit;
}

function helpText(int $level = 0): string {
    $t = "🤖 RAZE RUSSIA BOT\n\n"
       . "📌 Общие\n"
       . "/ping — проверка работы\n"
       . "/help — эта справка\n"
       . "/myid — ваш ID и peer\n"
       . "/role — ваша роль\n"
       . "/roles — список ролей\n"
       . "/info [ID] — информация о пользователе\n"
       . "/nick ID ник — установить ник\n"
       . "/delnick ID — удалить ник\n"
       . "/report текст — пожаловаться\n\n";

    if ($level >= 20) {
        $t .= "🤝 Помощник+\n"
            . "/reports — открытые репорты\n"
            . "/close ID — закрыть репорт\n"
            . "/admins — список администрации\n\n";
    }
    if ($level >= 40) {
        $t .= "🔨 Модератор+\n"
            . "/warn ID причина\n"
            . "/unwarn ID\n"
            . "/warns ID — список предупреждений\n"
            . "/mute ID 10m причина (или ответом: /mute 10m причина)\n"
            . "/unmute ID\n"
            . "/kick ID\n"
            . "/logs [ID]\n\n";
    }
    if ($level >= 60) {
        $t .= "🛡 Администратор+\n"
            . "/ban ID 1d причина\n"
            . "/unban ID\n"
            . "/setrole ID роль\n"
            . "/delrole ID\n"
            . "/stats — статистика бота\n\n";
    }
    if ($level >= 900) {
        $t .= "⚡ Супердоступ / Владелец\n"
            . "/addws ID — супердоступ\n"
            . "/delws ID\n"
            . "/say текст — сообщение от бота\n"
            . "/clearlogs — очистить лог\n\n";
    }

    $t .= "⏱ Длительность: 30s, 10m, 2h, 1d, 1d12h, perm/навсегда\n"
        . "Префиксы: / ! . ,\n"
        . "Можно отвечать на сообщение пользователя.";
    return $t;
}

function notifyStaff(PDO $pdo, array $owners, int $peer, string $text): void {
    // Try to notify owners in current peer + DM if possible
    $ids = $owners;
    $s = $pdo->query('SELECT user_id FROM superusers');
    foreach ($s->fetchAll() as $r) $ids[] = (int)$r['user_id'];
    $s = $pdo->query('SELECT user_id FROM roles WHERE priority >= 40');
    foreach ($s->fetchAll() as $r) $ids[] = (int)$r['user_id'];
    $ids = array_unique(array_filter($ids));
    // Prefer current chat
    sendMsg($peer, $text);
}

/* ─────────────────────── Main processor ─────────────────────── */

function processMessage(PDO $pdo, array $msg, array $owners, int $groupId): void {
    $peer  = (int)($msg['peer_id'] ?? 0);
    $actor = (int)($msg['from_id'] ?? 0);
    $text  = trim((string)($msg['text'] ?? ''));
    $msgId = (int)($msg['id'] ?? 0);

    // Ignore messages from groups / community itself
    if ($peer < 1 || $actor < 1 || $text === '') return;
    if ($actor === -$groupId) return; // community messages

    // Enforce ban
    $ban = isBanned($pdo, $actor);
    if ($ban) {
        deleteMsg($msgId);
        // Try kick from chat
        if ($peer >= 2000000000) {
            kickFromChat($peer, $actor);
        }
        return;
    }

    // Enforce mute
    $mute = isMuted($pdo, $actor);
    if ($mute) {
        deleteMsg($msgId);
        return;
    }

    // Simple flood protection (commands only later, but we check early)
    if (checkFlood($pdo, $actor, 12, 8)) {
        // soft mute for 60s
        $pdo->prepare('INSERT INTO mutes(user_id,actor_id,reason,expires_at,created_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET expires_at=excluded.expires_at,reason=excluded.reason')
            ->execute([$actor, 0, 'anti-flood', time() + 60, nowstr()]);
        deleteMsg($msgId);
        return;
    }

    if (!preg_match('/^[\/!. ,](\S+)(?:\s+([\s\S]*))?$/u', $text, $m)) return;

    $command = mb_strtolower($m[1]);
    $tail    = trim($m[2] ?? '');
    $args    = $tail === '' ? [] : preg_split('/\s+/u', $tail, -1, PREG_SPLIT_NO_EMPTY);
    $args    = $args ?: [];

    $level = priorityFor($pdo, $actor, $owners);

    $reply = static function (string $s) use ($peer): void {
        sendMsg($peer, $s);
    };
    $need = static function (int $required) use ($level, $reply): bool {
        if ($level < $required) {
            $reply('⛔ Недостаточно прав.');
            return false;
        }
        return true;
    };

    $target = getTarget($msg, $args);

    // Helpers for reason extraction when target comes from reply
    $isReplyTarget = !empty($msg['reply_message']['from_id']) || !empty($msg['fwd_messages'][0]['from_id']);

    $aliases = [
        'пинг' => 'ping', 'команды' => 'help', 'помощь' => 'help', 'справка' => 'help',
        'айди' => 'myid', 'id' => 'myid', 'мойайди' => 'myid', 'мойid' => 'myid',
        'роль' => 'role', 'роли' => 'roles', 'админы' => 'admins', 'админ' => 'admins',
        'инфо' => 'info', 'информация' => 'info', 'whois' => 'info',
        'пред' => 'warn', 'варн' => 'warn', 'предупреждение' => 'warn',
        'снятьпред' => 'unwarn', 'снятьварн' => 'unwarn',
        'варны' => 'warns', 'преды' => 'warns', 'предупреждения' => 'warns',
        'мут' => 'mute', 'размут' => 'unmute', 'unmute' => 'unmute',
        'бан' => 'ban', 'разбан' => 'unban',
        'кик' => 'kick', 'исключить' => 'kick',
        'репорт' => 'report', 'жалоба' => 'report',
        'репорты' => 'reports', 'жалобы' => 'reports',
        'закрыть' => 'close',
        'выдатьроль' => 'setrole', 'снятьроль' => 'delrole',
        'сник' => 'nick', 'ник' => 'nick', 'установитьник' => 'nick',
        'удалитьник' => 'delnick', 'delnick' => 'delnick',
        'логи' => 'logs', 'лог' => 'logs',
        'стата' => 'stats', 'статистика' => 'stats',
        'сказать' => 'say', 'say' => 'say',
        'очиститьлоги' => 'clearlogs',
        'addws' => 'addws', 'delws' => 'delws',
        'статус' => 'status', 'status' => 'status',
    ];
    $command = $aliases[$command] ?? $command;

    try {
        switch ($command) {

            case 'ping':
                $reply('🏓 RAZE RUSSIA BOT работает. Uptime ok.');
                break;

            case 'help':
                $reply(helpText($level));
                break;

            case 'myid':
                $reply("🆔 Ваш VK ID: {$actor}\nPeer ID: {$peer}");
                break;

            case 'role':
                $nick = getNickname($pdo, $actor);
                $extra = $nick ? "\n🏷 Ник: {$nick}" : '';
                $reply('👤 Ваша роль: ' . roleName($pdo, $actor, $owners) . $extra);
                break;

            case 'roles':
                $reply(
                    "👑 Владелец — полный доступ (OWNER_IDS)\n"
                    . "⚡ Супердоступ — почти полный доступ\n"
                    . "🛡 Ст. администратор — приоритет 80\n"
                    . "🛡 Администратор — приоритет 60\n"
                    . "🔨 Модератор — приоритет 40\n"
                    . "🤝 Помощник — приоритет 20\n"
                    . "👤 Участник — приоритет 0"
                );
                break;

            case 'admins':
                if (!$need(20)) break;
                $out = "🛡 Администрация:\n";
                foreach ($owners as $oid) {
                    $n = getNickname($pdo, $oid);
                    $out .= "• Владелец: id{$oid}" . ($n ? " ({$n})" : '') . "\n";
                }
                $sups = $pdo->query('SELECT user_id FROM superusers ORDER BY user_id')->fetchAll();
                foreach ($sups as $r) {
                    $n = getNickname($pdo, (int)$r['user_id']);
                    $out .= "• Супердоступ: id{$r['user_id']}" . ($n ? " ({$n})" : '') . "\n";
                }
                $rows = $pdo->query("SELECT user_id, role FROM roles WHERE priority >= 20 ORDER BY priority DESC")->fetchAll();
                foreach ($rows as $r) {
                    $n = getNickname($pdo, (int)$r['user_id']);
                    $out .= "• {$r['role']}: id{$r['user_id']}" . ($n ? " ({$n})" : '') . "\n";
                }
                $reply(trim($out) === "🛡 Администрация:" ? 'Список администрации пуст.' : trim($out));
                break;

            case 'info':
                $tid = $target ?: $actor;
                $role = roleName($pdo, $tid, $owners);
                $nick = getNickname($pdo, $tid);
                $warns = activeWarns($pdo, $tid);
                $muteRow = isMuted($pdo, $tid);
                $banRow  = isBanned($pdo, $tid);

                $out = "📋 Информация об id{$tid}\n";
                $out .= "Роль: {$role}\n";
                if ($nick) $out .= "Ник: {$nick}\n";
                $out .= "Предупреждения: {$warns}/3\n";
                if ($muteRow) {
                    $left = (int)$muteRow['expires_at'] > 0 ? formatDuration((int)$muteRow['expires_at'] - time()) : 'навсегда';
                    $out .= "🔇 Мут: {$left} (причина: {$muteRow['reason']})\n";
                }
                if ($banRow) {
                    $left = (int)$banRow['expires_at'] > 0 ? formatDuration((int)$banRow['expires_at'] - time()) : 'навсегда';
                    $out .= "🔨 Бан: {$left} (причина: {$banRow['reason']})\n";
                }
                $reply(trim($out));
                break;

            case 'report':
                if ($tail === '') {
                    $reply('Использование: /report текст жалобы');
                    break;
                }
                $s = $pdo->prepare('INSERT INTO reports(peer_id,user_id,message,created_at) VALUES(?,?,?,?)');
                $s->execute([$peer, $actor, mb_substr($tail, 0, 1500), nowstr()]);
                $id = (int)$pdo->lastInsertId();
                audit($pdo, $peer, $actor, 'report_create', $id, $tail);
                $reply("📨 Репорт #{$id} создан. Администрация рассмотрит его.");
                // Notify staff in the same chat
                $staffMsg = "🚨 Новый репорт #{$id} от id{$actor}:\n" . mb_substr($tail, 0, 400);
                notifyStaff($pdo, $owners, $peer, $staffMsg);
                break;

            case 'reports':
                if (!$need(20)) break;
                $rows = $pdo->query("SELECT id,user_id,message,created_at FROM reports WHERE status='open' ORDER BY id DESC LIMIT 15")->fetchAll();
                if (!$rows) {
                    $reply('Открытых репортов нет.');
                    break;
                }
                $out = "📨 Открытые репорты:\n";
                foreach ($rows as $r) {
                    $out .= "#{$r['id']} от id{$r['user_id']} ({$r['created_at']}):\n" . mb_substr($r['message'], 0, 100) . "\n\n";
                }
                $reply(trim($out));
                break;

            case 'close':
                if (!$need(20)) break;
                $rid = (int)($args[0] ?? 0);
                if ($rid < 1) {
                    $reply('Использование: /close ID репорта');
                    break;
                }
                $s = $pdo->prepare("UPDATE reports SET status='closed',assigned_to=?,closed_at=? WHERE id=? AND status='open'");
                $s->execute([$actor, nowstr(), $rid]);
                if ($s->rowCount()) {
                    audit($pdo, $peer, $actor, 'report_close', $rid);
                    $reply("✅ Репорт #{$rid} закрыт.");
                } else {
                    $reply('Открытый репорт с таким ID не найден.');
                }
                break;

            case 'warn':
                if (!$need(40)) break;
                if (!$target) {
                    $reply('Использование: /warn ID причина (или ответьте на сообщение)');
                    break;
                }
                $reason = $isReplyTarget
                    ? trim(implode(' ', $args))
                    : trim(implode(' ', array_slice($args, 1)));
                if ($reason === '') {
                    $reply('Укажите причину: /warn ID причина');
                    break;
                }
                if (priorityFor($pdo, $target, $owners) >= $level) {
                    $reply('⛔ Нельзя выдать предупреждение пользователю с равными или более высокими правами.');
                    break;
                }
                $s = $pdo->prepare('INSERT INTO warnings(user_id,actor_id,reason,created_at) VALUES(?,?,?,?)');
                $s->execute([$target, $actor, $reason, nowstr()]);
                $n = activeWarns($pdo, $target);
                audit($pdo, $peer, $actor, 'warn', $target, $reason);
                $reply("⚠️ id{$target} получил предупреждение ({$n}/3).\nПричина: {$reason}");
                if ($n >= 3) {
                    $reply("🚨 У id{$target} накоплено 3 активных предупреждения. Рекомендуется проверить доступ.");
                }
                break;

            case 'unwarn':
                if (!$need(40)) break;
                if (!$target) {
                    $reply('Использование: /unwarn ID');
                    break;
                }
                $s = $pdo->prepare('SELECT id FROM warnings WHERE user_id=? AND active=1 ORDER BY id DESC LIMIT 1');
                $s->execute([$target]);
                $wid = $s->fetchColumn();
                if (!$wid) {
                    $reply('У пользователя нет активных предупреждений.');
                    break;
                }
                $pdo->prepare('UPDATE warnings SET active=0 WHERE id=?')->execute([$wid]);
                audit($pdo, $peer, $actor, 'unwarn', $target);
                $reply("✅ Одно предупреждение id{$target} снято.");
                break;

            case 'warns':
                if (!$need(40)) break;
                $tid = $target ?: 0;
                if (!$tid) {
                    $reply('Использование: /warns ID');
                    break;
                }
                $s = $pdo->prepare('SELECT id,reason,created_at,active FROM warnings WHERE user_id=? ORDER BY id DESC LIMIT 10');
                $s->execute([$tid]);
                $rows = $s->fetchAll();
                if (!$rows) {
                    $reply("У id{$tid} нет предупреждений.");
                    break;
                }
                $out = "⚠️ Предупреждения id{$tid}:\n";
                foreach ($rows as $r) {
                    $status = $r['active'] ? 'активно' : 'снято';
                    $out .= "#{$r['id']} [{$status}] {$r['created_at']}: {$r['reason']}\n";
                }
                $reply(trim($out));
                break;

            case 'mute':
                if (!$need(40)) break;

                $duration = -1;
                $reason = '';

                if ($isReplyTarget) {
                    // /mute 10m reason  (target from reply)
                    if (isset($args[0])) {
                        $duration = parseDuration((string)$args[0]);
                        $reason = trim(implode(' ', array_slice($args, 1)));
                    }
                } else {
                    // /mute ID 10m reason
                    if (!$target) {
                        $reply('Использование: /mute ID 10m причина\nИли ответом: /mute 10m причина');
                        break;
                    }
                    if (isset($args[1])) {
                        $duration = parseDuration((string)$args[1]);
                        $reason = trim(implode(' ', array_slice($args, 2)));
                    }
                }

                if (!$target) {
                    $reply('Не удалось определить пользователя. Укажите ID или ответьте на сообщение.');
                    break;
                }
                if ($duration < 0) {
                    $reply('Некорректная длительность. Примеры: 10m, 2h, 1d, 30s, perm');
                    break;
                }
                // Minimum 30 seconds for timed mute, 0 = permanent
                if ($duration > 0 && $duration < 30) {
                    $reply('Минимальная длительность мута — 30 секунд.');
                    break;
                }
                if (priorityFor($pdo, $target, $owners) >= $level) {
                    $reply('⛔ Нельзя наказать пользователя с равными или более высокими правами.');
                    break;
                }

                $expires = $duration > 0 ? time() + $duration : 0;
                $s = $pdo->prepare('INSERT INTO mutes(user_id,actor_id,reason,expires_at,created_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET actor_id=excluded.actor_id,reason=excluded.reason,expires_at=excluded.expires_at,created_at=excluded.created_at');
                $s->execute([$target, $actor, $reason ?: 'не указана', $expires, nowstr()]);
                audit($pdo, $peer, $actor, 'mute', $target, $reason);
                $reply("🔇 id{$target} заглушён на " . formatDuration($duration) . ".\nБот будет удалять его сообщения (если есть права).");
                break;

            case 'unmute':
                if (!$need(40)) break;
                if (!$target) {
                    $reply('Использование: /unmute ID');
                    break;
                }
                $pdo->prepare('DELETE FROM mutes WHERE user_id=?')->execute([$target]);
                audit($pdo, $peer, $actor, 'unmute', $target);
                $reply("🔊 Мут id{$target} снят.");
                break;

            case 'ban':
                if (!$need(60)) break;
                if (!$target) {
                    $reply('Использование: /ban ID 1d причина (или ответом)');
                    break;
                }

                $duration = -1;
                $reason = '';
                if ($isReplyTarget) {
                    if (isset($args[0])) {
                        $duration = parseDuration((string)$args[0]);
                        $reason = trim(implode(' ', array_slice($args, 1)));
                    } else {
                        $duration = 0; // permanent if only reply
                    }
                } else {
                    if (isset($args[1])) {
                        $duration = parseDuration((string)$args[1]);
                        $reason = trim(implode(' ', array_slice($args, 2)));
                    } else {
                        $duration = 0;
                        $reason = trim(implode(' ', array_slice($args, 1)));
                    }
                }
                if ($duration < 0) $duration = 0;

                if (priorityFor($pdo, $target, $owners) >= $level) {
                    $reply('⛔ Нельзя забанить пользователя с равными или более высокими правами.');
                    break;
                }

                $expires = $duration > 0 ? time() + $duration : 0;
                $s = $pdo->prepare('INSERT INTO bans(user_id,actor_id,reason,expires_at,created_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET actor_id=excluded.actor_id,reason=excluded.reason,expires_at=excluded.expires_at,created_at=excluded.created_at');
                $s->execute([$target, $actor, $reason ?: 'не указана', $expires, nowstr()]);
                audit($pdo, $peer, $actor, 'ban', $target, $reason);

                $extra = kickFromChat($peer, $target);
                $reply("🔨 id{$target} внесён в бан-лист на " . formatDuration($duration) . ".\nПричина: " . ($reason ?: 'не указана') . $extra);
                break;

            case 'unban':
                if (!$need(60)) break;
                if (!$target) {
                    $reply('Использование: /unban ID');
                    break;
                }
                $pdo->prepare('DELETE FROM bans WHERE user_id=?')->execute([$target]);
                audit($pdo, $peer, $actor, 'unban', $target);
                $reply("✅ Бан id{$target} снят в системе бота. Автоматическое возвращение в беседу не выполняется.");
                break;

            case 'kick':
                if (!$need(40)) break;
                if (!$target) {
                    $reply('Использование: /kick ID (или ответом на сообщение)');
                    break;
                }
                if (priorityFor($pdo, $target, $owners) >= $level) {
                    $reply('⛔ Нельзя кикнуть пользователя с равными или более высокими правами.');
                    break;
                }
                if ($peer < 2000000000) {
                    $reply('Команда кика работает только в беседе.');
                    break;
                }
                $extra = kickFromChat($peer, $target);
                audit($pdo, $peer, $actor, 'kick', $target);
                $reply("👢 id{$target} удалён из беседы." . ($extra ? " {$extra}" : ''));
                break;

            case 'setrole':
                if (!$need(60)) break;
                if (!$target) {
                    $reply('Использование: /setrole ID помощник|модератор|администратор|ст.администратор');
                    break;
                }
                $roleRaw = $isReplyTarget
                    ? trim(implode(' ', $args))
                    : trim(implode(' ', array_slice($args, 1)));
                if ($roleRaw === '') {
                    $reply('Укажите роль: помощник, модератор, администратор, ст.администратор');
                    break;
                }
                $map = [
                    'участник'          => ['Участник', 0],
                    'помощник'          => ['Помощник', 20],
                    'модератор'         => ['Модератор', 40],
                    'администратор'     => ['Администратор', 60],
                    'ст.администратор'  => ['Ст. администратор', 80],
                    'старший'           => ['Ст. администратор', 80],
                    'стадмин'           => ['Ст. администратор', 80],
                ];
                $key = mb_strtolower($roleRaw);
                if (!isset($map[$key])) {
                    $reply('Доступные роли: участник, помощник, модератор, администратор, ст.администратор');
                    break;
                }
                if (priorityFor($pdo, $target, $owners) >= $level) {
                    $reply('⛔ Нельзя менять роль пользователя с равными или более высокими правами.');
                    break;
                }
                [$rname, $rp] = $map[$key];
                // Cannot grant role higher or equal to own level (except owners)
                if ($rp >= $level && $level < 1000) {
                    $reply('⛔ Нельзя выдать роль с приоритетом выше или равным вашему.');
                    break;
                }
                $s = $pdo->prepare('INSERT INTO roles(user_id,role,priority,granted_by,created_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET role=excluded.role,priority=excluded.priority,granted_by=excluded.granted_by,created_at=excluded.created_at');
                $s->execute([$target, $rname, $rp, $actor, nowstr()]);
                audit($pdo, $peer, $actor, 'setrole', $target, $rname);
                $reply("✅ id{$target}: выдана роль «{$rname}».");
                break;

            case 'delrole':
                if (!$need(60)) break;
                if (!$target) {
                    $reply('Использование: /delrole ID');
                    break;
                }
                if (priorityFor($pdo, $target, $owners) >= $level) {
                    $reply('⛔ Нельзя снять роль у пользователя с равными или более высокими правами.');
                    break;
                }
                $pdo->prepare('DELETE FROM roles WHERE user_id=?')->execute([$target]);
                audit($pdo, $peer, $actor, 'delrole', $target);
                $reply("✅ Роль id{$target} сброшена до участника.");
                break;

            case 'addws':
                if (!in_array($actor, $owners, true)) {
                    $reply('⛔ Команда доступна только ID из OWNER_IDS.');
                    break;
                }
                if (!$target) {
                    $reply('Использование: /addws ID');
                    break;
                }
                $s = $pdo->prepare('INSERT OR IGNORE INTO superusers(user_id,granted_by,created_at) VALUES(?,?,?)');
                $s->execute([$target, $actor, nowstr()]);
                audit($pdo, $peer, $actor, 'addws', $target);
                $reply("⚡ id{$target} получил супердоступ.");
                break;

            case 'delws':
                if (!in_array($actor, $owners, true)) {
                    $reply('⛔ Команда доступна только ID из OWNER_IDS.');
                    break;
                }
                if (!$target) {
                    $reply('Использование: /delws ID');
                    break;
                }
                $pdo->prepare('DELETE FROM superusers WHERE user_id=?')->execute([$target]);
                audit($pdo, $peer, $actor, 'delws', $target);
                $reply("✅ Супердоступ id{$target} снят.");
                break;

            case 'nick':
                if (!$need(20)) break;
                if (!$target) {
                    $reply('Использование: /nick ID игровой_ник');
                    break;
                }
                $nick = $isReplyTarget
                    ? trim(implode(' ', $args))
                    : trim(implode(' ', array_slice($args, 1)));
                if ($nick === '') {
                    $reply('Укажите ник: /nick ID ник');
                    break;
                }
                if (mb_strlen($nick) > 64) {
                    $reply('Ник слишком длинный (макс. 64 символа).');
                    break;
                }
                $s = $pdo->prepare('INSERT INTO nicknames(user_id,nickname,updated_by,updated_at) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET nickname=excluded.nickname,updated_by=excluded.updated_by,updated_at=excluded.updated_at');
                $s->execute([$target, $nick, $actor, nowstr()]);
                audit($pdo, $peer, $actor, 'nick', $target, $nick);
                $reply("✅ Ник id{$target} сохранён: {$nick}");
                break;

            case 'delnick':
                if (!$need(20)) break;
                if (!$target) {
                    $reply('Использование: /delnick ID');
                    break;
                }
                $pdo->prepare('DELETE FROM nicknames WHERE user_id=?')->execute([$target]);
                audit($pdo, $peer, $actor, 'delnick', $target);
                $reply("✅ Ник id{$target} удалён.");
                break;

            case 'logs':
                if (!$need(40)) break;
                $filter = (int)($args[0] ?? 0);
                if ($filter) {
                    $s = $pdo->prepare('SELECT * FROM audit_log WHERE target_id=? OR actor_id=? ORDER BY id DESC LIMIT 15');
                    $s->execute([$filter, $filter]);
                    $rows = $s->fetchAll();
                } else {
                    $rows = $pdo->query('SELECT * FROM audit_log ORDER BY id DESC LIMIT 15')->fetchAll();
                }
                if (!$rows) {
                    $reply('Записей нет.');
                    break;
                }
                $out = "📋 Последние действия:\n";
                foreach ($rows as $r) {
                    $out .= "#{$r['id']} {$r['action']} | id{$r['actor_id']} → id{$r['target_id']} | {$r['created_at']}\n";
                    if ($r['details'] !== '') $out .= "   └ {$r['details']}\n";
                }
                $reply(trim($out));
                break;

            case 'stats':
                if (!$need(60)) break;
                $warns   = (int)$pdo->query('SELECT COUNT(*) FROM warnings WHERE active=1')->fetchColumn();
                $mutes   = (int)$pdo->query('SELECT COUNT(*) FROM mutes')->fetchColumn();
                $bans    = (int)$pdo->query('SELECT COUNT(*) FROM bans')->fetchColumn();
                $reports = (int)$pdo->query("SELECT COUNT(*) FROM reports WHERE status='open'")->fetchColumn();
                $roles   = (int)$pdo->query('SELECT COUNT(*) FROM roles WHERE priority>0')->fetchColumn();
                $logs    = (int)$pdo->query('SELECT COUNT(*) FROM audit_log')->fetchColumn();
                $reply(
                    "📊 Статистика бота\n"
                    . "Активных варнов: {$warns}\n"
                    . "Мутов: {$mutes}\n"
                    . "Банов: {$bans}\n"
                    . "Открытых репортов: {$reports}\n"
                    . "Выданных ролей: {$roles}\n"
                    . "Записей в логе: {$logs}"
                );
                break;

            case 'say':
                if ($level < 900) {
                    $reply('⛔ Недостаточно прав.');
                    break;
                }
                if ($tail === '') {
                    $reply('Использование: /say текст');
                    break;
                }
                // Delete the command message if possible, then send clean text
                deleteMsg($msgId);
                sendMsg($peer, $tail);
                audit($pdo, $peer, $actor, 'say', 0, mb_substr($tail, 0, 200));
                break;

            case 'clearlogs':
                if ($level < 900) {
                    $reply('⛔ Недостаточно прав.');
                    break;
                }
                $pdo->exec('DELETE FROM audit_log');
                $reply('🗑 Лог аудита очищен.');
                break;

            case 'status':
                $reply(
                    "🤖 RAZE RUSSIA BOT\n"
                    . "Group ID: {$groupId}\n"
                    . "PHP: " . PHP_VERSION . "\n"
                    . "Время: " . nowstr() . "\n"
                    . "Бот работает нормально."
                );
                break;

            default:
                // Silent for unknown commands
                break;
        }
    } catch (Throwable $e) {
        error_log('[command ' . $command . '] ' . $e->getMessage());
        $reply('⚠️ Ошибка выполнения команды. Проверьте права бота и логи.');
    }
}

/* ─────────────────────── Startup & Long Poll ─────────────────────── */

echo "RAZE RUSSIA BOT starting. Group ID={$groupId}\n";
cleanExpired($pdo);

try {
    vk('groups.getById', ['group_id' => $groupId]);
    $lp = vk('groups.getLongPollServer', ['group_id' => $groupId]);
    $server = (string)($lp['server'] ?? '');
    $key    = (string)($lp['key'] ?? '');
    $ts     = (string)($lp['ts'] ?? '');
    if ($server === '' || $key === '' || $ts === '') {
        throw new RuntimeException('groups.getLongPollServer returned incomplete data');
    }

    vk('groups.setLongPollSettings', [
        'group_id'              => $groupId,
        'enabled'               => 1,
        'api_version'           => $apiVersion,
        'message_new'           => 1,
        'message_reply'         => 0,
        'message_edit'          => 0,
        'message_allow'         => 0,
        'message_deny'          => 0,
        'message_typing_state'  => 0,
        'photo_new'             => 0,
        'audio_new'             => 0,
        'video_new'             => 0,
        'wall_reply_new'        => 0,
        'wall_post_new'         => 0,
        'wall_repost'           => 0,
        'board_post_new'        => 0,
        'market_comment_new'    => 0,
        'group_join'            => 0,
        'group_leave'           => 0,
        'user_block'            => 0,
        'user_unblock'          => 0,
        'group_change_settings' => 0,
        'group_officers_edit'   => 0,
        'poll_vote_new'         => 0,
        'like_add'              => 0,
        'like_remove'           => 0,
        'message_event'         => 0,
        'donut_subscription_create' => 0,
        'donut_subscription_prolonged' => 0,
        'donut_subscription_cancelled' => 0,
        'donut_subscription_expired' => 0,
        'donut_subscription_price_changed' => 0,
        'donut_money_withdraw'  => 0,
        'donut_money_withdraw_error' => 0,
    ]);

    echo "Long Poll connected; message_new enabled.\n";

    $lastCleanup = time();
    $failCount   = 0;

    while (true) {
        // Periodic cleanup of expired mutes/bans
        if (time() - $lastCleanup > 120) {
            cleanExpired($pdo);
            $lastCleanup = time();
        }

        $url = $server . '?act=a_check&key=' . urlencode($key) . '&ts=' . urlencode($ts) . '&wait=' . $pollWait;
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_TIMEOUT        => $pollWait + 15,
            CURLOPT_SSL_VERIFYPEER => true,
        ]);
        $body = curl_exec($ch);
        $err  = curl_error($ch);
        curl_close($ch);

        if ($body === false || $err !== '') {
            $failCount++;
            error_log('[longpoll] ' . $err);
            sleep(min(30, 2 * $failCount));
            if ($failCount >= 5) {
                // Refresh server credentials
                try {
                    $lp = vk('groups.getLongPollServer', ['group_id' => $groupId]);
                    $server = (string)$lp['server'];
                    $key    = (string)$lp['key'];
                    $ts     = (string)$lp['ts'];
                    $failCount = 0;
                    echo "Long Poll server refreshed after network errors.\n";
                } catch (Throwable $e) {
                    error_log('[longpoll-refresh] ' . $e->getMessage());
                }
            }
            continue;
        }

        $failCount = 0;
        $data = json_decode($body, true);
        if (!is_array($data)) {
            sleep(1);
            continue;
        }

        if (isset($data['failed'])) {
            $failed = (int)$data['failed'];
            if ($failed === 1) {
                // ts is outdated
                $ts = (string)($data['ts'] ?? $ts);
            } else {
                // key expired or other — get new server
                try {
                    $lp = vk('groups.getLongPollServer', ['group_id' => $groupId]);
                    $server = (string)$lp['server'];
                    $key    = (string)$lp['key'];
                    $ts     = (string)$lp['ts'];
                    echo "Long Poll credentials refreshed (failed={$failed}).\n";
                } catch (Throwable $e) {
                    error_log('[longpoll-failed] ' . $e->getMessage());
                    sleep(5);
                }
            }
            continue;
        }

        if (isset($data['ts'])) {
            $ts = (string)$data['ts'];
        }

        foreach (($data['updates'] ?? []) as $update) {
            if (($update['type'] ?? '') !== 'message_new') continue;
            $msg = $update['object']['message'] ?? $update['object'] ?? null;
            if (is_array($msg)) {
                processMessage($pdo, $msg, $ownerIds, $groupId);
            }
        }
    }
} catch (Throwable $e) {
    fwrite(STDERR, "FATAL: " . $e->getMessage() . "\n");
    exit(1);
}
