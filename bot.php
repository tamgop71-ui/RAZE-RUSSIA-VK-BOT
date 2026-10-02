<?php
declare(strict_types=1);

$config = require __DIR__ . '/config.php';
date_default_timezone_set($config['timezone'] ?? 'Europe/Moscow');

$pdo = new PDO(
    "mysql:host={$config['mysql']['host']};port={$config['mysql']['port']};dbname={$config['mysql']['database']};charset={$config['mysql']['charset']}",
    $config['mysql']['username'],
    $config['mysql']['password'],
    [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]
);

function vk(string $method, array $params = []): array {
    global $config;
    $params['access_token'] = $config['vk_token'];
    $params['v'] = '5.199';
    $url = 'https://api.vk.com/method/' . $method . '?' . http_build_query($params);
    $raw = @file_get_contents($url);
    if ($raw === false) return ['error' => ['error_msg' => 'VK API request failed']];
    return json_decode($raw, true) ?: [];
}

function sendMessage(int $peerId, string $text, array $extra = []): void {
    $params = array_merge(['peer_id'=>$peerId,'random_id'=>random_int(-2147483648,2147483647),'message'=>$text], $extra);
    vk('messages.send', $params);
}

function commandParts(string $text): array {
    $text = trim($text);
    if ($text === '') return ['', []];
    $text = preg_replace('/^[!\/]+/u', '', $text);
    $parts = preg_split('/\s+/u', $text);
    $cmd = mb_strtolower(array_shift($parts));
    return [$cmd, $parts];
}

function rolePriority(PDO $pdo, int $peerId, int $userId): int {
    $s=$pdo->prepare("SELECT COALESCE(r.priority,0) p FROM chat_users u LEFT JOIN roles r ON r.id=u.role_id WHERE u.peer_id=? AND u.user_id=?");
    $s->execute([$peerId,$userId]);
    return (int)($s->fetch()['p'] ?? 0);
}

