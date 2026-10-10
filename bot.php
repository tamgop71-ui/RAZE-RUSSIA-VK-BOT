<?php
declare(strict_types=1);

/**
 * RAZE RUSSIA BOT — VK Long Poll, PHP 8.2
 * Original implementation inspired by common community moderation bot features.
 */
date_default_timezone_set(getenv('TZ') ?: 'Europe/Moscow');

function envv(string $key, string $default = ''): string {
    $value = getenv($key);
    return $value === false ? $default : trim((string)$value);
}
$token = envv('VK_TOKEN');
$groupId = (int)envv('VK_GROUP_ID', '0');
$ownerIds = array_values(array_filter(array_map('intval', preg_split('/[\s,;]+/', envv('OWNER_IDS')) ?: [])));
$apiVersion = envv('VK_API_VERSION', '5.199');
$dbPath = envv('DB_PATH', __DIR__ . '/data/raze.sqlite');
$pollWait = max(1, min(25, (int)envv('LONGPOLL_WAIT', '25')));

if ($token === '' || $groupId < 1) {
    fwrite(STDERR, "ERROR: set VK_TOKEN and VK_GROUP_ID environment variables.\n");
    exit(1);
}
if (!extension_loaded('pdo_sqlite') || !function_exists('curl_init')) {
    fwrite(STDERR, "ERROR: PHP extensions pdo_sqlite and curl are required.\n");
    exit(1);
}
if (!is_dir(dirname($dbPath))) mkdir(dirname($dbPath), 0775, true);

