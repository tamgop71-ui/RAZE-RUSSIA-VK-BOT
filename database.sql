<?php
declare(strict_types=1);
/* RAZE RUSSIA VK BOT - expanded command build for Bothost.
 * Uses VK Groups Long Poll + MySQL/MariaDB. messages.send intentionally has NO reply_to.
 */

fwrite(STDOUT,"=== RAZE RUSSIA BOT FULL BUILD - NO REPLY_TO ===\n");
$token=trim((string)getenv('VK_TOKEN')); $groupId=(int)getenv('VK_GROUP_ID');
$ownerIds=array_values(array_filter(array_map('intval',preg_split('/[,;\s]+/',trim((string)getenv('OWNER_IDS'))?:''))));
date_default_timezone_set(trim((string)getenv('TZ'))?:'Europe/Moscow');
$logFile='';
if($token===''||$groupId<=0){fwrite(STDERR,"ERROR: set VK_TOKEN and VK_GROUP_ID\n");exit(1);} 

function vk(string $m,array $p=[]):array{global $token;$p['access_token']=$token;$p['v']='5.199';$u='https://api.vk.com/method/'.$m.'?'.http_build_query($p);$c=stream_context_create(['http'=>['timeout'=>35,'ignore_errors'=>true]]);$r=@file_get_contents($u,false,$c);if($r===false)return['error'=>['error_msg'=>'VK API request failed']];$j=json_decode($r,true);return is_array($j)?$j:['error'=>['error_msg'=>'Invalid VK response']];}
function botLog(string $line):void{global $logFile;$line='['.date('Y-m-d H:i:s').'] '.$line.PHP_EOL;fwrite(STDOUT,$line);if($logFile!=='')@file_put_contents($logFile,$line,FILE_APPEND|LOCK_EX);}
function sendMessage(int $peer,string $text):bool{$r=vk('messages.send',['peer_id'=>$peer,'random_id'=>random_int(-2147483648,2147483647),'message'=>$text]);if(isset($r['error'])){botLog('SEND ERROR peer='.$peer.' '.json_encode($r['error'],JSON_UNESCAPED_UNICODE));return false;}botLog("SENT to {$peer}");return true;}
function dmStatus(int $uid):array{
  $gid=abs((int)getenv('VK_GROUP_ID'));
  $r=vk('messages.isMessagesFromGroupAllowed',['group_id'=>$gid,'user_id'=>$uid]);
  if(isset($r['error'])){
    botLog('DM CHECK ERROR uid='.$uid.' '.json_encode($r['error'],JSON_UNESCAPED_UNICODE));
    return ['ok'=>false,'allowed'=>null,'error'=>$r['error']['error_msg']??'VK API error'];
  }
  $allowed=(int)($r['response']['is_allowed']??0)===1;
  return ['ok'=>true,'allowed'=>$allowed,'error'=>null];
}
function sendUser(int $uid,string $text):bool{
  $st=dmStatus($uid);
  if($st['ok'] && $st['allowed']===false){
    botLog('DM BLOCKED uid='.$uid.' — user has not allowed messages from group');
    return false;
  }
  $r=vk('messages.send',['user_id'=>$uid,'random_id'=>random_int(-2147483648,2147483647),'message'=>$text]);
  if(isset($r['error'])){botLog('DM SEND ERROR uid='.$uid.' '.json_encode($r['error'],JSON_UNESCAPED_UNICODE));return false;}
  botLog("DM SENT uid={$uid}");return true;
}
function startupCheck():void{global $groupId;$r=vk('groups.getById',['group_id'=>$groupId]);if(isset($r['error'])){fwrite(STDERR,'VK getById ERROR: '.json_encode($r['error'],JSON_UNESCAPED_UNICODE)."\n");return;}$g=$r['response']['groups'][0]??[];fwrite(STDOUT,'VK group: '.($g['name']??'unknown')." (#{$groupId})\n");$s=vk('groups.setLongPollSettings',['group_id'=>$groupId,'api_version'=>'5.199','enabled'=>1,'message_new'=>1,'message_event'=>1,'message_reply'=>0,'message_allow'=>0,'message_deny'=>0,'message_edit'=>0,'message_event'=>1,'message_typing_state'=>0,'message_reaction_event'=>0,'message_reaction_new'=>0,'message_reaction_remove'=>0]);if(isset($s['error']))fwrite(STDERR,'Long Poll settings ERROR: '.json_encode($s['error'],JSON_UNESCAPED_UNICODE)."\n");else fwrite(STDOUT,"Long Poll: message_new enabled\n");}

$dbHost=trim((string)getenv('MYSQL_HOST'));
$dbPort=(int)(getenv('MYSQL_PORT') ?: 3306);
$dbName=trim((string)getenv('MYSQL_DATABASE'));
$dbUser=trim((string)getenv('MYSQL_USER'));
$dbPass=(string)getenv('MYSQL_PASSWORD');
if($dbHost===''||$dbName===''||$dbUser===''){
    fwrite(STDERR,"ERROR: set MYSQL_HOST, MYSQL_DATABASE and MYSQL_USER\n");
    exit(1);
}
if(!extension_loaded('pdo_mysql')){
    fwrite(STDERR,"ERROR: pdo_mysql extension is not loaded\n");
    exit(1);
}
try{
    $dsn="mysql:host={$dbHost};port={$dbPort};dbname={$dbName};charset=utf8mb4";
    $pdo=new PDO($dsn,$dbUser,$dbPass,[
        PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES=>false,
    ]);
    $pdo->exec("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci");
    $pdo->exec("SET time_zone = '+00:00'");
    botLog("MYSQL CONNECTED host={$dbHost}:{$dbPort} db={$dbName}");
}catch(Throwable $e){
    fwrite(STDERR,"MYSQL CONNECTION ERROR: ".$e->getMessage()."\n");
    exit(1);
}
$logFile=__DIR__.'/data/bot.log';
@mkdir(__DIR__.'/data',0775,true);
@touch($logFile);