function ensureUser(PDO $pdo, int $peerId, int $userId): void {
    $s=$pdo->prepare("INSERT INTO chat_users(peer_id,user_id,role_id) VALUES(?,?,1)
      ON DUPLICATE KEY UPDATE last_seen=NOW()");
    $s->execute([$peerId,$userId]);
}

function targetId(array $event, array $args): ?int {
    if (!empty($args[0]) && preg_match('/^-?\d+$/', $args[0])) return abs((int)$args[0]);
    if (!empty($args[0]) && preg_match('/(?:id)?(\d+)/i', $args[0], $m)) return (int)$m[1];
    if (!empty($event['object']['reply_message']['from_id'])) return (int)$event['object']['reply_message']['from_id'];
    return null;
}

$raw=file_get_contents('php://input');
$event=json_decode($raw,true);
if (!$event) { http_response_code(200); exit('ok'); }
if (($event['type'] ?? '') !== 'message_new') { echo 'ok'; exit; }

$obj=$event['object'] ?? [];
$text=(string)($obj['text'] ?? '');
$peerId=(int)($obj['peer_id'] ?? 0);
$fromId=(int)($obj['from_id'] ?? 0);
if (!$peerId || !$fromId) { echo 'ok'; exit; }

ensureUser($pdo,$peerId,$fromId);
[$cmd,$args]=commandParts($text);
if ($cmd==='') { echo 'ok'; exit; }

$priority=rolePriority($pdo,$peerId,$fromId);
$owners=$config['owner_ids'] ?? [];
if (in_array($fromId,$owners,true)) $priority=100;

$need = [
 'мут'=>20,'унмут'=>20,'кик'=>20,'пред'=>20,'варн'=>20,'унварн'=>20,'снятьпред'=>20,
 'предупреждения'=>20,'getwarns'=>20,'getwarn'=>20,'getban'=>20,'getmute'=>20,
 'бан'=>20,'унбан'=>20,'сник'=>20,'рник'=>20,'нлист'=>20,'безников'=>20,'вызов'=>20,
 'role'=>40,'removerole'=>40,'помощник'=>40,'модер'=>40,'тишина'=>40,
 'gzov'=>40,'gkick'=>40,'gsnick'=>40,
 'gban'=>60,'gunban'=>60,'grole'=>60,'гмодер'=>60,'гпомощник'=>60,'удалить'=>60,'gm'=>60,'removegm'=>60,'history'=>60,'gms'=>60,
 'pin'=>80,'unpin'=>80,'admin'=>80,'gadmin'=>80,'newrole'=>80,'gnewrole'=>80,'delrole'=>80,'welcome'=>80,'setrules'=>80,'delrules'=>80,'неактив'=>80,'givemoney'=>80,'timeuved'=>80,
 'settings'=>100,'setup'=>100,'unity'=>100,'addunity'=>100,'createunity'=>100,'editunity'=>100,'removeunity'=>100,'sync'=>100,'spec'=>100,'gspec'=>100,'wipe'=>100,'games'=>100,'editcmd'=>100,'geditcmd'=>100,'gedit'=>100,'gsettings'=>100,'owner'=>100,'automod'=>100,
 'addws'=>100,'setlog'=>100,'zovvv'=>100,'gtimeuvedg'=>100,'gzovg'=>100,'reportedit'=>100,'getdialog'=>100,'getreport'=>100,'reports'=>100,'listunities'=>100,'listen'=>100,'chatlist'=>100,'userchats'=>100,'ahistory'=>100,'checkban'=>100
];

if (isset($need[$cmd]) && $priority < $need[$cmd]) {
    sendMessage($peerId,"🤖 У Вас недостаточно высокого приоритета для использования этой команды.\nНеобходимая роль: {$need[$cmd]}+");
    echo 'ok'; exit;
}

switch ($cmd) {
case 'пинг':
case 'статус':
    sendMessage($peerId,'🟢 RAZE RUSSIA BOT работает.');
    break;

case 'помощь':
case 'команды':
case 'help':
    sendMessage($peerId,"🤖 RAZE RUSSIA BOT\n\nОбщие: !пинг, !правила, !роли, !админы, !онлайн, !myid\nМодерация: !мут, !кик, !пред, !бан, !унбан, !getwarn, !getban, !getmute\nНики: !ник, !сник, !рник, !нлист\nРоли: !role, !removerole, !помощник, !модер\nАдмин: !gban, !grole, !gm, !admin, !gadmin\nВладелец: !settings, !setup, !sync, !games, !automod\nПоддержка: /report, /reports, /getreport, /getdialog");
    break;

case 'myid':
case 'thereid':
    sendMessage($peerId,"🆔 ID беседы: {$peerId}");
    break;

case 'роли':
    sendMessage($peerId,"👑 Роли RAZE RUSSIA:\nУчастник — 0\nПомощник — 20\nМодератор — 40\nАдминистратор — 60\nСт. администратор — 80\nВладелец — 100");
    break;

case 'ник':
    $tid=targetId($event,$args) ?? $fromId;
    $s=$pdo->prepare("SELECT nickname FROM chat_users WHERE peer_id=? AND user_id=?");
    $s->execute([$peerId,$tid]);
    $n=$s->fetchColumn();
    sendMessage($peerId,$n ? "🏷 Ник: {$n}" : "🏷 Ник не установлен.");
    break;

case 'сник':
    $tid=targetId($event,$args);
    $nick=trim(implode(' ', array_slice($args,1)));
    if (!$tid || $nick==='') { sendMessage($peerId,"Использование: !сник [ID] [никнейм]"); break; }
    $s=$pdo->prepare("INSERT INTO chat_users(peer_id,user_id,nickname) VALUES(?,?,?) ON DUPLICATE KEY UPDATE nickname=VALUES(nickname)");
    $s->execute([$peerId,$tid,$nick]);
    sendMessage($peerId,"🏷 Ник пользователя установлен: {$nick}");
    break;

case 'рник':
    $tid=targetId($event,$args) ?? $fromId;
    $pdo->prepare("UPDATE chat_users SET nickname=NULL WHERE peer_id=? AND user_id=?")->execute([$peerId,$tid]);
    sendMessage($peerId,"🏷 Ник удалён.");
    break;

case 'пред':
case 'варн':
    $tid=targetId($event,$args);
    if (!$tid) { sendMessage($peerId,"Использование: !пред [ID] [причина]"); break; }
    $reason=trim(implode(' ',array_slice($args,1))) ?: 'Не указана';
    $pdo->prepare("INSERT INTO warnings(peer_id,user_id,moderator_id,reason) VALUES(?,?,?,?)")->execute([$peerId,$tid,$fromId,$reason]);
    $s=$pdo->prepare("SELECT COUNT(*) FROM warnings WHERE peer_id=? AND user_id=? AND active=1");
    $s->execute([$peerId,$tid]); $cnt=(int)$s->fetchColumn();
    sendMessage($peerId,"⚠️ Пользователь получил предупреждение ({$cnt}/3).\nПричина: {$reason}");
    break;

case 'предупреждения':
case 'getwarns':
    $tid=targetId($event,$args) ?? $fromId;
    $s=$pdo->prepare("SELECT COUNT(*) FROM warnings WHERE peer_id=? AND user_id=? AND active=1");
    $s->execute([$peerId,$tid]); $cnt=(int)$s->fetchColumn();
    sendMessage($peerId,"⚠️ Активных предупреждений: {$cnt}");
    break;

case 'getwarn':
    $tid=targetId($event,$args) ?? $fromId;
    $s=$pdo->prepare("SELECT moderator_id,reason,created_at FROM warnings WHERE peer_id=? AND user_id=? AND active=1 ORDER BY id DESC LIMIT 10");
    $s->execute([$peerId,$tid]); $rows=$s->fetchAll();
    if (!$rows) { sendMessage($peerId,"⚠️ Активных предупреждений нет."); break; }
    $out="⚠️ Предупреждения:\n";
    foreach($rows as $i=>$r) $out.=($i+1).". Выдал: {$r['moderator_id']} | {$r['created_at']} | {$r['reason']}\n";
    sendMessage($peerId,$out);
    break;

case 'унварн':
case 'снятьпред':
    $tid=targetId($event,$args) ?? $fromId;
    $s=$pdo->prepare("SELECT id FROM warnings WHERE peer_id=? AND user_id=? AND active=1 ORDER BY id DESC LIMIT 1");
    $s->execute([$peerId,$tid]); $id=$s->fetchColumn();
    if ($id) {
        $pdo->prepare("UPDATE warnings SET active=0 WHERE id=?")->execute([$id]);
        sendMessage($peerId,"✅ Последнее предупреждение снято.");
    } else sendMessage($peerId,"У пользователя нет активных предупреждений.");
    break;

case 'бан':
    $tid=targetId($event,$args);
    $days=(int)($args[1]??0);
    $reason=trim(implode(' ',array_slice($args,2))) ?: 'Не указана';
    if (!$tid || $days<1) { sendMessage($peerId,"Использование: !бан [ID] [дни] [причина]"); break; }
    if (rolePriority($pdo,$peerId,$tid) >= $priority) { sendMessage($peerId,"⛔ Нельзя наказать пользователя с ролью выше или равной вашей."); break; }
    $until=date('Y-m-d H:i:s',time()+$days*86400);
    $pdo->prepare("INSERT INTO bans(peer_id,user_id,moderator_id,days,reason,expires_at) VALUES(?,?,?,?,?,?)")->execute([$peerId,$tid,$fromId,$days,$reason,$until]);
    vk('messages.removeChatUser',['chat_id'=>$peerId-2000000000,'member_id'=>$tid]);
    sendMessage($peerId,"🔨 Пользователь заблокирован на {$days} дн.\nПричина: {$reason}");
    break;

case 'мут':
    $tid=targetId($event,$args);
    $minutes=(int)($args[1]??0);
    $reason=trim(implode(' ',array_slice($args,2))) ?: 'Не указана';
    if (!$tid || $minutes<1) { sendMessage($peerId,"Использование: !мут [ID] [минуты] [причина]"); break; }
    $until=date('Y-m-d H:i:s',time()+$minutes*60);
    $pdo->prepare("INSERT INTO mutes(peer_id,user_id,moderator_id,minutes,reason,expires_at) VALUES(?,?,?,?,?,?)")->execute([$peerId,$tid,$fromId,$minutes,$reason,$until]);
    sendMessage($peerId,"🔇 Пользователь получил мут на {$minutes} мин.\nПричина: {$reason}");
    break;

case 'унмут':
    $tid=targetId($event,$args);
    if ($tid) {
        $pdo->prepare("UPDATE mutes SET active=0 WHERE peer_id=? AND user_id=? AND active=1")->execute([$peerId,$tid]);
        sendMessage($peerId,"🔊 Мут снят.");
    } else sendMessage($peerId,"Использование: !унмут [ID]");
    break;

case 'кик':
    $tid=targetId($event,$args);
    if (!$tid) { sendMessage($peerId,"Использование: !кик [ID] [причина]"); break; }
    if (rolePriority($pdo,$peerId,$tid) >= $priority) { sendMessage($peerId,"⛔ Нельзя исключить пользователя с ролью выше или равной вашей."); break; }
    vk('messages.removeChatUser',['chat_id'=>$peerId-2000000000,'member_id'=>$tid]);
    sendMessage($peerId,"👢 Пользователь исключён из беседы.");
    break;

case 'setlog':
    $logPeer=(int)($args[0]??0);
    $pdo->prepare("INSERT INTO chat_settings(peer_id,log_peer_id) VALUES(?,?) ON DUPLICATE KEY UPDATE log_peer_id=VALUES(log_peer_id)")->execute([$peerId,$logPeer]);
    sendMessage($peerId,$logPeer ? "📝 Лог-чат установлен: {$logPeer}" : "📝 Лог-чат отключён.");
    break;

case 'report':
    $body=trim(implode(' ',$args));
    if ($body==='') { sendMessage($peerId,"Использование: /report [текст]"); break; }
    $pdo->prepare("INSERT INTO reports(peer_id,user_id,text) VALUES(?,?,?)")->execute([$peerId,$fromId,$body]);
    sendMessage($peerId,"📨 Ваш репорт отправлен администрации. Ожидайте ответа.");
    break;

case 'reports':
    $rows=$pdo->query("SELECT id,peer_id,user_id,LEFT(text,120) text,status,created_at FROM reports WHERE status='open' ORDER BY id DESC LIMIT 15")->fetchAll();
    if (!$rows) { sendMessage($peerId,"📭 Открытых тикетов нет."); break; }
    $out="📨 Открытые тикеты:\n";
    foreach($rows as $r) $out.="#{$r['id']} | user {$r['user_id']} | {$r['text']}\n";
    sendMessage($peerId,$out);
    break;

default:
    // Не отвечаем на обычные сообщения и неизвестные команды.
    break;
}
echo 'ok';