$pdo = new PDO('sqlite:' . $dbPath, null, null, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
]);
$pdo->exec('PRAGMA journal_mode=WAL');
$pdo->exec('PRAGMA busy_timeout=5000');
$pdo->exec(<<<'SQL'
CREATE TABLE IF NOT EXISTS roles (
 user_id INTEGER PRIMARY KEY, role TEXT NOT NULL DEFAULT 'Участник',
 priority INTEGER NOT NULL DEFAULT 0, granted_by INTEGER NOT NULL DEFAULT 0,
 created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS superusers (
 user_id INTEGER PRIMARY KEY, granted_by INTEGER NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS warnings (
 id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, actor_id INTEGER NOT NULL,
 reason TEXT NOT NULL, created_at TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS mutes (
 user_id INTEGER PRIMARY KEY, actor_id INTEGER NOT NULL, reason TEXT NOT NULL,
 expires_at INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS bans (
 user_id INTEGER PRIMARY KEY, actor_id INTEGER NOT NULL, reason TEXT NOT NULL,
 expires_at INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS reports (
 id INTEGER PRIMARY KEY AUTOINCREMENT, peer_id INTEGER NOT NULL, user_id INTEGER NOT NULL,
 message TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open', assigned_to INTEGER NOT NULL DEFAULT 0,
 created_at TEXT NOT NULL, closed_at TEXT
);
CREATE TABLE IF NOT EXISTS nicknames (
 user_id INTEGER PRIMARY KEY, nickname TEXT NOT NULL, updated_by INTEGER NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_log (
 id INTEGER PRIMARY KEY AUTOINCREMENT, peer_id INTEGER NOT NULL DEFAULT 0, actor_id INTEGER NOT NULL,
 action TEXT NOT NULL, target_id INTEGER NOT NULL DEFAULT 0, details TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
 key TEXT PRIMARY KEY, value TEXT NOT NULL
);
SQL);

function nowstr(): string { return date('Y-m-d H:i:s'); }
function audit(PDO $pdo, int $peer, int $actor, string $action, int $target = 0, string $details = ''): void {
    $s = $pdo->prepare('INSERT INTO audit_log(peer_id,actor_id,action,target_id,details,created_at) VALUES(?,?,?,?,?,?)');
    $s->execute([$peer,$actor,$action,$target,mb_substr($details,0,1000),nowstr()]);
}
function vk(string $method, array $params = []): array {
    global $token, $apiVersion;
    $params['access_token'] = $token;
    $params['v'] = $apiVersion;
    $ch = curl_init('https://api.vk.com/method/' . $method);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => http_build_query($params),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 25,
        CURLOPT_SSL_VERIFYPEER => true,
    ]);
    $body = curl_exec($ch);
    $err = curl_error($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($body === false || $err !== '') throw new RuntimeException("VK request failed: " . $err);
    $data = json_decode($body, true);
    if (!is_array($data)) throw new RuntimeException("Invalid VK response (HTTP {$code})");
    if (isset($data['error'])) {
        $e = $data['error'];
        throw new RuntimeException('VK API ' . ($e['error_code'] ?? '?') . ': ' . ($e['error_msg'] ?? 'unknown error'));
    }
    return $data['response'] ?? [];
}
function sendMsg(int $peer, string $text, array $extra = []): void {
    try {
        vk('messages.send', array_merge([
            'peer_id' => $peer, 'message' => mb_substr($text,0,3500),
            'random_id' => random_int(1, PHP_INT_MAX >> 1),
        ], $extra));
    } catch (Throwable $e) {
        error_log('[sendMsg] ' . $e->getMessage());
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
function isPrivileged(int $id, array $owners, PDO $pdo): bool {
    return priorityFor($pdo, $id, $owners) >= 40;
}
function getTarget(array $msg, array $args): int {
    if (!empty($msg['reply_message']['from_id'])) return (int)$msg['reply_message']['from_id'];
    if (!empty($msg['fwd_messages'][0]['from_id'])) return (int)$msg['fwd_messages'][0]['from_id'];
    if (isset($args[0]) && preg_match('/^-?\d+$/', (string)$args[0])) return abs((int)$args[0]);
    if (isset($args[0]) && preg_match('/(?:id|club)(\d+)/i', (string)$args[0], $m)) return (int)$m[1];
    return 0;
}
function parseDuration(string $raw): int {
    if (!preg_match('/^(\d+)([mhd])$/i', $raw, $m)) return 0;
    $n = (int)$m[1];
    return $n * match (strtolower($m[2])) {'m'=>60, 'h'=>3600, 'd'=>86400};
}
function helpText(): string {
    return "🤖 RAZE RUSSIA BOT\n\n"
      . "Общие: /ping, /help, /myid, /role, /roles, /admins\n"
      . "Репорты: /report текст, /reports, /close ID\n"
      . "Модерация (при наличии прав): /warn ID причина, /unwarn ID, /mute ID 10m причина, /unmute ID, /ban ID 1d причина, /unban ID, /kick ID\n"
      . "Управление: /setrole ID роль, /delrole ID, /nick ID ник, /logs [ID]\n"
      . "Владелец: /addws ID, /delws ID\n\n"
      . "Длительность: 10m — минуты, 2h — часы, 3d — дни. Команды также принимают префиксы ! . ,";
}
function processMessage(PDO $pdo, array $msg, array $owners): void {
    $peer = (int)($msg['peer_id'] ?? 0);
    $actor = (int)($msg['from_id'] ?? 0);
    $text = trim((string)($msg['text'] ?? ''));
    if ($peer < 1 || $actor < 1 || $text === '') return;

    // Apply local mute enforcement. The bot can delete messages only if VK grants sufficient rights.
    $mute = $pdo->prepare('SELECT expires_at,reason FROM mutes WHERE user_id=?');
    $mute->execute([$actor]);
    $muteRow = $mute->fetch();
    if ($muteRow) {
        if ((int)$muteRow['expires_at'] > 0 && (int)$muteRow['expires_at'] <= time()) {
            $pdo->prepare('DELETE FROM mutes WHERE user_id=?')->execute([$actor]);
        } else {
            try {
                if (!empty($msg['id'])) vk('messages.delete', ['message_ids'=>(int)$msg['id'], 'delete_for_all'=>1]);
            } catch (Throwable $e) { error_log('[mute-delete] '.$e->getMessage()); }
            return;
        }
    }

    if (!preg_match('/^[\/!. ,](\S+)(?:\s+([\s\S]*))?$/u', $text, $m)) return;
    $command = mb_strtolower($m[1]);
    $tail = trim($m[2] ?? '');
    $args = $tail === '' ? [] : preg_split('/\s+/u', $tail);
    $args = $args ?: [];
    $level = priorityFor($pdo, $actor, $owners);
    $reply = static function(string $s) use ($peer): void { sendMsg($peer, $s); };
    $need = static function(int $required) use ($level, $reply): bool {
        if ($level < $required) { $reply('⛔ Недостаточно прав.'); return false; }
        return true;
    };
    $target = getTarget($msg, $args);
    $reasonFrom = static function(int $skip = 1) use ($args): string {
        return trim(implode(' ', array_slice($args, $skip)));
    };

    $aliases = [
      'пинг'=>'ping','команды'=>'help','помощь'=>'help','айди'=>'myid','id'=>'myid','мойайди'=>'myid',
      'роли'=>'roles','админы'=>'admins','пред'=>'warn','варн'=>'warn','снятьпред'=>'unwarn','unwarn'=>'unwarn',
      'мут'=>'mute','размут'=>'unmute','бан'=>'ban','разбан'=>'unban','кик'=>'kick',
      'репорт'=>'report','репорты'=>'reports','закрыть'=>'close','выдатьроль'=>'setrole','снятьроль'=>'delrole',
      'сник'=>'nick','ник'=>'nick','логи'=>'logs','addws'=>'addws','delws'=>'delws'
    ];
    $command = $aliases[$command] ?? $command;

    try {
        switch ($command) {
            case 'ping': $reply('🏓 RAZE RUSSIA BOT работает.'); break;
            case 'help': $reply(helpText()); break;
            case 'myid': $reply("🆔 Ваш VK ID: {$actor}\nPeer ID: {$peer}"); break;
            case 'role': $reply('👤 Ваша роль: ' . roleName($pdo,$actor,$owners)); break;
            case 'roles':
                $reply("👑 Владелец — полный доступ\n⚡ Супердоступ — расширенный доступ\n🛡 Администратор — приоритет 60\n🔨 Модератор — приоритет 40\n🤝 Помощник — приоритет 20\n👤 Участник — приоритет 0");
                break;
            case 'admins':
                $rows = $pdo->query("SELECT user_id,role FROM roles WHERE priority>=20 ORDER BY priority DESC")->fetchAll();
                $out = "🛡 Администрация:\n";
                foreach ($owners as $oid) $out .= "• Владелец: id{$oid}\n";
                $sups = $pdo->query('SELECT user_id FROM superusers ORDER BY user_id')->fetchAll();
                foreach ($sups as $r) $out .= "• Супердоступ: id{$r['user_id']}\n";
                foreach ($rows as $r) $out .= "• {$r['role']}: id{$r['user_id']}\n";
                $reply($out === "🛡 Администрация:\n" ? 'Список администрации пуст.' : trim($out));
                break;
            case 'report':
                if ($tail === '') { $reply('Использование: /report текст жалобы'); break; }
                $s=$pdo->prepare('INSERT INTO reports(peer_id,user_id,message,created_at) VALUES(?,?,?,?)');
                $s->execute([$peer,$actor,mb_substr($tail,0,1500),nowstr()]);
                $id=(int)$pdo->lastInsertId();
                audit($pdo,$peer,$actor,'report_create',$id,$tail);
                $reply("📨 Репорт #{$id} создан. Администрация рассмотрит его.");
                break;
            case 'reports':
                if (!$need(20)) break;
                $rows=$pdo->query("SELECT id,user_id,message,created_at FROM reports WHERE status='open' ORDER BY id DESC LIMIT 15")->fetchAll();
                if (!$rows) { $reply('Открытых репортов нет.'); break; }
                $out="📨 Открытые репорты:\n";
                foreach($rows as $r) $out.="#{$r['id']} от id{$r['user_id']}: ".mb_substr($r['message'],0,120)."\n";
                $reply(trim($out)); break;
            case 'close':
                if (!$need(20)) break;
                $rid=(int)($args[0]??0);
                if ($rid<1) { $reply('Использование: /close ID репорта'); break; }
                $s=$pdo->prepare("UPDATE reports SET status='closed',assigned_to=?,closed_at=? WHERE id=? AND status='open'");
                $s->execute([$actor,nowstr(),$rid]);
                if ($s->rowCount()) { audit($pdo,$peer,$actor,'report_close',$rid); $reply("✅ Репорт #{$rid} закрыт."); }
                else $reply('Открытый репорт с таким ID не найден.');
                break;
            case 'warn':
                if (!$need(40)) break;
                $target = $target ?: 0; $reason=$reasonFrom($target ? 1 : 0);
                if (!$target || $reason==='') { $reply('Использование: /warn ID причина (или ответьте на сообщение)'); break; }
                if (priorityFor($pdo,$target,$owners) >= $level) { $reply('⛔ Нельзя выдать предупреждение пользователю с равными или более высокими правами.'); break; }
                $s=$pdo->prepare('INSERT INTO warnings(user_id,actor_id,reason,created_at) VALUES(?,?,?,?)');
                $s->execute([$target,$actor,$reason,nowstr()]);
                $count=$pdo->prepare('SELECT COUNT(*) FROM warnings WHERE user_id=? AND active=1'); $count->execute([$target]); $n=(int)$count->fetchColumn();
                audit($pdo,$peer,$actor,'warn',$target,$reason);
                $reply("⚠️ id{$target} получил предупреждение ({$n}/3).\nПричина: {$reason}");
                if ($n>=3) $reply("🚨 У id{$target} накоплено 3 активных предупреждения. Проверьте доступ вручную.");
                break;
            case 'unwarn':
                if (!$need(40)) break;
                if (!$target) { $reply('Использование: /unwarn ID'); break; }
                $s=$pdo->prepare('SELECT id FROM warnings WHERE user_id=? AND active=1 ORDER BY id DESC LIMIT 1'); $s->execute([$target]); $wid=$s->fetchColumn();
                if (!$wid) { $reply('У пользователя нет активных предупреждений.'); break; }
                $pdo->prepare('UPDATE warnings SET active=0 WHERE id=?')->execute([$wid]); audit($pdo,$peer,$actor,'unwarn',$target);
                $reply("✅ Одно предупреждение id{$target} снято."); break;
            case 'mute':
                if (!$need(40)) break;
                if (!$target) { $reply('Использование: /mute ID 10m причина (или ответьте на сообщение)'); break; }
                $duration=isset($args[1])?parseDuration((string)$args[1]):0;
                $reason=$target && $duration ? trim(implode(' ',array_slice($args,2))):trim(implode(' ',array_slice($args,1)));
                if ($duration===0 && isset($args[1]) && preg_match('/^\d+[mhd]$/i',(string)$args[1])) $duration=parseDuration((string)$args[1]);
                if ($duration===0 && isset($args[0]) && $target && preg_match('/^\d+[mhd]$/i',(string)$args[0])) $duration=parseDuration((string)$args[0]);
                // Reply target syntax: /mute 10m reason
                if (!empty($msg['reply_message']['from_id']) && isset($args[0]) && parseDuration((string)$args[0])>0) {
                    $duration=parseDuration((string)$args[0]); $reason=trim(implode(' ',array_slice($args,1)));
                }
                if (!$target || $duration<60) { $reply('Использование: /mute ID 10m причина; ответом: /mute 10m причина'); break; }
                if (priorityFor($pdo,$target,$owners)>=$level) { $reply('⛔ Нельзя наказать пользователя с равными или более высокими правами.'); break; }
                $expires=time()+$duration;
                $s=$pdo->prepare('INSERT INTO mutes(user_id,actor_id,reason,expires_at,created_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET actor_id=excluded.actor_id,reason=excluded.reason,expires_at=excluded.expires_at,created_at=excluded.created_at');
                $s->execute([$target,$actor,$reason ?: 'не указана',$expires,nowstr()]); audit($pdo,$peer,$actor,'mute',$target,$reason);
                $reply("🔇 id{$target} заглушён на ".($duration>=86400?round($duration/86400,1).' дн.':($duration>=3600?round($duration/3600,1).' ч.':round($duration/60).' мин.')).".\nБот будет удалять его сообщения, если VK разрешает удаление."); break;
            case 'unmute':
                if (!$need(40)) break;
                if (!$target) { $reply('Использование: /unmute ID'); break; }
                $pdo->prepare('DELETE FROM mutes WHERE user_id=?')->execute([$target]); audit($pdo,$peer,$actor,'unmute',$target);
                $reply("🔊 Мут id{$target} снят."); break;
            case 'ban':
                if (!$need(60)) break;
                if (!$target) { $reply('Использование: /ban ID 1d причина'); break; }
                $duration=isset($args[1])?parseDuration((string)$args[1]):0;
                $reason=trim(implode(' ',array_slice($args,$duration?2:1)));
                if (priorityFor($pdo,$target,$owners)>=$level) { $reply('⛔ Нельзя забанить пользователя с равными или более высокими правами.'); break; }
                $expires=$duration?time()+$duration:0;
                $s=$pdo->prepare('INSERT INTO bans(user_id,actor_id,reason,expires_at,created_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET actor_id=excluded.actor_id,reason=excluded.reason,expires_at=excluded.expires_at,created_at=excluded.created_at');
                $s->execute([$target,$actor,$reason?:'не указана',$expires,nowstr()]); audit($pdo,$peer,$actor,'ban',$target,$reason);
                try { if ($peer>=2000000000) vk('messages.removeChatUser',['chat_id'=>$peer-2000000000,'user_id'=>$target]); $extra=' Пользователь удалён из беседы (если у бота есть права).'; } catch(Throwable $e) { $extra=' VK не разрешил удалить пользователя из беседы: '.$e->getMessage(); }
                $reply("🔨 id{$target} внесён в бан-лист.\nПричина: ".($reason?:'не указана').$extra); break;
            case 'unban':
                if (!$need(60)) break;
                if (!$target) { $reply('Использование: /unban ID'); break; }
                $pdo->prepare('DELETE FROM bans WHERE user_id=?')->execute([$target]); audit($pdo,$peer,$actor,'unban',$target);
                $reply("✅ Бан id{$target} снят в системе бота. Автоматическое добавление обратно в беседу не выполняется."); break;
            case 'kick':
                if (!$need(40)) break;
                if (!$target) { $reply('Использование: /kick ID'); break; }
                if (priorityFor($pdo,$target,$owners)>=$level) { $reply('⛔ Нельзя кикнуть пользователя с равными или более высокими правами.'); break; }
                if ($peer<2000000000) { $reply('Команда кика работает только в беседе.'); break; }
                vk('messages.removeChatUser',['chat_id'=>$peer-2000000000,'user_id'=>$target]); audit($pdo,$peer,$actor,'kick',$target);
                $reply("👢 id{$target} удалён из беседы."); break;
            case 'setrole':
                if (!$need(60)) break;
                $target=$target ?: 0; $roleRaw=trim(implode(' ',array_slice($args,1)));
                if (!$target || $roleRaw==='') { $reply('Использование: /setrole ID помощник|модератор|администратор'); break; }
                $map=['участник'=>['Участник',0],'помощник'=>['Помощник',20],'модератор'=>['Модератор',40],'администратор'=>['Администратор',60],'ст.администратор'=>['Ст. администратор',80],'старший'=>['Ст. администратор',80]];
                $key=mb_strtolower($roleRaw);
                if (!isset($map[$key])) { $reply('Роли: участник, помощник, модератор, администратор, ст.администратор.'); break; }
                if (priorityFor($pdo,$target,$owners)>=$level) { $reply('⛔ Нельзя менять роль пользователя с равными или более высокими правами.'); break; }
                [$rname,$rp]=$map[$key];
                $s=$pdo->prepare('INSERT INTO roles(user_id,role,priority,granted_by,created_at) VALUES(?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET role=excluded.role,priority=excluded.priority,granted_by=excluded.granted_by,created_at=excluded.created_at');
                $s->execute([$target,$rname,$rp,$actor,nowstr()]); audit($pdo,$peer,$actor,'setrole',$target,$rname);
                $reply("✅ id{$target}: выдана роль «{$rname}»."); break;
            case 'delrole':
                if (!$need(60)) break;
                if (!$target) { $reply('Использование: /delrole ID'); break; }
                if (priorityFor($pdo,$target,$owners)>=$level) { $reply('⛔ Нельзя снять роль у пользователя с равными или более высокими правами.'); break; }
                $pdo->prepare('DELETE FROM roles WHERE user_id=?')->execute([$target]); audit($pdo,$peer,$actor,'delrole',$target);
                $reply("✅ Роль id{$target} сброшена до участника."); break;
            case 'addws':
                if (!in_array($actor,$owners,true)) { $reply('⛔ Команда доступна только ID из OWNER_IDS.'); break; }
                if (!$target) { $reply('Использование: /addws ID'); break; }
                $s=$pdo->prepare('INSERT OR IGNORE INTO superusers(user_id,granted_by,created_at) VALUES(?,?,?)'); $s->execute([$target,$actor,nowstr()]);
                audit($pdo,$peer,$actor,'addws',$target); $reply("⚡ id{$target} получил супердоступ."); break;
            case 'delws':
                if (!in_array($actor,$owners,true)) { $reply('⛔ Команда доступна только ID из OWNER_IDS.'); break; }
                if (!$target) { $reply('Использование: /delws ID'); break; }
                $pdo->prepare('DELETE FROM superusers WHERE user_id=?')->execute([$target]); audit($pdo,$peer,$actor,'delws',$target);
                $reply("✅ Супердоступ id{$target} снят."); break;
            case 'nick':
                if (!$need(20)) break;
                if (!$target || count($args)<2) { $reply('Использование: /nick ID игровой_ник'); break; }
                $nick=trim(implode(' ',array_slice($args,1)));
                $s=$pdo->prepare('INSERT INTO nicknames(user_id,nickname,updated_by,updated_at) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET nickname=excluded.nickname,updated_by=excluded.updated_by,updated_at=excluded.updated_at');
                $s->execute([$target,$nick,$actor,nowstr()]); audit($pdo,$peer,$actor,'nick',$target,$nick);
                $reply("✅ Ник id{$target} сохранён: {$nick}"); break;
            case 'logs':
                if (!$need(40)) break;
                $filter=(int)($args[0]??0);
                if ($filter) { $s=$pdo->prepare('SELECT * FROM audit_log WHERE target_id=? ORDER BY id DESC LIMIT 10'); $s->execute([$filter]); $rows=$s->fetchAll(); }
                else $rows=$pdo->query('SELECT * FROM audit_log ORDER BY id DESC LIMIT 10')->fetchAll();
                if (!$rows) { $reply('Записей нет.'); break; }
                $out="📋 Последние действия:\n";
                foreach($rows as $r) $out.="#{$r['id']} {$r['action']} | id{$r['actor_id']} → id{$r['target_id']} | {$r['created_at']}\n";
                $reply(trim($out)); break;
            default:
                // Keep unknown messages quiet; only commands receive a response.
                break;
        }
    } catch (Throwable $e) {
        error_log('[command '.$command.'] '.$e->getMessage());
        $reply('⚠️ Ошибка выполнения команды. Проверьте права бота и настройки VK API.');
    }
}

echo "RAZE RUSSIA BOT starting. Group ID={$groupId}\n";
try {
    // Validate token and group access.
    vk('groups.getById', ['group_id'=>$groupId]);
    $lp = vk('groups.getLongPollServer', ['group_id'=>$groupId]);
    $server = (string)($lp['server'] ?? '');
    $key = (string)($lp['key'] ?? '');
    $ts = (string)($lp['ts'] ?? '');
    if ($server==='' || $key==='' || $ts==='') throw new RuntimeException('groups.getLongPollServer returned incomplete data');
    vk('groups.setLongPollSettings', [
        'group_id'=>$groupId,
        'enabled'=>1,
        'message_new'=>1,
        'message_reply'=>0,
        'message_edit'=>0,
        'message_allow'=>0,
        'message_deny'=>0,
        'photo_new'=>0,'audio_new'=>0,'video_new'=>0,'wall_reply_new'=>0,
        'wall_post_new'=>0,'wall_repost'=>0,'board_post_new'=>0,'market_comment_new'=>0,
        'group_change_settings'=>0,'group_officers_edit'=>0,'poll_vote_new'=>0,
        'group_join'=>0,'group_leave'=>0,'user_block'=>0,'user_unblock'=>0,
        'like_add'=>0,'like_remove'=>0,'message_event'=>0,' Donut' => 0
    ]);
    echo "Long Poll connected; message_new enabled.\n";
    while (true) {
        $url = $server . '?act=a_check&key=' . urlencode($key) . '&ts=' . urlencode($ts) . '&wait=' . $pollWait;
        $ch=curl_init($url);
        curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>$pollWait+10]);
        $body=curl_exec($ch); $err=curl_error($ch); curl_close($ch);
        if ($body===false || $err!=='') { error_log('[longpoll] '.$err); sleep(2); continue; }
        $data=json_decode($body,true);
        if (!is_array($data)) { sleep(1); continue; }
        if (isset($data['failed'])) {
            $failed=(int)$data['failed'];
            if ($failed===1) $ts=(string)($data['ts']??$ts);
            else {
                $lp=vk('groups.getLongPollServer',['group_id'=>$groupId]);
                $server=(string)$lp['server']; $key=(string)$lp['key']; $ts=(string)$lp['ts'];
            }
            continue;
        }
        if (isset($data['ts'])) $ts=(string)$data['ts'];
        foreach (($data['updates']??[]) as $update) {
            if (($update['type']??'')!=='message_new') continue;
            $msg=$update['object']['message'] ?? $update['object'] ?? null;
            if (is_array($msg)) processMessage($pdo,$msg,$ownerIds);
        }
    }
} catch (Throwable $e) {
    fwrite(STDERR, "FATAL: ".$e->getMessage()."\n");
    exit(1);
}