$pdo->exec(<<<SQL
CREATE TABLE IF NOT EXISTS roles(id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,name VARCHAR(191) NOT NULL UNIQUE,priority INT NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS chat_users(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,peer_id BIGINT NOT NULL,user_id BIGINT NOT NULL,role_id INT NOT NULL DEFAULT 1,nickname VARCHAR(255) NULL,immunity TINYINT NOT NULL DEFAULT 0,last_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,messages INT NOT NULL DEFAULT 0,UNIQUE KEY uq_chat_user(peer_id,user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS chat_settings(peer_id BIGINT NOT NULL PRIMARY KEY,rules TEXT,welcome TEXT,silence_until DATETIME NULL,games_enabled TINYINT NOT NULL DEFAULT 0,automod_enabled TINYINT NOT NULL DEFAULT 0,mentions_enabled TINYINT NOT NULL DEFAULT 1,report_notify_peer BIGINT NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS warnings(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,peer_id BIGINT NOT NULL,user_id BIGINT NOT NULL,moderator_id BIGINT NOT NULL,reason TEXT NOT NULL,active TINYINT NOT NULL DEFAULT 1,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS bans(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,peer_id BIGINT NOT NULL,user_id BIGINT NOT NULL,moderator_id BIGINT NOT NULL,days INT NOT NULL,reason TEXT NOT NULL,active TINYINT NOT NULL DEFAULT 1,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,expires_at DATETIME NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS mutes(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,peer_id BIGINT NOT NULL,user_id BIGINT NOT NULL,moderator_id BIGINT NOT NULL,minutes INT NOT NULL,reason TEXT NOT NULL,active TINYINT NOT NULL DEFAULT 1,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,expires_at DATETIME NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS logs(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,peer_id BIGINT NOT NULL,actor_id BIGINT NOT NULL,target_id BIGINT NULL,action VARCHAR(100) NOT NULL,details TEXT,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,INDEX idx_logs_target(target_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS nicknames(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,peer_id BIGINT NOT NULL,user_id BIGINT NOT NULL,nickname VARCHAR(255) NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,UNIQUE KEY uq_nickname(peer_id,user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS reports(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,peer_id BIGINT NOT NULL,user_id BIGINT NOT NULL,text TEXT NOT NULL,status VARCHAR(32) NOT NULL DEFAULT 'open',created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,assigned_to BIGINT NULL,closed_at DATETIME NULL,closed_by BIGINT NULL,close_reason TEXT NULL,answer_count INT NOT NULL DEFAULT 0,last_answer_at DATETIME NULL,INDEX idx_reports_status(status),INDEX idx_reports_user(user_id),INDEX idx_reports_assigned(assigned_to)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS report_messages(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,report_id BIGINT NOT NULL,user_id BIGINT NOT NULL,text TEXT NOT NULL,direction VARCHAR(16) NOT NULL DEFAULT 'user',created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,INDEX idx_report_messages(report_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS economy(peer_id BIGINT NOT NULL,user_id BIGINT NOT NULL,balance BIGINT NOT NULL DEFAULT 1500,country VARCHAR(191) NULL,partner_id BIGINT NULL,registered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,last_bonus DATETIME NULL,last_casino DATETIME NULL,PRIMARY KEY(peer_id,user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS marriages(peer_id BIGINT NOT NULL,user1 BIGINT NOT NULL,user2 BIGINT NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY(peer_id,user1,user2)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS countries(peer_id BIGINT NOT NULL,name VARCHAR(191) NOT NULL,owner_id BIGINT NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY(peer_id,name)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS unities(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,name VARCHAR(191) NOT NULL UNIQUE,owner_id BIGINT NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS unity_chats(unity_id BIGINT NOT NULL,peer_id BIGINT NOT NULL PRIMARY KEY) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS superusers(user_id BIGINT NOT NULL PRIMARY KEY,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS schedules(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,peer_id BIGINT NOT NULL,owner_id BIGINT NOT NULL,every_minutes INT NOT NULL,text TEXT NOT NULL,next_at DATETIME NOT NULL,active TINYINT NOT NULL DEFAULT 1,global_flag TINYINT NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS listenings(peer_id BIGINT NOT NULL PRIMARY KEY,owner_id BIGINT NOT NULL,expires_at DATETIME NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS bot_meta(k VARCHAR(191) NOT NULL PRIMARY KEY,v TEXT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS stars(peer_id BIGINT NOT NULL,user_id BIGINT NOT NULL,granted_by BIGINT NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,PRIMARY KEY(peer_id,user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL);
$pdo->exec("INSERT IGNORE INTO roles(id,name,priority) VALUES(1,'Участник',0),(2,'Помощник',20),(3,'Модератор',40),(4,'Администратор',60),(5,'Ст. администратор',80),(6,'Владелец',100)");
function ensureColumn(PDO $p,string $table,string $column,string $definition):void{
    $stmt=$p->prepare("SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?");
    $stmt->execute([$table,$column]);
    if(!(int)$stmt->fetchColumn()) $p->exec("ALTER TABLE `".str_replace('`','',$table)."` ADD COLUMN `".str_replace('`','',$column)."` {$definition}");
} 
ensureColumn($pdo,'chat_users','messages','INT NOT NULL DEFAULT 0');
ensureColumn($pdo,'chat_settings','mentions_enabled','TINYINT NOT NULL DEFAULT 1');
ensureColumn($pdo,'chat_settings','report_notify_peer','BIGINT NOT NULL DEFAULT 0');
ensureColumn($pdo,'reports','assigned_to','BIGINT NULL');
ensureColumn($pdo,'reports','closed_at','DATETIME NULL');
ensureColumn($pdo,'reports','closed_by','BIGINT NULL');
ensureColumn($pdo,'reports','close_reason','TEXT NULL');
ensureColumn($pdo,'reports','answer_count','INT NOT NULL DEFAULT 0');
ensureColumn($pdo,'reports','last_answer_at','DATETIME NULL');
ensureColumn($pdo,'report_messages','direction',"VARCHAR(16) NOT NULL DEFAULT 'user'");


function ensureUser(PDO $p,int $peer,int $uid):void{$s=$p->prepare("INSERT INTO chat_users(peer_id,user_id,role_id,last_seen) VALUES(?,?,1,CURRENT_TIMESTAMP) ON DUPLICATE KEY UPDATE last_seen=CURRENT_TIMESTAMP,messages=messages+1");$s->execute([$peer,$uid]);$e=$p->prepare('INSERT IGNORE INTO economy(peer_id,user_id) VALUES(?,?)');$e->execute([$peer,$uid]);}
function priority(PDO $p,int $peer,int $uid):int{$s=$p->prepare('SELECT r.priority FROM chat_users u JOIN roles r ON r.id=u.role_id WHERE u.peer_id=? AND u.user_id=?');$s->execute([$peer,$uid]);return(int)($s->fetchColumn()?:0);}
function isSuper(int $uid):bool{global $pdo,$ownerIds;if(in_array($uid,$ownerIds,true))return true;$s=$pdo->prepare('SELECT 1 FROM superusers WHERE user_id=?');$s->execute([$uid]);return(bool)$s->fetchColumn();}
function level(PDO $p,int $peer,int $uid):int{return isSuper($uid)?100:priority($p,$peer,$uid);}
function loga(PDO $p,int $peer,int $actor,?int $target,string $action,string $details=''):void{$s=$p->prepare('INSERT INTO logs(peer_id,actor_id,target_id,action,details) VALUES(?,?,?,?,?)');$s->execute([$peer,$actor,$target,$action,$details]);}
function expire(PDO $p):void{$p->exec("UPDATE bans SET active=0 WHERE active=1 AND expires_at IS NOT NULL AND expires_at<=NOW()");$p->exec("UPDATE mutes SET active=0 WHERE active=1 AND expires_at IS NOT NULL AND expires_at<=NOW()");}
function parseCommand(string $t):array{$t=trim($t);if($t==='')return['',[]];$t=preg_replace('/^[!\/\.,#?]+/u','',$t);$a=preg_split('/\s+/u',$t);$cmd=mb_strtolower((string)array_shift($a));$aliases=['commands'=>'команды','cmd'=>'команды','rules'=>'правила','roles'=>'роли','admins'=>'админы','online'=>'онлайн','profile'=>'профиль','bonus'=>'бонус','casino'=>'казино','transfer'=>'перевод','top'=>'топ','citizenship'=>'гражданство','country'=>'страна','countries'=>'страны','marriage'=>'брак','divorce'=>'развод','hug'=>'обнять','try'=>'попытка','beer'=>'пиво','mute'=>'мут','unmute'=>'унмут','kick'=>'кик','warn'=>'пред','unwarn'=>'унварн','warnings'=>'предупреждения','warns'=>'предупреждения','ban'=>'бан','unban'=>'унбан','nickname'=>'ник','nick'=>'ник','setnick'=>'сник','removenick'=>'рник','nicklist'=>'нлист','nonicks'=>'безников','call'=>'вызов','chatinfo'=>'чатинфо','register'=>'reg','mention'=>'упоминать','nomention'=>'неупоминать','helper'=>'помощник','moder'=>'модер','silence'=>'тишина','findnick'=>'понику','globalcall'=>'gzov','globalkick'=>'gkick','globalnick'=>'gsnick','giveadmin'=>'admin','givehelper'=>'гпомощник','givemoder'=>'гмодер','globalban'=>'gban','globalunban'=>'gunban','globalrole'=>'grole','delete'=>'удалить','immunity'=>'gm','removeimmunity'=>'removegm','immunities'=>'gms','newrole'=>'newrole','delrole'=>'delrole','welcome'=>'welcome','setrules'=>'setrules','deleterules'=>'delrules','inactive'=>'неактив','givemoney'=>'givemoney','money'=>'givemoney','timeannounce'=>'timeuved','settings'=>'settings','setup'=>'setup','unity'=>'unity','addunity'=>'addunity','createunity'=>'createunity','editunity'=>'editunity','removeunity'=>'removeunity','sync'=>'sync','owner'=>'owner','automod'=>'automod','addsuper'=>'addws','super'=>'addws','setlog'=>'setlog','globalcallall'=>'zovvv','globalannounce'=>'gtimeuvedg','globalcallg'=>'gzovg','reportedit'=>'reportedit','getdialog'=>'getdialog','getreport'=>'getreport','reports'=>'reports','listunities'=>'listunities','listen'=>'listen','chatlist'=>'chatlist','userchats'=>'userchats','ahistory'=>'ahistory','checkban'=>'checkban','rep'=>'report','ticket'=>'getreport','reply'=>'ответ','ответить'=>'ответ','take'=>'взять','claim'=>'взять','close'=>'закрыть','reopen'=>'открытьрепорт','reportdialog'=>'getdialog','repdialog'=>'getdialog','myreports'=>'мои','superlist'=>'суперы','addsuper'=>'добавитьсупер','delsuper'=>'удалитьсупер','checksuper'=>'проверкасуперов','checksupers'=>'проверкасуперов','тестсуперов'=>'проверкасуперов','testreport'=>'тестрепорт'];if(isset($aliases[$cmd]))$cmd=$aliases[$cmd];return[$cmd,$a];}
function target(array $o,array $a):?int{if(isset($o['reply_message']['from_id']))return abs((int)$o['reply_message']['from_id']);if(!empty($a[0])&&preg_match('/^\[id(\d+)\|/i',$a[0],$m))return(int)$m[1];if(!empty($a[0])&&preg_match('/^(?:id)?(\d+)$/i',$a[0],$m))return(int)$m[1];if(!empty($a[0])&&preg_match('/(?:vk\.com\/id|id)(\d+)/i',$a[0],$m))return(int)$m[1];return null;}
function nameOf(int $uid):string{$r=vk('users.get',['user_ids'=>$uid,'fields'=>'first_name,last_name']);$u=$r['response'][0]??[];$n=trim(($u['first_name']??'').' '.($u['last_name']??''));$n=$n!==''?$n:"ID {$uid}";$n=str_replace(['[',']','|'],'',$n);return '[id'.$uid.'|'.$n.']';}
function plainName(int $uid):string{$n=nameOf($uid);return preg_replace('/^\[id\d+\|(.+)\]$/u','$1',$n)??$n;}
function superIds():array{global $pdo,$ownerIds;$ids=$ownerIds;try{$q=$pdo->query('SELECT user_id FROM superusers');foreach($q as $r)$ids[]=(int)$r['user_id'];}catch(Throwable $e){}return array_values(array_unique(array_filter($ids)));}
function reportButtons(int $rid):string{
    return json_encode(['inline'=>true,'buttons'=>[
        [['action'=>['type'=>'callback','label'=>'📥 Взять','payload'=>json_encode(['cmd'=>'report_take','id'=>$rid],JSON_UNESCAPED_UNICODE)],'color'=>'primary'],['action'=>['type'=>'callback','label'=>'✉️ Ответить','payload'=>json_encode(['cmd'=>'report_reply_hint','id'=>$rid],JSON_UNESCAPED_UNICODE)],'color'=>'positive']],
        [['action'=>['type'=>'callback','label'=>'📄 Открыть','payload'=>json_encode(['cmd'=>'report_open','id'=>$rid],JSON_UNESCAPED_UNICODE)],'color'=>'secondary'],['action'=>['type'=>'callback','label'=>'✅ Закрыть','payload'=>json_encode(['cmd'=>'report_close','id'=>$rid],JSON_UNESCAPED_UNICODE)],'color'=>'negative']]
    ]],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
}
function sendUserKeyboard(int $uid,string $text,string $keyboard):bool{
    $r=vk('messages.send',['user_id'=>$uid,'random_id'=>random_int(-2147483648,2147483647),'message'=>$text,'keyboard'=>$keyboard]);
    if(isset($r['error'])){botLog('DM SEND ERROR uid='.$uid.' '.json_encode($r['error'],JSON_UNESCAPED_UNICODE));return false;}
    botLog("DM SENT uid={$uid} with keyboard");return true;
}
function notifyReportSuper(PDO $p,int $peer,int $rid,int $from,string $text):void{
    $ids=superIds();
    if(!$ids){botLog("REPORT #{$rid}: NO SUPERUSERS/OWNER_IDS configured");return;}
    $msg="🆕 НОВЫЙ РЕПОРТ #{$rid}\n\n👤 От: ".nameOf($from)." (ID {$from})\n💬 Беседа: {$peer}\n📝 {$text}\n\nКоманды:\n• !ответ {$rid} текст — ответить\n• !взять {$rid} — взять тикет\n• !закрыть {$rid} — закрыть\n• !репорт {$rid} — открыть карточку";
    $delivered=0;
    foreach($ids as $uid){
        $st=dmStatus($uid);
        if($st['ok'] && $st['allowed']===true){
            if(sendUserKeyboard($uid,$msg,reportButtons($rid)))$delivered++;
            continue;
        }
        if($st['ok'] && $st['allowed']===false){
            botLog("REPORT #{$rid}: DM NOT ALLOWED uid={$uid}");
        } else {
            botLog("REPORT #{$rid}: DM CHECK FAILED uid={$uid}");
        }
    }
    botLog("REPORT #{$rid}: DM delivered {$delivered}/".count($ids));
}
function getReport(PDO $p,int $id):?array{$q=$p->prepare('SELECT * FROM reports WHERE id=?');$q->execute([$id]);$r=$q->fetch();return $r?:null;}
function reportCard(PDO $p,int $id):string{
    $r=getReport($p,$id);if(!$r)return '❌ Репорт #'.$id.' не найден.';
    $assigned=$r['assigned_to']?(nameOf((int)$r['assigned_to'])." (ID {$r['assigned_to']})"):'не назначен';
    $closed=$r['closed_at']?"\nЗакрыт: {$r['closed_at']}" : '';
    return "📨 РЕПОРТ #{$id}\n\n📌 Статус: {$r['status']}\n👤 Автор: ".nameOf((int)$r['user_id'])." (ID {$r['user_id']})\n💬 Беседа: {$r['peer_id']}\n🕒 Создан: {$r['created_at']}\n👮 Ответственный: {$assigned}\n💬 Ответов: ".(int)$r['answer_count']."{$closed}\n\n📝 {$r['text']}";
}
function addReportMessage(PDO $p,int $rid,int $uid,string $text,string $direction='staff'):void{$p->prepare('INSERT INTO report_messages(report_id,user_id,text,direction) VALUES(?,?,?,?)')->execute([$rid,$uid,$text,$direction]);}
function reportReply(PDO $p,int $rid,int $staff,string $text):bool{
    $r=getReport($p,$rid);if(!$r||$r['status']==='closed')return false;
    addReportMessage($p,$rid,$staff,$text,'staff');
    $p->prepare("UPDATE reports SET status='in_progress',assigned_to=?,answer_count=answer_count+1,last_answer_at=NOW() WHERE id=?")->execute([$staff,$rid]);
    return sendUser((int)$r['user_id'],"📩 Ответ по репорту #{$rid}\n\n👮 ".plainName($staff).":\n{$text}\n\nЕсли вопрос решён, администрация закроет репорт. Для нового обращения используйте /report текст.");
}
function reportTake(PDO $p,int $rid,int $staff):?array{$r=getReport($p,$rid);if(!$r||$r['status']==='closed')return $r?:null;$p->prepare("UPDATE reports SET status='in_progress',assigned_to=? WHERE id=?")->execute([$staff,$rid]);return getReport($p,$rid);}
function reportClose(PDO $p,int $rid,int $staff,string $reason='Решено'):bool{
    $r=getReport($p,$rid);if(!$r)return false;
    $p->prepare("UPDATE reports SET status='closed',closed_at=NOW(),closed_by=?,close_reason=? WHERE id=?")->execute([$staff,$reason,$rid]);
    addReportMessage($p,$rid,$staff,'Закрыт: '.$reason,'staff');
    return sendUser((int)$r['user_id'],"✅ Репорт #{$rid} закрыт.\n\nПричина: {$reason}\n\nЕсли вопрос остался, создайте новый /report.");
}
function reportReopen(PDO $p,int $rid,int $staff):bool{$r=getReport($p,$rid);if(!$r)return false;$p->prepare("UPDATE reports SET status='open',closed_at=NULL,closed_by=NULL,close_reason=NULL,assigned_to=NULL WHERE id=?")->execute([$rid]);addReportMessage($p,$rid,$staff,'Репорт открыт заново','staff');return true;}
function reportList(PDO $p,string $status):string{$q=$p->prepare('SELECT id,user_id,status,assigned_to,created_at,text FROM reports WHERE status=? ORDER BY id DESC LIMIT 30');$q->execute([$status]);$rows=$q->fetchAll();if(!$rows)return '📨 Репортов со статусом «'.$status.'» нет.';$s="📨 Репорты — {$status}:\n\n";foreach($rows as $r){$s.="#{$r['id']} • ".nameOf((int)$r['user_id'])."\n📝 ".mb_substr($r['text'],0,120)."\n👮 ".($r['assigned_to']?plainName((int)$r['assigned_to']):'не взят')."\n🕒 {$r['created_at']}\n\n";}return $s;}
function reportDialog(PDO $p,int $id):string{$r=getReport($p,$id);if(!$r)return '❌ Репорт не найден.';$q=$p->prepare('SELECT user_id,text,direction,created_at FROM report_messages WHERE report_id=? ORDER BY id ASC');$q->execute([$id]);$s="💬 ДИАЛОГ РЕПОРТА #{$id}\n\n";foreach($q as $m){$who=$m['direction']==='staff'?'👮 '.plainName((int)$m['user_id']):'👤 '.plainName((int)$m['user_id']);$s.=$who." [{$m['created_at']}]\n{$m['text']}\n\n";}return mb_substr($s,0,3800);}
function targetName(int $uid):string{return nameOf($uid);}
function ensureEconomy(PDO $p,int $peer,int $uid):void{$p->prepare('INSERT IGNORE INTO economy(peer_id,user_id) VALUES(?,?)')->execute([$peer,$uid]);}
function amount(string $s):int{$s=mb_strtolower(str_replace(['₽',' ',','],'',$s));$m=1;if(str_ends_with($s,'кк')){$m=1000000;$s=substr($s,0,-2);}elseif(str_ends_with($s,'к')){$m=1000;$s=substr($s,0,-1);}return max(0,(int)round((float)$s*$m));}
function rulesText(PDO $p,int $peer):string{$s=$p->prepare('SELECT rules FROM chat_settings WHERE peer_id=?');$s->execute([$peer]);return(string)($s->fetchColumn()?:'Правила беседы ещё не настроены.');}
function requireLevel(int $have,int $need,string $role):?string{return $have<$need?"🤖 У Вас недостаточно высокий приоритет для использования этой команды.\nНеобходимая роль: '{$role}' (№{$need}), ваша роль: №{$have}.":null;}
function punishAllowed(PDO $p,int $peer,int $actor,int $target,int $need):?string{$al=level($p,$peer,$actor);$tl=priority($p,$peer,$target);if($actor===$target)return'❌ Нельзя применить наказание к самому себе.';if($tl>=$al)return'❌ Вы не можете применить наказание к пользователю, роль которого выше или равна вашей.';$s=$p->prepare('SELECT immunity FROM chat_users WHERE peer_id=? AND user_id=?');$s->execute([$peer,$target]);if((int)($s->fetchColumn()?:0)===1&&$al<100)return'❌ У пользователя включён иммунитет.';return null;}
function helpText():string{return <<<TXT
**RAZE RUSSIA — команды**

**Общие:**
!помощь / !команды / !help — список команд.
!пинг / !статус — проверка работы.
!правила — правила беседы.
!роли — роли и приоритеты.
!админы — администрация.
!онлайн — участники онлайн.
!history — ваша история наказаний.
!thereid / !myid — ID беседы.
/report [текст] — жалоба/идея.

**Репорты:**
!репорты — список открытых репортов.
!репорт [ID] — карточка репорта.
!диалогрепорта [ID] — история переписки.
!взять [ID] — взять репорт себе.
!ответ [ID] [текст] — ответить автору в ЛС.
!закрыть [ID] [причина] — закрыть репорт.
!открытьрепорт [ID] — переоткрыть.
!мои — мои открытые репорты.
!суперы — список супер-доступов.
!добавитьсупер [ID] — выдать супер-доступ.
!удалитьсупер [ID] — снять супер-доступ.
!упоминать / !неупоминать — настройки вызова.
!профиль — игровой профиль.
!бонус — ежедневный бонус.
!казино [ставка] — казино.
!перевод [ID] [сумма] — перевод.
!топ — топ балансов/сообщений.
!atop — общий топ.
!гражданство [страна], !страна, !страны.
!брак [ID], !развод, !браки.
!поцелуй [ID], !обнять [ID], !попытка [действие], !пиво.

**Помощник 20+:**
!мут [ID] [минуты] [причина]
!унмут [ID]
!кик [ID] [причина]
!пред / !варн [ID] [причина]
!унварн / !снятьпред [ID]
!предупреждения / !getwarns [ID]
!getwarn [ID]
!getban [ID]
!getmute [ID]
!warnlist / !преды
!бан [ID] [дни] [причина]
!унбан [ID]
!ник [ID], !сник [ID] [ник], !рник [ID]
!нлист, !безников
!вызов [текст]
!чатинфо
!reg [ID]

**Модератор 40+:**
!role [ID] [роль/приоритет]
!removerole [ID]
!помощник [ID], !модер [ID]
!тишина [время]
!понику [часть ника]
!gzov [текст], !gkick [ID], !gsnick [ID] [ник]

**Администратор 60+:**
!gban, !gunban, !grole, !гмодер, !гпомощник
!удалить, !gm, !removegm, !history [ID], !gms

**Ст. администратор 80+:**
!pin, !unpin, !admin, !gadmin, !newrole, !gnewrole, !delrole
!welcome, !setrules, !delrules, !неактив, !givemoney, !timeuved

**Владелец 100+:**
!settings, !setup, !unity / !addunity / !createunity / !editunity / !removeunity
!sync, !spec / !gspec, !wipe, !games, !editcmd / !geditcmd, !gedit
!gsettings, !owner, !automod, !addws

**Создатель/супер-доступ:**
!setlog, !zovvv, !addws, !gtimeuvedg, !gzovg
!reportedit, !getdialog, !getreport, !reports
!listunities, !listen, !chatlist, !userchats, !ahistory, !checkban
TXT;}

function doGlobal(PDO $p,int $peer,int $uid,string $action,callable $fn):void{$s=$p->query('SELECT peer_id FROM chat_settings')->fetchAll(PDO::FETCH_COLUMN);foreach($s as $other){try{$fn((int)$other);}catch(Throwable $e){}}}
function chatMembers(int $peer):array{$chat=$peer-2000000000;$r=vk('messages.getConversationMembers',['peer_id'=>$peer,'fields'=>'online,first_name,last_name']);return $r['response']['items']??[];}
function mentionAll(PDO $p,int $peer,string $text):void{$m=chatMembers($peer);$ids=[];foreach($m as $x){$id=(int)($x['member_id']??0);if($id>0)$ids[]=$id;}if(!$ids){sendMessage($peer,$text);return;} $out=$text."\n";foreach(array_slice($ids,0,100) as $id)$out.="[id{$id}|. ] ";sendMessage($peer,$out);}
function sendScheduled(PDO $p):void{$now=date('Y-m-d H:i:s');$s=$p->prepare('SELECT * FROM schedules WHERE active=1 AND next_at<=?');$s->execute([$now]);foreach($s as $row){sendMessage((int)$row['peer_id'],$row['text']);$next=date('Y-m-d H:i:s',time()+((int)$row['every_minutes']*60));$p->prepare('UPDATE schedules SET next_at=? WHERE id=?')->execute([$next,$row['id']]);}}

function handle(PDO $p,array $o):void{
 global $ownerIds,$groupId;
 $peer=(int)($o['peer_id']??0);$from=(int)($o['from_id']??0);$text=trim((string)($o['text']??''));
 if(!$peer)return;botLog("EVENT message_new peer={$peer} from={$from} text=".json_encode($text,JSON_UNESCAPED_UNICODE));if($from>0)ensureUser($p,$peer,$from);expire($p);$actions=[];if(isset($o['action'])&&is_array($o['action']))$actions[]=$o['action'];if(isset($o['object']['action'])&&is_array($o['object']['action']))$actions[]=$o['object']['action'];foreach($actions as $action){botLog('ACTION '.json_encode($action,JSON_UNESCAPED_UNICODE));if(($action['type']??'')==='chat_invite_user'&&abs((int)($action['member_id']??0))===$groupId){$p->prepare("INSERT IGNORE INTO chat_settings(peer_id,rules,welcome,mentions_enabled) VALUES(?,?,?,1)")->execute([$peer,'Правила беседы ещё не настроены.','Добро пожаловать в RAZE RUSSIA!']);botLog("BOT INVITED peer={$peer} member_id=".(int)($action['member_id']??0));sendMessage($peer,"🤖 RAZE RUSSIA подключён!\n\n⚙️ Настройка:\n1) Выдайте сообществу права администратора беседы.\n2) Разрешите управление сообщениями и участниками.\n3) Напишите !помощь — список команд.\n\n🔹 Префиксы: ! / . , # ?\n🔹 Примеры: !пинг, /пинг, .пинг, ,пинг, #пинг, ?пинг\n🔹 Звезда: !звезда [ID]\n🔹 Деньги супер-доступом: !выдатьденьги [ID] [сумма]\n🔹 Репорт: /report текст");return;}}if(!$from)return;[$cmd,$a]=parseCommand($text);if($cmd==='')return;
 $L=level($p,$peer,$from);$target=target($o,$a);$req=[
 'пинг'=>[0,'Участник'],'ping'=>[0,'Участник'],'статус'=>[0,'Участник'],'help'=>[0,'Участник'],'помощь'=>[0,'Участник'],'команды'=>[0,'Участник'],'start'=>[0,'Участник'],'правила'=>[0,'Участник'],'роли'=>[0,'Участник'],'админы'=>[0,'Участник'],'онлайн'=>[0,'Участник'],'history'=>[0,'Участник'],'myid'=>[0,'Участник'],'thereid'=>[0,'Участник'],'id'=>[0,'Участник'],'report'=>[0,'Участник'],'rep'=>[0,'Участник'],'репорты'=>[100,'Владелец'],'репорт'=>[100,'Владелец'],'взять'=>[100,'Владелец'],'ответ'=>[100,'Владелец'],'закрыть'=>[100,'Владелец'],'открытьрепорт'=>[100,'Владелец'],'диалогрепорта'=>[100,'Владелец'],'мои'=>[100,'Владелец'],'суперы'=>[100,'Владелец'],'добавитьсупер'=>[100,'Владелец'],'удалитьсупер'=>[100,'Владелец'],'проверкасуперов'=>[100,'Владелец'],'тестрепорт'=>[100,'Владелец'],'профиль'=>[0,'Участник'],'проф'=>[0,'Участник'],'бонус'=>[0,'Участник'],'bonus'=>[0,'Участник'],'казино'=>[0,'Участник'],'перевод'=>[0,'Участник'],'топ'=>[0,'Участник'],'top'=>[0,'Участник'],'atop'=>[0,'Участник'],'гражданство'=>[0,'Участник'],'страна'=>[0,'Участник'],'страны'=>[0,'Участник'],'брак'=>[0,'Участник'],'развод'=>[0,'Участник'],'браки'=>[0,'Участник'],'поцелуй'=>[0,'Участник'],'kiss'=>[0,'Участник'],'обнять'=>[0,'Участник'],'попытка'=>[0,'Участник'],'пиво'=>[0,'Участник'],
 'сник'=>[20,'Помощник'],'ник'=>[20,'Помощник'],'рник'=>[20,'Помощник'],'нлист'=>[20,'Помощник'],'безников'=>[20,'Помощник'],'мут'=>[20,'Помощник'],'унмут'=>[20,'Помощник'],'кик'=>[20,'Помощник'],'пред'=>[20,'Помощник'],'варн'=>[20,'Помощник'],'унварн'=>[20,'Помощник'],'снятьпред'=>[20,'Помощник'],'предупреждения'=>[20,'Помощник'],'getwarns'=>[20,'Помощник'],'getwarn'=>[20,'Помощник'],'getban'=>[20,'Помощник'],'getmute'=>[20,'Помощник'],'warnlist'=>[20,'Помощник'],'преды'=>[20,'Помощник'],'бан'=>[20,'Помощник'],'унбан'=>[20,'Помощник'],'вызов'=>[20,'Помощник'],'чатинфо'=>[20,'Помощник'],'reg'=>[20,'Помощник'],'упоминать'=>[20,'Помощник'],'неупоминать'=>[20,'Помощник'],
 'звезда'=>[40,'Модератор'],'снятьзвезду'=>[40,'Модератор'],'звезды'=>[0,'Участник'],'star'=>[40,'Модератор'],'unstar'=>[40,'Модератор'],'stars'=>[0,'Участник'],
 'role'=>[40,'Модератор'],'removerole'=>[40,'Модератор'],'помощник'=>[40,'Модератор'],'модер'=>[40,'Модератор'],'тишина'=>[40,'Модератор'],'понику'=>[40,'Модератор'],'gzov'=>[40,'Модератор'],'gkick'=>[40,'Модератор'],'gsnick'=>[40,'Модератор'],
 'gban'=>[60,'Администратор'],'gunban'=>[60,'Администратор'],'grole'=>[60,'Администратор'],'гмодер'=>[60,'Администратор'],'гпомощник'=>[60,'Администратор'],'удалить'=>[60,'Администратор'],'gm'=>[60,'Администратор'],'removegm'=>[60,'Администратор'],'gms'=>[60,'Администратор'],
 'pin'=>[80,'Ст. администратор'],'unpin'=>[80,'Ст. администратор'],'admin'=>[80,'Ст. администратор'],'gadmin'=>[80,'Ст. администратор'],'newrole'=>[80,'Ст. администратор'],'gnewrole'=>[80,'Ст. администратор'],'delrole'=>[80,'Ст. администратор'],'welcome'=>[80,'Ст. администратор'],'setrules'=>[80,'Ст. администратор'],'delrules'=>[80,'Ст. администратор'],'неактив'=>[80,'Ст. администратор'],'givemoney'=>[100,'Владелец'],'timeuved'=>[80,'Ст. администратор'],
 'settings'=>[100,'Владелец'],'setup'=>[100,'Владелец'],'unity'=>[100,'Владелец'],'addunity'=>[100,'Владелец'],'createunity'=>[100,'Владелец'],'editunity'=>[100,'Владелец'],'removeunity'=>[100,'Владелец'],'sync'=>[100,'Владелец'],'spec'=>[100,'Владелец'],'gspec'=>[100,'Владелец'],'wipe'=>[100,'Владелец'],'games'=>[100,'Владелец'],'editcmd'=>[100,'Владелец'],'geditcmd'=>[100,'Владелец'],'gedit'=>[100,'Владелец'],'gsettings'=>[100,'Владелец'],'owner'=>[100,'Владелец'],'automod'=>[100,'Владелец'],
 'setlog'=>[100,'Владелец'],'zovvv'=>[100,'Владелец'],'addws'=>[100,'Владелец'],'gtimeuvedg'=>[100,'Владелец'],'gzovg'=>[100,'Владелец'],'reportedit'=>[100,'Владелец'],'getdialog'=>[100,'Владелец'],'getreport'=>[100,'Владелец'],'reports'=>[100,'Владелец'],'listunities'=>[100,'Владелец'],'listen'=>[100,'Владелец'],'chatlist'=>[100,'Владелец'],'userchats'=>[100,'Владелец'],'ahistory'=>[100,'Владелец'],'checkban'=>[100,'Владелец']];
 if(!isset($req[$cmd]))return;[$need,$role]=$req[$cmd];if($L<$need){sendMessage($peer,requireLevel($L,$need,$role)??'❌ Недостаточно прав.');return;}
 $argText=trim(implode(' ',$a));
 switch($cmd){
 case 'пинг':case'ping':case'статус':sendMessage($peer,'🏓 RAZE RUSSIA BOT: онлайн');break;
 case 'help':case'помощь':case'команды':case'start':sendMessage($peer,helpText());break;
 case 'правила':sendMessage($peer,rulesText($p,$peer));break;
 case 'роли':$rows=$p->query('SELECT name,priority FROM roles ORDER BY priority DESC')->fetchAll();$s="👑 Роли:\n";foreach($rows as $r)$s.="• {$r['name']} ({$r['priority']})\n";sendMessage($peer,$s);break;
 case 'админы':$q=$p->prepare('SELECT u.user_id,r.name,r.priority FROM chat_users u JOIN roles r ON r.id=u.role_id WHERE u.peer_id=? AND r.priority>0 ORDER BY r.priority DESC');$q->execute([$peer]);$s="👮 Администрация:\n";foreach($q as $r)$s.="• ".nameOf((int)$r['user_id'])." — {$r['name']} ({$r['priority']})\n";sendMessage($peer,$s);break;
 case 'онлайн':$m=chatMembers($peer);$online=array_filter($m,fn($x)=>!empty($x['is_admin'])||!empty($x['online']));sendMessage($peer,'🟢 Онлайн участников: '.count($online).' из '.count($m));break;
 case 'myid':sendMessage($peer,"🆔 Ваш VK ID: {$from}");break;case'thereid':case'id':sendMessage($peer,"🆔 ID этой беседы: {$peer}");break;
 case 'report':$t=$argText;if($t===''){sendMessage($peer,'Использование: /report [текст]');break;}$p->prepare("INSERT INTO reports(peer_id,user_id,text,status) VALUES(?,?,?,'open')")->execute([$peer,$from,$t]);$rid=(int)$p->lastInsertId();addReportMessage($p,$rid,$from,$t,'user');notifyReportSuper($p,$peer,$rid,$from,$t);$s=$p->prepare('SELECT report_notify_peer FROM chat_settings WHERE peer_id=?');$s->execute([$peer]);$np=(int)($s->fetchColumn()?:0);if($np)sendMessage($np,"🆕 Новый репорт #{$rid}\n👤 От: ".nameOf($from)."\n📝 {$t}");sendMessage($peer,"📨 Репорт #{$rid} принят.\n👤 Автор: ".nameOf($from)."\n✅ Репорт отправлен всем супер-доступам в ЛС.");break;
 case 'упоминать':$p->prepare('INSERT INTO chat_settings(peer_id,mentions_enabled) VALUES(?,1) ON DUPLICATE KEY UPDATE mentions_enabled=1')->execute([$peer]);sendMessage($peer,'✅ Вы включили упоминание себя в вызовах.');break;case'неупоминать':$p->prepare('INSERT INTO chat_settings(peer_id,mentions_enabled) VALUES(?,0) ON DUPLICATE KEY UPDATE mentions_enabled=0')->execute([$peer]);sendMessage($peer,'✅ Вы отключили упоминание себя в вызовах.');break;
 case 'profile':case'профиль':case'проф':ensureEconomy($p,$peer,$target??$from);$q=$p->prepare('SELECT * FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$target??$from]);$e=$q->fetch();sendMessage($peer,"👤 Профиль: ".nameOf($target??$from)."\n💰 Баланс: ".number_format((int)$e['balance'],0,'.',' ')." ₽\n🌍 Страна: ".($e['country']?:'не указана')."\n💍 Партнёр: ".($e['partner_id'] ? nameOf((int)$e['partner_id']) : 'нет'));break;
 case 'bonus':case'бонус':ensureEconomy($p,$peer,$from);$q=$p->prepare('SELECT balance,last_bonus FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);$e=$q->fetch();if($e['last_bonus']&&strtotime($e['last_bonus'])>time()-86400){sendMessage($peer,'⏳ Бонус уже получен. Возвращайтесь через 24 часа.');break;}$p->prepare("UPDATE economy SET balance=balance+1000,last_bonus=NOW() WHERE peer_id=? AND user_id=?")->execute([$peer,$from]);sendMessage($peer,'🎁 Вы получили ежедневный бонус: 1 000 ₽!');break;
 case 'казино':$bet=amount($a[0]??'0');ensureEconomy($p,$peer,$from);$q=$p->prepare('SELECT balance FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);$bal=(int)$q->fetchColumn();if($bet<=0||$bet>$bal){sendMessage($peer,"🎰 Недостаточно средств. Ваш баланс: ".number_format($bal,0,'.',' '));break;}$roll=random_int(1,100);$mult = $roll <= 10 ? 0 : ($roll <= 55 ? 1 : ($roll <= 85 ? 1.5 : 2.5));$delta=(int)round($bet*$mult)-$bet;$p->prepare('UPDATE economy SET balance=balance+?,last_casino=datetime(\'now\') WHERE peer_id=? AND user_id=?')->execute([$delta,$peer,$from]);sendMessage($peer,"🎰 Результат: {$mult}×\n".($delta>=0?'Вы выиграли ':'Вы проиграли ').number_format(abs($delta),0,'.',' ')." ₽");break;
 case 'перевод':$t = $target ?? (isset($a[0]) ? (int)$a[0] : 0);$sum=amount($a[$target?0:1]??'0');if(!$t||$sum<=0){sendMessage($peer,'Использование: !перевод [ID] [сумма]');break;}ensureEconomy($p,$peer,$from);ensureEconomy($p,$peer,$t);$p->beginTransaction();$q=$p->prepare('SELECT balance FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);$bal=(int)$q->fetchColumn();if($bal<$sum){$p->rollBack();sendMessage($peer,'❌ Недостаточно средств.');break;}$p->prepare('UPDATE economy SET balance=balance-? WHERE peer_id=? AND user_id=?')->execute([$sum,$peer,$from]);$p->prepare('UPDATE economy SET balance=balance+? WHERE peer_id=? AND user_id=?')->execute([$sum,$peer,$t]);$p->commit();sendMessage($peer,"💸 Перевод выполнен: ".number_format($sum,0,'.',' ')." ₽ отправлено пользователю ".nameOf($t).'.');break;
 case 'топ':case'top':$q=$p->prepare('SELECT user_id,balance FROM economy WHERE peer_id=? ORDER BY balance DESC LIMIT 10');$q->execute([$peer]);$s="👑 Топ игроков по балансу:\n";$i=1;foreach($q as $r)$s.=$i++.'. '.nameOf((int)$r['user_id']).' — '.number_format((int)$r['balance'],0,'.',' ')." ₽\n";sendMessage($peer,$s);break;
 case 'atop':$q=$p->query('SELECT user_id,SUM(balance) balance FROM economy GROUP BY user_id ORDER BY balance DESC LIMIT 10');$s="👑 Общий топ:\n";$i=1;foreach($q as $r)$s.=$i++.'. '.nameOf((int)$r['user_id']).' — '.number_format((int)$r['balance'],0,'.',' ')." ₽\n";sendMessage($peer,$s);break;
 case 'гражданство':$country=trim($argText);if($country===''){sendMessage($peer,'Укажите страну.');break;}$p->prepare('UPDATE economy SET country=? WHERE peer_id=? AND user_id=?')->execute([$country,$peer,$from]);$p->prepare('INSERT IGNORE INTO countries(peer_id,name,owner_id) VALUES(?,?,?)')->execute([$peer,$country,$from]);sendMessage($peer,"🌍 Гражданство установлено: {$country}");break;case'страна':$q=$p->prepare('SELECT country FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);sendMessage($peer,'🌍 Ваша страна: '.($q->fetchColumn()?:'не указана'));break;case'страны':$q=$p->prepare('SELECT name,COUNT(*) citizens FROM countries c LEFT JOIN economy e ON e.peer_id=c.peer_id AND e.country=c.name WHERE c.peer_id=? GROUP BY c.name ORDER BY citizens DESC');$q->execute([$peer]);$s="🌍 Страны:\n";foreach($q as $r)$s.="• {$r['name']} — {$r['citizens']} граждан\n";sendMessage($peer,$s?:'Стран пока нет.');break;
 case 'брак':$t=$target??(int)($a[0]??0);if(!$t||$t===$from){sendMessage($peer,'Укажите ID другого пользователя.');break;}ensureEconomy($p,$peer,$from);ensureEconomy($p,$peer,$t);$p->prepare('UPDATE economy SET partner_id=? WHERE peer_id=? AND user_id=?')->execute([$t,$peer,$from]);$p->prepare('UPDATE economy SET partner_id=? WHERE peer_id=? AND user_id=?')->execute([$from,$peer,$t]);$p->prepare('INSERT IGNORE INTO marriages(peer_id,user1,user2) VALUES(?,?,?)')->execute([$peer,min($from,$t),max($from,$t)]);sendMessage($peer,'💍 Предложение/брак оформлен с '.nameOf($t).'.');break;case'развод':$q=$p->prepare('SELECT partner_id FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);$t=(int)($q->fetchColumn()?:0);if($t){$p->prepare('UPDATE economy SET partner_id=NULL WHERE peer_id=? AND user_id IN (?,?)')->execute([$peer,$from,$t]);$p->prepare('DELETE FROM marriages WHERE peer_id=? AND ((user1=? AND user2=?) OR (user1=? AND user2=?))')->execute([$peer,min($from,$t),max($from,$t),max($from,$t),min($from,$t)]);sendMessage($peer,'💔 Брак расторгнут.');}else sendMessage($peer,'Брака нет.');break;case'браки':$q=$p->prepare('SELECT user1,user2 FROM marriages WHERE peer_id=? LIMIT 20');$q->execute([$peer]);$s="💍 Браки:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user1']).' + '.nameOf((int)$r['user2'])."\n";sendMessage($peer,$s?:'Браков пока нет.');break;
 case 'поцелуй':case'kiss':$t=$target??(int)($a[0]??0);sendMessage($peer,$t?'💋 '.nameOf($from).' поцеловал(а) '.nameOf($t).'.':'Укажите ID.');break;case'обнять':$t=$target??(int)($a[0]??0);sendMessage($peer,$t?'🤗 '.nameOf($from).' обнял(а) '.nameOf($t).'.':'Укажите ID.');break;case'попытка':sendMessage($peer,'🎲 '.nameOf($from).' — '.(random_int(0,1)?'успех!':'неудача!').' Действие: '.$argText);break;case'пиво':sendMessage($peer,'🍺 '.nameOf($from).' выпил(а) виртуальное пиво.');break;
 case 'history':$t=$target??$from;$q=$p->prepare('SELECT action,details,created_at FROM logs WHERE peer_id=? AND target_id=? AND action IN (\'warn\',\'ban\',\'mute\',\'unwarn\',\'unban\',\'unmute\') ORDER BY id DESC LIMIT 20');$q->execute([$peer,$t]);$s="📜 История наказаний: ".nameOf($t)."\n";foreach($q as $r)$s.="• {$r['created_at']} — {$r['action']} — {$r['details']}\n";sendMessage($peer,$s);break;
 case 'сник':case'ник':$t=$target??$from;if($cmd==='ник'&&!$argText){$q=$p->prepare('SELECT nickname FROM nicknames WHERE peer_id=? AND user_id=?');$q->execute([$peer,$t]);sendMessage($peer,'🏷 Ник: '.($q->fetchColumn()?:'не установлен'));break;}$nick=$target ? trim(implode(' ',array_slice($a,1))) : trim($argText);if($nick===''){sendMessage($peer,'Использование: !сник [ID] [ник]');break;}$p->prepare('INSERT INTO nicknames(peer_id,user_id,nickname) VALUES(?,?,?) ON DUPLICATE KEY UPDATE nickname=VALUES(nickname)')->execute([$peer,$t,$nick]);sendMessage($peer,'✅ Ник установлен: '.$nick);break;
 case 'рник':$t=$target??$from;$p->prepare('DELETE FROM nicknames WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'✅ Ник удалён.');break;case'нлист':$q=$p->prepare('SELECT user_id,nickname FROM nicknames WHERE peer_id=? ORDER BY nickname LIMIT 50');$q->execute([$peer]);$s="🏷 Ники:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user_id']).' — '.$r['nickname']."\n";sendMessage($peer,$s);break;case'безников':$q=$p->prepare('SELECT user_id FROM chat_users WHERE peer_id=? AND user_id NOT IN(SELECT user_id FROM nicknames WHERE peer_id=?) LIMIT 50');$q->execute([$peer,$peer]);$s="👤 Без никнейма:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user_id'])."\n";sendMessage($peer,$s);break;
 case 'пред':case'варн':$t=$target??(int)($a[0]??0);$reason=trim(implode(' ',array_slice($a,$target?1:1)));if(!$t){sendMessage($peer,'Укажите ID/ответ.');break;}$bad=punishAllowed($p,$peer,$from,$t,20);if($bad){sendMessage($peer,$bad);break;}$q=$p->prepare('SELECT COUNT(*) FROM warnings WHERE peer_id=? AND user_id=? AND active=1');$q->execute([$peer,$t]);$cnt=(int)$q->fetchColumn();if($cnt>=3){sendMessage($peer,'❌ У пользователя уже 3 активных предупреждения.');break;}$p->prepare('INSERT INTO warnings(peer_id,user_id,moderator_id,reason) VALUES(?,?,?,?)')->execute([$peer,$t,$from,$reason?:'Без причины']);sendMessage($peer,nameOf($t)." получил предупреждение (".($cnt+1).'/3). Причина: '.($reason?:'не указана'));break;
 case 'унварн':case'снятьпред':$t=$target??(int)($a[0]??0);if(!$t){sendMessage($peer,'Укажите ID/ответ.');break;}$q=$p->prepare('SELECT id FROM warnings WHERE peer_id=? AND user_id=? AND active=1 ORDER BY id DESC LIMIT 1');$q->execute([$peer,$t]);$id=$q->fetchColumn();if($id){$p->prepare('UPDATE warnings SET active=0 WHERE id=?')->execute([$id]);sendMessage($peer,'✅ Последнее предупреждение снято.');}else sendMessage($peer,'Активных предупреждений нет.');break;
 case 'предупреждения':case'getwarns':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT COUNT(*) FROM warnings WHERE peer_id=? AND user_id=? AND active=1');$q->execute([$peer,$t]);sendMessage($peer,'⚠️ Активных предупреждений: '.$q->fetchColumn());break;case'getwarn':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT moderator_id,reason,created_at FROM warnings WHERE peer_id=? AND user_id=? ORDER BY id DESC');$q->execute([$peer,$t]);$s='⚠️ Предупреждения '.nameOf($t).":\n";$i=1;foreach($q as $r)$s.=$i++.'. Выдал: '.nameOf((int)$r['moderator_id']).' | '.$r['reason'].' | '.$r['created_at']."\n";sendMessage($peer,$s);break;case'getban':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT moderator_id,days,reason,created_at,expires_at,active FROM bans WHERE peer_id=? AND user_id=? ORDER BY id DESC');$q->execute([$peer,$t]);$s='🔨 Баны '.nameOf($t).":\n";foreach($q as $r)$s.='• '.($r['active']?'активен':'снят').' | выдал '.nameOf((int)$r['moderator_id']).' | '.$r['days'].' дн. | до '.$r['expires_at'].' | '.$r['reason']."\n";sendMessage($peer,$s);break;case'getmute':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT moderator_id,minutes,reason,created_at,expires_at,active FROM mutes WHERE peer_id=? AND user_id=? ORDER BY id DESC');$q->execute([$peer,$t]);$s='🔇 Муты '.nameOf($t).":\n";foreach($q as $r)$s.='• '.($r['active']?'активен':'снят').' | выдал '.nameOf((int)$r['moderator_id']).' | '.$r['minutes'].' мин. | до '.$r['expires_at'].' | '.$r['reason']."\n";sendMessage($peer,$s);break;
 case 'warnlist':case'преды':$q=$p->prepare('SELECT user_id,COUNT(*) c FROM warnings WHERE peer_id=? AND active=1 GROUP BY user_id ORDER BY c DESC');$q->execute([$peer]);$s="⚠️ Список варнов:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user_id']).' — '.$r['c']."\n";sendMessage($peer,$s);break;
 case 'мут':$t=$target??(int)($a[0]??0);$idx=$target?0:1;$mins=(int)($a[$idx]??0);if(!$t||$mins<=0){sendMessage($peer,'Использование: !мут [ID] [минуты] [причина]');break;}$bad=punishAllowed($p,$peer,$from,$t,20);if($bad){sendMessage($peer,$bad);break;}$reason=trim(implode(' ',array_slice($a,$idx+1)))?:'Без причины';$exp=date('Y-m-d H:i:s',time()+$mins*60);$p->prepare('INSERT INTO mutes(peer_id,user_id,moderator_id,minutes,reason,expires_at) VALUES(?,?,?,?,?,?)')->execute([$peer,$t,$from,$mins,$reason,$exp]);sendMessage($peer,"🔇 ".nameOf($t)." получил мут на {$mins} мин. Причина: {$reason}");break;case'унмут':$t=$target??(int)($a[0]??0);$p->prepare('UPDATE mutes SET active=0 WHERE peer_id=? AND user_id=? AND active=1')->execute([$peer,$t]);sendMessage($peer,'🔊 Мут снят.');break;
 case 'кик':$t=$target??(int)($a[0]??0);$bad=punishAllowed($p,$peer,$from,$t,20);if($bad){sendMessage($peer,$bad);break;}$r=vk('messages.removeChatUser',['chat_id'=>$peer-2000000000,'member_id'=>$t]);sendMessage($peer,isset($r['response'])?'👢 Пользователь исключён.':'❌ VK: '.($r['error']['error_msg']??'ошибка'));break;
 case 'бан':$t=$target??(int)($a[0]??0);$idx=$target?0:1;$days=(int)($a[$idx]??0);if(!$t||$days<=0){sendMessage($peer,'Использование: !бан [ID] [дни] [причина]');break;}$bad=punishAllowed($p,$peer,$from,$t,40);if($bad){sendMessage($peer,$bad);break;}$reason=trim(implode(' ',array_slice($a,$idx+1)))?:'не указана';$exp=date('Y-m-d H:i:s',time()+$days*86400);$p->prepare('INSERT INTO bans(peer_id,user_id,moderator_id,days,reason,expires_at) VALUES(?,?,?,?,?,?)')->execute([$peer,$t,$from,$days,$reason,$exp]);sendMessage($peer,"🔨 ".nameOf($t)." заблокирован на {$days} дн.\nПричина: {$reason}");break;case'унбан':$t=$target??(int)($a[0]??0);$p->prepare('UPDATE bans SET active=0 WHERE peer_id=? AND user_id=? AND active=1')->execute([$peer,$t]);sendMessage($peer,'✅ Бан снят.');break;
 case 'вызов':mentionAll($p,$peer,$argText?:'📢 Вызов участников!');break;case'чатинфо':$m=chatMembers($peer);$q=$p->prepare('SELECT COUNT(*) FROM chat_users WHERE peer_id=?');$q->execute([$peer]);sendMessage($peer,'ℹ️ ID: '.$peer."\nУчастников VK: ".count($m)."\nПользователей в базе: ".$q->fetchColumn());break;case'reg':$t=$target??(int)($a[0]??$from);$q=$p->prepare('SELECT registered_at FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$t]);sendMessage($peer,'📅 Регистрация: '.($q->fetchColumn()?:'нет данных'));break;
 case 'звезда':case 'star':$t=$target??(int)($a[0]??0);if(!$t){sendMessage($peer,'⭐ Использование: !звезда [ID] или ответом на сообщение.');break;}$p->prepare('REPLACE INTO stars(peer_id,user_id,granted_by) VALUES(?,?,?)')->execute([$peer,$t,$from]);sendMessage($peer,'⭐ Звезда выдана '.nameOf($t).'.');break;case 'снятьзвезду':case 'unstar':$t=$target??(int)($a[0]??0);if(!$t){sendMessage($peer,'⭐ Использование: !снятьзвезду [ID] или ответом.');break;}$p->prepare('DELETE FROM stars WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'⭐ Звезда снята с '.nameOf($t).'.');break;case 'звезды':case 'stars':$q=$p->prepare('SELECT user_id,granted_by FROM stars WHERE peer_id=? ORDER BY created_at');$q->execute([$peer]);$out='⭐ Звёзды беседы:\n';$i=1;foreach($q as $r)$out.=$i++.'. '.nameOf((int)$r['user_id']).' — выдал '.nameOf((int)$r['granted_by'])."\n";sendMessage($peer,$out);break;case 'role':$t=$target??(int)($a[0]??0);$rn=trim(implode(' ',array_slice($a,$target?1:1)));$rid=null;if(is_numeric($rn)){$q=$p->prepare('SELECT id FROM roles WHERE priority=?');$q->execute([(int)$rn]);$rid=$q->fetchColumn();}else{$q=$p->prepare('SELECT id FROM roles WHERE name=?');$q->execute([$rn]);$rid=$q->fetchColumn();}if(!$t||!$rid){sendMessage($peer,'Использование: !role [ID] [роль/приоритет]');break;}$p->prepare('INSERT INTO chat_users(peer_id,user_id,role_id) VALUES(?,?,?) ON DUPLICATE KEY UPDATE role_id=VALUES(role_id)')->execute([$peer,$t,$rid]);sendMessage($peer,'👑 Роль выдана.');break;case'removerole':$t=$target??(int)($a[0]??0);$p->prepare('UPDATE chat_users SET role_id=1 WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'✅ Все роли сняты.');break;case'помощник':case'модер':$t=$target??(int)($a[0]??0);$r=$cmd==='помощник'?2:3;$p->prepare('UPDATE chat_users SET role_id=? WHERE peer_id=? AND user_id=?')->execute([$r,$peer,$t]);sendMessage($peer,'👑 Роль назначена.');break;
 case 'тишина':$mins=(int)($a[0]??0);if(!$mins){$mins=30;}if(str_contains(mb_strtolower($argText),'час'))$mins=(int)preg_replace('/\D/','',$argText)*60;if(str_contains(mb_strtolower($argText),'дн'))$mins=(int)preg_replace('/\D/','',$argText)*1440;$until=date('Y-m-d H:i:s',time()+$mins*60);$p->prepare('INSERT INTO chat_settings(peer_id,silence_until) VALUES(?,?) ON DUPLICATE KEY UPDATE silence_until=VALUES(silence_until)')->execute([$peer,$until]);sendMessage($peer,"🔇 Режим тишины включён до {$until}.");break;
 case 'понику':$part=mb_strtolower($argText);$q=$p->prepare('SELECT user_id,nickname FROM nicknames WHERE peer_id=? AND lower(nickname) LIKE ? LIMIT 20');$q->execute([$peer,'%'.$part.'%']);$s='🔎 Поиск:\n';foreach($q as $r)$s.='• '.nameOf((int)$r['user_id']).' — '.$r['nickname']."\n";sendMessage($peer,$s);break;
 case 'gsnick':$t=(int)($a[0]??0);$nick=trim(implode(' ',array_slice($a,1)));if(!$t||$nick===''){sendMessage($peer,'Использование: !gsnick [ID] [ник]');break;}doGlobal($p,$peer,$from,'gsnick',function(int $c)use($p,$t,$nick){$p->prepare('INSERT INTO nicknames(peer_id,user_id,nickname) VALUES(?,?,?) ON DUPLICATE KEY UPDATE nickname=VALUES(nickname)')->execute([$c,$t,$nick]);});sendMessage($peer,'✅ Ник установлен во всех известных беседах.');break;case'gzov':case'zovvv':case'gzovg':mentionAll($p,$peer,$argText?:'📢 Общий вызов!');break;case'gkick':$t=(int)($a[0]??0);doGlobal($p,$peer,$from,'gkick',function(int $c)use($t){vk('messages.removeChatUser',['chat_id'=>$c-2000000000,'member_id'=>$t]);});sendMessage($peer,'👢 Выполнено во всех известных беседах.');break;
 case 'gban':case'gunban':$t=(int)($a[0]??0);$days=(int)($a[1]??0);doGlobal($p,$peer,$from,$cmd,function(int $c)use($p,$from,$t,$days,$cmd,$argText){if($cmd==='gban'){$exp=date('Y-m-d H:i:s',time()+max(1,$days)*86400);$p->prepare('INSERT INTO bans(peer_id,user_id,moderator_id,days,reason,expires_at) VALUES(?,?,?,?,?,?)')->execute([$c,$t,$from,max(1,$days),$argText,$exp]);}else{$p->prepare('UPDATE bans SET active=0 WHERE peer_id=? AND user_id=?')->execute([$c,$t]);}});sendMessage($peer,'🌐 Глобальная блокировка обработана.');break;
 case 'grole':case'гмодер':case'гпомощник':$t=(int)($a[0]??0);$rn=$cmd==='гмодер'?3:2;if($cmd==='grole'){$rn=(int)($a[1]??3);}doGlobal($p,$peer,$from,$cmd,function(int $c)use($p,$t,$rn){$p->prepare('UPDATE chat_users SET role_id=? WHERE peer_id=? AND user_id=?')->execute([$rn,$c,$t]);});sendMessage($peer,'🌐 Глобальная роль обработана.');break;
 case 'удалить':$cm=$peer-2000000000;$mid=(int)($o['conversation_message_id']??0);if(!$mid&&isset($o['reply_message']['conversation_message_id']))$mid=(int)$o['reply_message']['conversation_message_id'];if(!$mid){sendMessage($peer,'Ответьте на сообщение, которое нужно удалить.');break;} $r=vk('messages.delete',['cmids'=>$mid,'delete_for_all'=>1,'peer_id'=>$peer]);sendMessage($peer,isset($r['response'])?'🗑 Сообщение удалено.':'❌ VK: '.($r['error']['error_msg']??'ошибка'));break;
 case 'gm':$t=$target??(int)($a[0]??0);$p->prepare('UPDATE chat_users SET immunity=CASE WHEN immunity=1 THEN 0 ELSE 1 END WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);$q=$p->prepare('SELECT immunity FROM chat_users WHERE peer_id=? AND user_id=?');$q->execute([$peer,$t]);sendMessage($peer,((int)$q->fetchColumn()===1?'🛡 Иммунитет включён.':'🛡 Иммунитет снят.'));break;case'removegm':$t=$target??(int)($a[0]??0);$p->prepare('UPDATE chat_users SET immunity=0 WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'🛡 Иммунитет снят.');break;case'gms':$q=$p->prepare('SELECT user_id FROM chat_users WHERE peer_id=? AND immunity=1');$q->execute([$peer]);$s='🛡 Иммунитет:\n';foreach($q as $r)$s.='• '.nameOf((int)$r['user_id'])."\n";sendMessage($peer,$s);break;
 case 'pin':$mid=(int)($o['reply_message']['conversation_message_id']??0);if(!$mid){sendMessage($peer,'Ответьте на сообщение.');break;}sendMessage($peer,'📌 Команда pin принята. Для закрепления бот должен иметь права администратора беседы.');break;case'unpin':sendMessage($peer,'📌 Открепление обработано.');break;
 case 'admin':case'gadmin':$t=(int)($a[0]??0);$r=4;doGlobal($p,$peer,$from,$cmd,function(int $c)use($p,$t,$r){$p->prepare('UPDATE chat_users SET role_id=? WHERE peer_id=? AND user_id=?')->execute([$r,$c,$t]);});sendMessage($peer,'👑 Администратор назначен.');break;
 case 'newrole':case'gnewrole':$pr=(int)($a[0]??0);$rn=trim(implode(' ',array_slice($a,1)));if($rn===''||$pr<0){sendMessage($peer,'Использование: !newrole [приоритет] [название]');break;}$p->prepare('INSERT INTO roles(name,priority) VALUES(?,?) ON DUPLICATE KEY UPDATE priority=VALUES(priority)')->execute([$rn,$pr]);sendMessage($peer,'✅ Роль создана/обновлена.');break;case'delrole':$pr=(int)($a[0]??-1);$p->prepare('DELETE FROM roles WHERE priority=? AND id>6')->execute([$pr]);sendMessage($peer,'✅ Роль удалена.');break;
 case 'welcome':$p->prepare('INSERT INTO chat_settings(peer_id,welcome) VALUES(?,?) ON DUPLICATE KEY UPDATE welcome=VALUES(welcome)')->execute([$peer,$argText]);sendMessage($peer,'✅ Приветствие сохранено.');break;case'setrules':$p->prepare('INSERT INTO chat_settings(peer_id,rules) VALUES(?,?) ON DUPLICATE KEY UPDATE rules=VALUES(rules)')->execute([$peer,$argText]);sendMessage($peer,'✅ Правила сохранены.');break;case'delrules':$p->prepare('UPDATE chat_settings SET rules=NULL WHERE peer_id=?')->execute([$peer]);sendMessage($peer,'✅ Правила удалены.');break;case'неактив':$days=(int)($a[0]??3);$q=$p->prepare("SELECT user_id,last_seen FROM chat_users WHERE peer_id=? AND last_seen<=? LIMIT 50");$q->execute([$peer,date('Y-m-d H:i:s',time()-$days*86400)]);$s="💤 Неактивные за {$days} дн.:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user_id']).' — '.$r['last_seen']."\n";sendMessage($peer,$s);break;
 case 'givemoney':$t=(int)($a[0]??0);$sum=amount($a[1]??'0');ensureEconomy($p,$peer,$t);$p->prepare('UPDATE economy SET balance=balance+? WHERE peer_id=? AND user_id=?')->execute([$sum,$peer,$t]);sendMessage($peer,'💰 Выдано '.number_format($sum,0,'.',' ').' ₽.');break;case'timeuved':$v=$a[0]??'0';$mins=(int)$v;if(str_contains(mb_strtolower($v),'ч'))$mins=(int)$v*60;$msg=trim(implode(' ',array_slice($a,1)));if($mins<=0||$msg===''){sendMessage($peer,'Использование: !timeuved 2 текст');break;}$next=date('Y-m-d H:i:s',time()+$mins*60);$p->prepare('INSERT INTO schedules(peer_id,owner_id,every_minutes,text,next_at) VALUES(?,?,?,?,?)')->execute([$peer,$from,$mins,$msg,$next]);sendMessage($peer,'⏰ Автоуведомление создано.');break;
 case 'settings':$q=$p->prepare('SELECT * FROM chat_settings WHERE peer_id=?');$q->execute([$peer]);$r=$q->fetch()?:[];sendMessage($peer,'⚙️ Настройки:\nGames: '.(!empty($r['games_enabled'])?'ON':'OFF')."\nAutoMod: ".(!empty($r['automod_enabled'])?'ON':'OFF')."\nMentions: ".(!empty($r['mentions_enabled'])?'ON':'OFF'));break;case'setup':$p->prepare('INSERT IGNORE INTO chat_settings(peer_id,rules,welcome,games_enabled,mentions_enabled) VALUES(?,\'Правила беседы ещё не настроены.\',\'Добро пожаловать в RAZE RUSSIA!\',0,1)')->execute([$peer]);sendMessage($peer,'✅ Первичная настройка выполнена.');break;case'games':$p->prepare('INSERT INTO chat_settings(peer_id,games_enabled) VALUES(?,1) ON DUPLICATE KEY UPDATE games_enabled=CASE WHEN games_enabled=1 THEN 0 ELSE 1 END')->execute([$peer]);$q=$p->prepare('SELECT games_enabled FROM chat_settings WHERE peer_id=?');$q->execute([$peer]);sendMessage($peer,'🎮 Игры: '.((int)$q->fetchColumn()?'включены':'выключены'));break;case'automod':$p->prepare('INSERT INTO chat_settings(peer_id,automod_enabled) VALUES(?,1) ON DUPLICATE KEY UPDATE automod_enabled=CASE WHEN automod_enabled=1 THEN 0 ELSE 1 END')->execute([$peer]);sendMessage($peer,'🛡 Автомод переключён.');break;
 case 'wipe':$p->prepare('DELETE FROM nicknames WHERE peer_id=?')->execute([$peer]);$p->prepare('UPDATE bans SET active=0 WHERE peer_id=?')->execute([$peer]);$p->prepare('UPDATE warnings SET active=0 WHERE peer_id=?')->execute([$peer]);sendMessage($peer,'🧹 Ники, баны и предупреждения сброшены.');break;case'sync':foreach(chatMembers($peer) as $m)if(isset($m['member_id']))ensureUser($p,$peer,(int)$m['member_id']);sendMessage($peer,'🔄 Участники синхронизированы.');break;case'owner':$t=(int)($a[0]??0);$p->prepare('UPDATE chat_users SET role_id=1 WHERE peer_id=? AND user_id!=? AND role_id=6')->execute([$peer,$t]);$p->prepare('UPDATE chat_users SET role_id=6 WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'👑 Владелец назначен.');break;case'spec':case'gspec':$t=(int)($a[0]??0);$p->prepare('UPDATE chat_users SET role_id=6 WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'⭐ Главный администратор назначен.');break;case'addws':$t=(int)($a[0]??0);$p->prepare('INSERT IGNORE INTO superusers(user_id) VALUES(?)')->execute([$t]);sendMessage($peer,'🛡 Супер-доступ выдан.');break;
 case 'unity':case'createunity':$name=$argText?:'RAZE Unity';$p->prepare('INSERT IGNORE INTO unities(name,owner_id) VALUES(?,?)')->execute([$name,$from]);$q=$p->prepare('SELECT id FROM unities WHERE name=?');$q->execute([$name]);$u=(int)$q->fetchColumn();$p->prepare('INSERT IGNORE INTO unity_chats(unity_id,peer_id) VALUES(?,?)')->execute([$u,$peer]);sendMessage($peer,"🌐 Объединение '{$name}' готово.");break;case'addunity':$q=$p->query('SELECT id FROM unities ORDER BY id DESC LIMIT 1');$u=(int)$q->fetchColumn();if($u){$p->prepare('INSERT IGNORE INTO unity_chats(unity_id,peer_id) VALUES(?,?)')->execute([$u,$peer]);sendMessage($peer,'🌐 Беседа добавлена в объединение.');}else sendMessage($peer,'Сначала создайте объединение.');break;case'removeunity':$p->prepare('DELETE FROM unity_chats WHERE peer_id=?')->execute([$peer]);sendMessage($peer,'🌐 Беседа удалена из объединения.');break;case'editunity':sendMessage($peer,'🌐 Для переименования: !editunity новое название.');break;case'listunities':$q=$p->query('SELECT id,name,owner_id FROM unities ORDER BY id');$s='🌐 Объединения:\n';foreach($q as $r)$s.="• #{$r['id']} {$r['name']} — owner {$r['owner_id']}\n";sendMessage($peer,$s);break;
 case 'setlog':$v=(int)($a[0]??0);$p->prepare('INSERT INTO bot_meta(k,v) VALUES(\'log_peer\',?) ON DUPLICATE KEY UPDATE v=VALUES(v)')->execute([(string)$v]);sendMessage($peer,$v?'📋 Лог-чат установлен.':'📋 Лог-чат отключён.');break;case'gtimeuvedg':$v=(int)($a[0]??0);$msg=trim(implode(' ',array_slice($a,1)));if($v>0&&$msg!==''){foreach($p->query('SELECT peer_id FROM chat_settings')->fetchAll(PDO::FETCH_COLUMN) as $c)$p->prepare('INSERT INTO schedules(peer_id,owner_id,every_minutes,text,next_at,global_flag) VALUES(?,?,?,?,?,1)')->execute([(int)$c,$from,$v*60,$msg,date('Y-m-d H:i:s',time()+$v*3600)]);sendMessage($peer,'🌐 Глобальное уведомление создано.');}else sendMessage($peer,'Использование: !gtimeuvedg [часы] [текст]');break;
 case 'reportedit':$sub=$a[0]??'';if($sub==='toggle'){$p->prepare("INSERT INTO bot_meta(k,v) VALUES('reports_enabled','1') ON DUPLICATE KEY UPDATE v=CASE WHEN v='1' THEN '0' ELSE '1' END")->execute([]);sendMessage($peer,'📨 Уведомления репортов переключены.');}elseif($sub==='notify'){$p->prepare('INSERT INTO chat_settings(peer_id,report_notify_peer) VALUES(?,?) ON DUPLICATE KEY UPDATE report_notify_peer=VALUES(report_notify_peer)')->execute([$peer,(int)($a[1]??0)]);sendMessage($peer,'📨 Чат уведомлений установлен.');}else sendMessage($peer,'Использование: !reportedit toggle / !reportedit notify [peerId]');break;
 case 'reports':sendMessage($peer,reportList($p,'open')."\n".reportList($p,'in_progress'));break;
 case 'getreport':case 'репорт':sendMessage($peer,reportCard($p,(int)($a[0]??0)));break;
 case 'getdialog':case 'диалогрепорта':sendMessage($peer,reportDialog($p,(int)($a[0]??0)));break;
 case 'взять':$id=(int)($a[0]??0);$r=reportTake($p,$id,$from);if(!$r){sendMessage($peer,'❌ Репорт не найден.');break;}sendMessage($peer,"📥 Репорт #{$id} закреплён за вами.\n\n".reportCard($p,$id));break;
 case 'ответ':$id=(int)($a[0]??0);$reply=trim(implode(' ',array_slice($a,1)));if(!$id||$reply===''){sendMessage($peer,'Использование: !ответ [ID] [текст]');break;}$r=getReport($p,$id);if(!$r){sendMessage($peer,'❌ Репорт не найден.');break;}if($r['status']==='closed'){sendMessage($peer,'❌ Репорт уже закрыт. Сначала !открытьрепорт '.$id);break;}$ok=reportReply($p,$id,$from,$reply);sendMessage($peer,$ok?"✉️ Ответ по репорту #{$id} отправлен автору.":"⚠️ Ответ записан в БД, но VK не позволил отправить ЛС автору.");break;
 case 'закрыть':$id=(int)($a[0]??0);$reason=trim(implode(' ',array_slice($a,1)))?:'Решено';if(!$id){sendMessage($peer,'Использование: !закрыть [ID] [причина]');break;}$ok=reportClose($p,$id,$from,$reason);sendMessage($peer,$ok?"✅ Репорт #{$id} закрыт, автор уведомлён.":"⚠️ Репорт #{$id} закрыт, но ЛС автору отправить не удалось.");break;
 case 'открытьрепорт':$id=(int)($a[0]??0);if(!$id||!reportReopen($p,$id,$from)){sendMessage($peer,'❌ Репорт не найден.');break;}sendMessage($peer,"🔄 Репорт #{$id} снова открыт.");break;
 case 'мои':$q=$p->prepare("SELECT id,status,text,created_at FROM reports WHERE assigned_to=? AND status<>'closed' ORDER BY id DESC");$q->execute([$from]);$rows=$q->fetchAll();$s="📥 Мои репорты:\n\n";foreach($rows as $r)$s.="#{$r['id']} • {$r['status']}\n{$r['text']}\n\n";sendMessage($peer,$rows?$s:'📥 У вас нет закреплённых открытых репортов.');break;
 case 'суперы':$ids=superIds();$s="🛡 Супер-доступы:\n";foreach($ids as $id)$s.='• '.nameOf($id)." — ID {$id}\n";sendMessage($peer,$s);break;
 case 'добавитьсупер':$id=(int)($a[0]??0);if(!$id){sendMessage($peer,'Использование: !добавитьсупер [ID]');break;}$p->prepare('INSERT IGNORE INTO superusers(user_id) VALUES(?)')->execute([$id]);sendMessage($peer,'🛡 Супер-доступ выдан: '.nameOf($id));break;
 case 'удалитьсупер':$id=(int)($a[0]??0);if(!$id){sendMessage($peer,'Использование: !удалитьсупер [ID]');break;}if(in_array($id,$ownerIds,true)){sendMessage($peer,'❌ Нельзя удалить владельца бота из OWNER_IDS.');break;}$p->prepare('DELETE FROM superusers WHERE user_id=?')->execute([$id]);sendMessage($peer,'✅ Супер-доступ снят: '.nameOf($id));break;
 case 'тестрепорт':
     $ids=superIds();
     if(!$ids){sendMessage($peer,'❌ Не найдено ни одного супер-доступа. Проверь OWNER_IDS или таблицу superusers.');break;}
     $out="🧪 Тест уведомлений репорта:\n\n";
     foreach($ids as $sid){
         $st=dmStatus($sid);
         if(!$st['ok']){$out.="• ".plainName($sid)." (ID {$sid}) — ⚠️ ошибка API: ".($st['error']??'неизвестно')."\n";continue;}
         if($st['allowed']===false){$out.="• ".plainName($sid)." (ID {$sid}) — ❌ ЛС запрещены\n";continue;}
         $ok=sendUser($sid,"🧪 Тестовое уведомление RAZE RUSSIA BOT\nЛС от сообщества разрешены.");
         $out.="• ".plainName($sid)." (ID {$sid}) — ".($ok?'✅ сообщение отправлено':'❌ ошибка отправки')."\n";
     }
     sendMessage($peer,$out);break;
 case 'проверкасуперов':$out="🔎 Проверка ЛС супер-доступов:\n\n";foreach(superIds() as $sid){$st=dmStatus($sid);$state=$st['ok']?($st['allowed']?'✅ ЛС разрешены':'❌ ЛС запрещены'):'⚠️ ошибка API';$out.="• ".plainName($sid)." (ID {$sid}) — {$state}".($st['error']?" — {$st['error']}":'')."\n";}sendMessage($peer,$out);break;
 case 'listen':$v=$a[0]??'';if(strtolower($v)==='stop'){$p->exec('DELETE FROM listenings');sendMessage($peer,'👂 Прослушки остановлены.');break;}$lp=(int)$v;if($lp){$p->prepare('INSERT INTO listenings(peer_id,owner_id,expires_at) VALUES(?,?,?) ON DUPLICATE KEY UPDATE owner_id=VALUES(owner_id),expires_at=VALUES(expires_at)')->execute([$lp,$from,date('Y-m-d H:i:s',time()+86400)]);sendMessage($peer,'👂 Прослушка включена на 24 часа.');}else sendMessage($peer,'Использование: !listen [peerId] или !listen stop');break;case'chatlist':$q=$p->query('SELECT peer_id FROM chat_settings ORDER BY peer_id');$s='💬 Беседы:\n';foreach($q as $r)$s.='• '.$r['peer_id']."\n";sendMessage($peer,$s);break;case'userchats':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT DISTINCT peer_id FROM chat_users WHERE user_id=?');$q->execute([$t]);$s='💬 Беседы пользователя:\n';foreach($q as $r)$s.='• '.$r['peer_id']."\n";sendMessage($peer,$s);break;case'ahistory':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT peer_id,action,details,created_at FROM logs WHERE target_id=? AND action IN (\'warn\',\'ban\',\'mute\') ORDER BY id DESC LIMIT 30');$q->execute([$t]);$s='📜 Глобальная история:\n';foreach($q as $r)$s.='• '.$r['peer_id'].' '.$r['action'].' '.$r['details'].' '.$r['created_at']."\n";sendMessage($peer,$s);break;case'checkban':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT peer_id,days,reason,expires_at FROM bans WHERE user_id=? AND active=1');$q->execute([$t]);$s='🔨 Активные блокировки:\n';foreach($q as $r)$s.='• '.$r['peer_id'].' — '.$r['days'].' дн. до '.$r['expires_at'].' — '.$r['reason']."\n";sendMessage($peer,$s);break;
 case 'editcmd':case'geditcmd':sendMessage($peer,'⚙️ Изменение приоритета команд доступно в полной панели настроек; текущая версия хранит стандартные приоритеты.');break;case'gedit':sendMessage($peer,'⚙️ Используйте !welcome или !setrules для текстовых настроек.');break;case'gsettings':sendMessage($peer,'⚙️ Глобальные настройки: игры/тишина/упоминания/автомод хранятся в базе бесед.');break;
 default:sendMessage($peer,'❓ Команда пока не имеет отдельного обработчика.');
 }
}

function handleMessageEvent(array $x):void{
    global $pdo;
    $o=$x['object']??[];
    if(isset($o['object'])&&is_array($o['object']))$o=$o['object'];
    $uid=(int)($o['user_id']??$o['from_id']??0);
    $peer=(int)($o['peer_id']??$uid);
    $eventId=(string)($o['event_id']??'');
    $payload=$o['payload']??'';
    if(is_string($payload))$payload=json_decode($payload,true)?:[];
    if(!is_array($payload)||!$uid||!isSuper($uid)){
        if($eventId)vk('messages.sendMessageEventAnswer',['event_id'=>$eventId,'user_id'=>$uid,'peer_id'=>$peer,'event_data'=>json_encode(['type'=>'show_snackbar','text'=>'Нет доступа'],JSON_UNESCAPED_UNICODE)]);
        return;
    }
    $cmd=(string)($payload['cmd']??'');$rid=(int)($payload['id']??0);
    $answer=['type'=>'show_snackbar','text'=>'Готово'];
    if($cmd==='report_take'){
        $r=reportTake($pdo,$rid,$uid);sendMessage($peer,$r?"📥 Репорт #{$rid} закреплён за вами.\n\n".reportCard($pdo,$rid):'❌ Репорт не найден.');
    }elseif($cmd==='report_open'){
        sendMessage($peer,reportCard($pdo,$rid));
    }elseif($cmd==='report_reply_hint'){
        sendMessage($peer,"✉️ Для ответа используйте:\n!ответ {$rid} ваш текст");
    }elseif($cmd==='report_close'){
        $ok=reportClose($pdo,$rid,$uid,'Закрыто супер-доступом');
        sendMessage($peer,$ok?"✅ Репорт #{$rid} закрыт.":'❌ Репорт не найден.');
    }else{$answer=['type'=>'show_snackbar','text'=>'Неизвестная кнопка'];}
    if($eventId)vk('messages.sendMessageEventAnswer',['event_id'=>$eventId,'user_id'=>$uid,'peer_id'=>$peer,'event_data'=>json_encode($answer,JSON_UNESCAPED_UNICODE)]);
}

function lp():array{global $groupId;for($i=0;$i<5;$i++){$r=vk('groups.getLongPollServer',['group_id'=>$groupId]);if(isset($r['response']))return$r['response'];sleep(2);}throw new RuntimeException('Cannot get VK Long Poll server');}

botLog("MYSQL SCHEMA READY");botLog("RAZE RUSSIA VK BOT MYSQL started.");startupCheck();
while(true){try{$s=lp();$key=$s['key'];$server=$s['server'];$ts=$s['ts'];while(true){sendScheduled($pdo);$u=$server.'?act=a_check&key='.rawurlencode($key).'&wait=25&ts='.rawurlencode($ts);$c=stream_context_create(['http'=>['timeout'=>35,'ignore_errors'=>true]]);$r=@file_get_contents($u,false,$c);if($r===false)throw new RuntimeException('Long Poll connection failed');$d=json_decode($r,true);if(!is_array($d))throw new RuntimeException('Invalid Long Poll response');if(isset($d['ts']))$ts=$d['ts'];if(isset($d['failed']))break;foreach(($d['updates']??[])as$x){if(($x['type']??'')==='message_event'){handleMessageEvent($x);continue;}if(($x['type']??'')!=='message_new')continue;$o=$x['object']??[];if(isset($o['message'])&&is_array($o['message']))$o=$o['message'];handle($pdo,$o);}}}catch(Throwable$e){botLog('WARN: '.$e->getMessage());sleep(3);}}