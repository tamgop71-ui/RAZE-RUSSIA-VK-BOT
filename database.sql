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
function prettyBotText(string $text):string{ $t=trim($text); if($t===''||str_starts_with($t,'🟣 RAZE RUSSIA')) return $text; return "┏━━━━━━━━━━━━━━━━━━┓\n🟣 RAZE RUSSIA\n┗━━━━━━━━━━━━━━━━━━┛\n\n".$t; }
function sendMessage(int $peer,string $text):bool{$text=prettyBotText($text);$r=vk('messages.send',['peer_id'=>$peer,'random_id'=>random_int(-2147483648,2147483647),'message'=>$text]);if(isset($r['error'])){botLog('SEND ERROR peer='.$peer.' '.json_encode($r['error'],JSON_UNESCAPED_UNICODE));return false;}botLog("SENT to {$peer}");return true;}
function sendMessageKeyboard(int $peer,string $text,string $keyboard):bool{$text=prettyBotText($text);$r=vk('messages.send',['peer_id'=>$peer,'random_id'=>random_int(-2147483648,2147483647),'message'=>$text,'keyboard'=>$keyboard]);if(isset($r['error'])){botLog('SEND ERROR peer='.$peer.' '.json_encode($r['error'],JSON_UNESCAPED_UNICODE));return false;}botLog("SENT to {$peer} WITH KEYBOARD");return true;}
function actionKeyboard(string $label,string $cmd,array $data,string $color='secondary'):string{return json_encode(['inline'=>true,'buttons'=>[[['action'=>['type'=>'callback','label'=>$label,'payload'=>json_encode(array_merge(['cmd'=>$cmd],$data),JSON_UNESCAPED_UNICODE)],'color'=>$color]]]],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);}

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
function startupCheck():void{global $groupId;$r=vk('groups.getById',['group_id'=>$groupId]);if(isset($r['error'])){fwrite(STDERR,'VK getById ERROR: '.json_encode($r['error'],JSON_UNESCAPED_UNICODE)."\n");return;}$g=$r['response']['groups'][0]??[];fwrite(STDOUT,'VK group: '.($g['name']??'unknown')." (#{$groupId})\n");$s=vk('groups.setLongPollSettings',['group_id'=>$groupId,'api_version'=>'5.199','enabled'=>1,'message_new'=>1,'message_event'=>1,'message_reply'=>0,'message_allow'=>0,'message_deny'=>0,'message_edit'=>0,'message_typing_state'=>0,'message_reaction_event'=>0,'message_reaction_new'=>0,'message_reaction_remove'=>0]);if(isset($s['error']))fwrite(STDERR,'Long Poll settings ERROR: '.json_encode($s['error'],JSON_UNESCAPED_UNICODE)."\n");else fwrite(STDOUT,"Long Poll: message_new enabled\n");}

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
    $pdo->exec("SET time_zone = '+03:00'");
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
CREATE TABLE IF NOT EXISTS chat_users(id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,peer_id BIGINT NOT NULL,user_id BIGINT NOT NULL,role_id INT NOT NULL DEFAULT 1,nickname VARCHAR(255) NULL,immunity TINYINT NOT NULL DEFAULT 0,mention_optout TINYINT NOT NULL DEFAULT 0,last_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,messages INT NOT NULL DEFAULT 0,UNIQUE KEY uq_chat_user(peer_id,user_id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS chat_settings(peer_id BIGINT NOT NULL PRIMARY KEY,rules TEXT,welcome TEXT,silence_until DATETIME NULL,games_enabled TINYINT NOT NULL DEFAULT 0,automod_enabled TINYINT NOT NULL DEFAULT 0,mentions_enabled TINYINT NOT NULL DEFAULT 1,report_notify_peer BIGINT NOT NULL DEFAULT 0) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS bot_chats(peer_id BIGINT NOT NULL PRIMARY KEY,title VARCHAR(255) NOT NULL DEFAULT '',chat_link VARCHAR(512) NOT NULL DEFAULT '',is_active TINYINT NOT NULL DEFAULT 1,first_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,last_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,INDEX idx_bot_chats_active(is_active)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
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
CREATE TABLE IF NOT EXISTS sysbans(user_id BIGINT NOT NULL PRIMARY KEY,granted_by BIGINT NOT NULL,created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL);
$pdo->exec("INSERT IGNORE INTO roles(id,name,priority) VALUES(1,'Участник',0),(2,'Помощник',20),(3,'Модератор',40),(4,'Администратор',60),(5,'Ст. администратор',80),(6,'Владелец',100)");
function ensureColumn(PDO $p,string $table,string $column,string $definition):void{
    $stmt=$p->prepare("SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? AND COLUMN_NAME=?");
    $stmt->execute([$table,$column]);
    if(!(int)$stmt->fetchColumn()) $p->exec("ALTER TABLE `".str_replace('`','',$table)."` ADD COLUMN `".str_replace('`','',$column)."` {$definition}");
} 
ensureColumn($pdo,'chat_users','messages','INT NOT NULL DEFAULT 0');
ensureColumn($pdo,'chat_users','mention_optout','TINYINT NOT NULL DEFAULT 0');
ensureColumn($pdo,'chat_settings','mentions_enabled','TINYINT NOT NULL DEFAULT 1');
ensureColumn($pdo,'chat_settings','report_notify_peer','BIGINT NOT NULL DEFAULT 0');
ensureColumn($pdo,'reports','assigned_to','BIGINT NULL');
ensureColumn($pdo,'reports','closed_at','DATETIME NULL');
ensureColumn($pdo,'reports','closed_by','BIGINT NULL');
ensureColumn($pdo,'reports','close_reason','TEXT NULL');
ensureColumn($pdo,'reports','answer_count','INT NOT NULL DEFAULT 0');
ensureColumn($pdo,'reports','last_answer_at','DATETIME NULL');
ensureColumn($pdo,'report_messages','direction',"VARCHAR(16) NOT NULL DEFAULT 'user'");


function chatTitleAndLink(int $peer):array{
    if($peer<2000000001) return ['title'=>'Личные сообщения','link'=>''];
    $r=vk('messages.getConversationsById',['peer_ids'=>$peer]);
    $item=$r['response']['items'][0]??[];
    $title=(string)($item['conversation']['chat_settings']['title']??'');
    if($title==='') $title='Без названия';
    $link='https://vk.com/im?sel=c'.($peer-2000000000);
    return ['title'=>$title,'link'=>$link];
}
function ensureBotChat(PDO $p,int $peer,bool $refresh=false):void{
    if($peer<2000000001)return;
    $q=$p->prepare('SELECT peer_id,title,chat_link FROM bot_chats WHERE peer_id=? LIMIT 1');$q->execute([$peer]);$row=$q->fetch();
    if($row && !$refresh){$p->prepare('UPDATE bot_chats SET is_active=1,last_seen=NOW() WHERE peer_id=?')->execute([$peer]);return;}
    $info=$refresh?chatTitleAndLink($peer):['title'=>'Без названия','link'=>'https://vk.com/im?sel=c'.($peer-2000000000)];
    if($row && $row['title']!=='' && !$refresh)$info=['title'=>$row['title'],'link'=>$row['chat_link']];
    $p->prepare("INSERT INTO bot_chats(peer_id,title,chat_link,is_active,first_seen,last_seen) VALUES(?,?,?,1,NOW(),NOW()) ON DUPLICATE KEY UPDATE title=VALUES(title),chat_link=VALUES(chat_link),is_active=1,last_seen=NOW()")
      ->execute([$peer,$info['title'],$info['link']]);
}
function botChatName(PDO $p,int $peer):string{
    $q=$p->prepare('SELECT title FROM bot_chats WHERE peer_id=?');$q->execute([$peer]);$t=(string)($q->fetchColumn()?:'');
    if($t===''){ensureBotChat($p,$peer);$q->execute([$peer]);$t=(string)($q->fetchColumn()?:'Без названия');}
    return $t;
}
function botChatLink(PDO $p,int $peer):string{
    $q=$p->prepare('SELECT chat_link FROM bot_chats WHERE peer_id=?');$q->execute([$peer]);$t=(string)($q->fetchColumn()?:'');
    if($t===''){$t='https://vk.com/im?sel=c'.($peer-2000000000);}
    return $t;
}
function chatMembers(int $peer):array{
    $r=vk('messages.getConversationMembers',[
        'peer_id'=>$peer,
        'extended'=>1,
        'fields'=>'online,screen_name,first_name,last_name',
        'count'=>1000
    ]);
    if(isset($r['error'])){
        botLog('CHAT MEMBERS ERROR peer='.$peer.' '.json_encode($r['error'],JSON_UNESCAPED_UNICODE));
        return [];
    }
    $items=$r['response']['items']??[];
    $profiles=[];
    foreach(($r['response']['profiles']??[]) as $profile){
        $profiles[(int)($profile['id']??0)]=$profile;
    }
    foreach($items as &$item){
        $uid=(int)($item['member_id']??0);
        if(isset($profiles[$uid])){
            $item['online']=(int)($profiles[$uid]['online']??0);
            $item['first_name']=$profiles[$uid]['first_name']??'';
            $item['last_name']=$profiles[$uid]['last_name']??'';
            $item['screen_name']=$profiles[$uid]['screen_name']??'';
        }else{
            $item['online']=(int)($item['online']??0);
        }
    }
    unset($item);
    return $items;
}

function ensureUser(PDO $p,int $peer,int $uid):void{$s=$p->prepare("INSERT INTO chat_users(peer_id,user_id,role_id,last_seen) VALUES(?,?,1,CURRENT_TIMESTAMP) ON DUPLICATE KEY UPDATE last_seen=CURRENT_TIMESTAMP,messages=messages+1");$s->execute([$peer,$uid]);$e=$p->prepare('INSERT IGNORE INTO economy(peer_id,user_id) VALUES(?,?)');$e->execute([$peer,$uid]);}
function priority(PDO $p,int $peer,int $uid):int{$s=$p->prepare('SELECT r.priority FROM chat_users u JOIN roles r ON r.id=u.role_id WHERE u.peer_id=? AND u.user_id=?');$s->execute([$peer,$uid]);return(int)($s->fetchColumn()?:0);}
function isSuper(int $uid):bool{global $pdo,$ownerIds;if(in_array($uid,$ownerIds,true))return true;$s=$pdo->prepare('SELECT 1 FROM superusers WHERE user_id=?');$s->execute([$uid]);return(bool)$s->fetchColumn();}
function level(PDO $p,int $peer,int $uid):int{return isSuper($uid)?100:priority($p,$peer,$uid);}
function loga(PDO $p,int $peer,int $actor,?int $target,string $action,string $details=''):void{$s=$p->prepare('INSERT INTO logs(peer_id,actor_id,target_id,action,details) VALUES(?,?,?,?,?)');$s->execute([$peer,$actor,$target,$action,$details]);}
function expire(PDO $p):void{$p->exec("UPDATE bans SET active=0 WHERE active=1 AND expires_at IS NOT NULL AND expires_at<=NOW()");$p->exec("UPDATE mutes SET active=0 WHERE active=1 AND expires_at IS NOT NULL AND expires_at<=NOW()");}
function parseCommand(string $t):array{$t=trim($t);if($t==='')return['',[]];$t=preg_replace('/^[!\/\.,#?]+/u','',$t);$a=preg_split('/\s+/u',$t);$cmd=mb_strtolower((string)array_shift($a));$aliases=['commands'=>'команды','cmd'=>'команды','rules'=>'правила','roles'=>'роли','admins'=>'админы','online'=>'онлайн','profile'=>'профиль','bonus'=>'бонус','casino'=>'казино','transfer'=>'перевод','top'=>'топ','citizenship'=>'гражданство','country'=>'страна','countries'=>'страны','marriage'=>'брак','divorce'=>'развод','hug'=>'обнять','try'=>'попытка','beer'=>'пиво','mute'=>'мут','unmute'=>'унмут','kick'=>'кик','warn'=>'пред','unwarn'=>'унварн','warnings'=>'предупреждения','warns'=>'предупреждения','ban'=>'бан','unban'=>'унбан','nickname'=>'ник','nick'=>'ник','setnick'=>'сник','removenick'=>'рник','nicklist'=>'нлист','nonicks'=>'безников','call'=>'вызов','chatinfo'=>'чатинфо','register'=>'reg','mention'=>'упоминать','nomention'=>'неупоминать','helper'=>'помощник','moder'=>'модер','silence'=>'тишина','findnick'=>'понику','globalcall'=>'gzov','globalkick'=>'gkick','globalnick'=>'gsnick','giveadmin'=>'admin','givehelper'=>'гпомощник','givemoder'=>'гмодер','globalban'=>'gban','globalunban'=>'gunban','globalrole'=>'grole','delete'=>'удалить','immunity'=>'gm','removeimmunity'=>'removegm','immunities'=>'gms','newrole'=>'newrole','delrole'=>'delrole','welcome'=>'welcome','setrules'=>'setrules','deleterules'=>'delrules','inactive'=>'неактив','givemoney'=>'givemoney','money'=>'givemoney','timeannounce'=>'timeuved','settings'=>'settings','setup'=>'setup','unity'=>'unity','addunity'=>'addunity','createunity'=>'createunity','editunity'=>'editunity','removeunity'=>'removeunity','sync'=>'sync','owner'=>'owner','automod'=>'automod','addsuper'=>'addws','super'=>'addws','setlog'=>'setlog','globalcallall'=>'zovvv','globalannounce'=>'gtimeuvedg','globalcallg'=>'gzovg','reportedit'=>'reportedit','getdialog'=>'getdialog','getreport'=>'getreport','reports'=>'reports','listunities'=>'listunities','unityinfo'=>'unityinfo','uninfo'=>'unityinfo','leaveunity'=>'leaveunity','deleteunity'=>'deleteunity','delunity'=>'deleteunity','объединение'=>'unity','создатьобъединение'=>'createunity','добавитьвобъединение'=>'addunity','удалитьизобъединения'=>'removeunity','объединения'=>'listunities','объединениеинфо'=>'unityinfo','выйтиобъединения'=>'leaveunity','удалитьобъединение'=>'deleteunity','гкик'=>'gkick','гсник'=>'gsnick','гбан'=>'gban','гунбан'=>'gunban','гроль'=>'grole','гзов'=>'gzov','гглава'=>'gspec','listen'=>'listen','chatlist'=>'chatlist','userchats'=>'userchats','ahistory'=>'ahistory','checkban'=>'checkban','rep'=>'report','репорты'=>'reports','ticket'=>'getreport','reply'=>'ответ','ответить'=>'ответ','take'=>'взять','claim'=>'взять','close'=>'закрыть','reopen'=>'открытьрепорт','reportdialog'=>'getdialog','repdialog'=>'getdialog','myreports'=>'мои','superlist'=>'суперы','addsuper'=>'добавитьсупер','delsuper'=>'удалитьсупер','checksuper'=>'проверкасуперов','checksupers'=>'проверкасуперов','тестсуперов'=>'проверкасуперов','testreport'=>'тестрепорт','sysrole'=>'sysrole','sysban'=>'sysban','sysunban'=>'sysunban','staff'=>'staff','сотрудники'=>'staff','version'=>'версия'];if(isset($aliases[$cmd]))$cmd=$aliases[$cmd];return[$cmd,$a];}
function resolveUserToken(string $v):?int{
    $v=trim($v);
    if(preg_match('/^\[id(\d+)\|/i',$v,$m))return(int)$m[1];
    if(preg_match('/^(?:@)?(?:id)?(\d+)$/i',$v,$m))return(int)$m[1];
    if(preg_match('/^(?:https?:\/\/)?(?:www\.)?vk\.com\/(?:id)?([A-Za-z0-9_.]+)\/?$/i',$v,$m))$v=$m[1];
    if(str_starts_with($v,'@'))$v=substr($v,1);
    if($v!==''){$r=vk('users.get',['user_ids'=>$v]);if(isset($r['response'][0]['id']))return(int)$r['response'][0]['id'];}
    return null;
}
function target(array $o,array $a):?int{
    if(isset($o['reply_message']['from_id']))return abs((int)$o['reply_message']['from_id']);
    foreach(array_slice($a,0,2) as $v){$t=resolveUserToken((string)$v);if($t!==null)return $t;}
    return null;
}
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
function amount(string $s):int{$s=mb_strtolower(str_replace(['₽',' ',','],'',$s));$m=1;if(str_ends_with($s,'кк')){$m=1000000;$s=substr($s,0,-2);}elseif(str_ends_with($s,'к')){$m=1000;$s=substr($s,0,-1);}if(!is_numeric($s))return 0;return (int)round((float)$s*$m);}
function rulesText(PDO $p,int $peer):string{$s=$p->prepare('SELECT rules FROM chat_settings WHERE peer_id=?');$s->execute([$peer]);return(string)($s->fetchColumn()?:'Правила беседы ещё не настроены.');}
function requireLevel(int $have,int $need,string $role):?string{return $have<$need?"🤖 У Вас недостаточно высокий приоритет для использования этой команды.\nНеобходимая роль: '{$role}' (№{$need}), ваша роль: №{$have}.":null;}
function punishAllowed(PDO $p,int $peer,int $actor,int $target,int $need):?string{$al=level($p,$peer,$actor);$tl=priority($p,$peer,$target);if($actor===$target)return'❌ Нельзя применить наказание к самому себе.';if($tl>=$al)return'❌ Вы не можете применить наказание к пользователю, роль которого выше или равна вашей.';$s=$p->prepare('SELECT immunity FROM chat_users WHERE peer_id=? AND user_id=?');$s->execute([$peer,$target]);if((int)($s->fetchColumn()?:0)===1&&$al<100)return'❌ У пользователя включён иммунитет.';return null;}
function manageTargetAllowed(PDO $p,int $peer,int $actor,int $target,bool $allowSelf=false):?string{$al=level($p,$peer,$actor);if(!$target)return'❌ Укажите пользователя ID, тегом или ответом на сообщение.';if(!$allowSelf&&$actor===$target)return'❌ Нельзя изменить собственную роль.';$tl=priority($p,$peer,$target);if($al<100&&$tl>=$al)return'❌ Нельзя изменять пользователя с ролью выше или равной вашей.';return null;}
function helpText():string{return <<<TXT
**RAZE RUSSIA — команды**

**Общие:**
!помощь / !команды / !help — помощь
!пинг / !статус / !версия — состояние и версия
!правила / !роли / !админы / !staff / !онлайн
!myid / !thereid / !id — ID пользователя/беседы
!профиль / !проф — профиль и баланс
!бонус — ежедневный бонус
!казино [ставка] — казино
!перевод [ID/@тег] [сумма] — перевод денег
!топ / !top / !atop — рейтинги
!report [текст] — отправить репорт
!упоминать / !неупоминать — участвовать/не участвовать в массовых упоминаниях
!гражданство [страна] / !страна / !страны
!брак [ID] / !развод / !браки
!поцелуй [ID] / !обнять [ID] / !попытка [действие] / !пиво

**Помощник 20+:**
!мут [ID] [минуты] [причина] / !унмут
!кик [ID] [причина]
!пред / !варн [ID] [причина] / !унварн / !снятьпред
!предупреждения / !getwarns / !getwarn / !warnlist / !преды
!бан [ID] [дни] [причина] / !унбан / !getban
!getmute
!ник / !сник [ID] [ник] / !рник / !нлист / !безников
!вызов [текст] / !чатинфо / !reg

**Модератор 40+:**
!role [ID/@тег] [роль/приоритет] / !removerole
!помощник [ID] / !модер [ID]
!тишина [минуты] / !понику [часть ника]
!звезда [ID] / !снятьзвезду / !звезды
!gzov [текст] / !gkick [ID] / !gsnick [ID] [ник]

**Администратор 60+:**
!gban / !gunban / !grole / !гмодер / !гпомощник
!удалить — ответом на сообщение
!gm / !removegm / !gms

**Ст. администратор 80+:**
!pin / !unpin
!admin / !gadmin
!newrole / !gnewrole / !delrole
!welcome / !setrules / !delrules
!неактив / !timeuved

**Владелец 100+:**
!settings / !setup / !games / !automod / !sync / !wipe
!owner / !spec / !gspec
!givemoney [ID/@тег] [сумма] — также ответом: !givemoney [сумма]
!unity / !createunity / !addunity / !removeunity / !editunity / !unityinfo / !leaveunity / !deleteunity / !listunities
!setlog / !gtimeuvedg / !zovvv / !gzovg
!reportedit / !reports / !репорты / !getreport / !репорт / !getdialog / !диалогрепорта
!взять / !ответ / !закрыть / !открытьрепорт / !мои
!суперы / !добавитьсупер / !удалитьсупер / !проверкасуперов / !тестрепорт
!listen / !chatlist / !userchats / !ahistory / !checkban

**Супер-доступ:**
!sysrole / !sysban / !sysunban

💡 Большинство команд с пользователем поддерживают ответ на его сообщение, @тег, VK ID или ссылку VK.
TXT;}
function unityPeers(PDO $p,int $peer):array{
    $q=$p->prepare('SELECT uc.peer_id FROM unity_chats uc JOIN unity_chats cur ON cur.unity_id=uc.unity_id WHERE cur.peer_id=? ORDER BY uc.peer_id');
    $q->execute([$peer]);
    return array_values(array_unique(array_map('intval',$q->fetchAll(PDO::FETCH_COLUMN))));
}
function unityIdByPeer(PDO $p,int $peer):int{
    $q=$p->prepare('SELECT unity_id FROM unity_chats WHERE peer_id=? LIMIT 1');$q->execute([$peer]);return (int)($q->fetchColumn()?:0);
}
function unityKeyboard(int $uid):string{
 return json_encode(['inline'=>true,'buttons'=>[
  [['action'=>['type'=>'callback','label'=>'🔄 Обновить','payload'=>json_encode(['cmd'=>'unity_refresh','unity_id'=>$uid],JSON_UNESCAPED_UNICODE)],'color'=>'secondary']],
  [['action'=>['type'=>'callback','label'=>'➕ Добавить беседу','payload'=>json_encode(['cmd'=>'unity_add','unity_id'=>$uid],JSON_UNESCAPED_UNICODE)],'color'=>'positive'],['action'=>['type'=>'callback','label'=>'➖ Убрать беседу','payload'=>json_encode(['cmd'=>'unity_remove','unity_id'=>$uid],JSON_UNESCAPED_UNICODE)],'color'=>'negative']],
  [['action'=>['type'=>'callback','label'=>'🚪 Выйти','payload'=>json_encode(['cmd'=>'unity_leave','unity_id'=>$uid],JSON_UNESCAPED_UNICODE)],'color'=>'secondary'],['action'=>['type'=>'callback','label'=>'🗑 Удалить','payload'=>json_encode(['cmd'=>'unity_delete','unity_id'=>$uid],JSON_UNESCAPED_UNICODE)],'color'=>'negative']]
 ]],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
}

function unityInfo(PDO $p,int $uid):?array{
    $q=$p->prepare('SELECT id,name,owner_id,created_at FROM unities WHERE id=?');$q->execute([$uid]);$r=$q->fetch();return $r?:null;
}
function unityCanManage(PDO $p,int $peer,int $from,int $uid=0):bool{
    if(isSuper($from)) return true;
    $uid=$uid?:unityIdByPeer($p,$peer); if(!$uid)return false;
    $u=unityInfo($p,$uid); return $u && (int)$u['owner_id']===$from;
}
function doGlobal(PDO $p,int $peer,int $uid,string $action,callable $fn):array{
    $targets=unityPeers($p,$peer);
    if(!$targets){sendMessage($peer,'❌ Эта команда работает только внутри объединения. Сначала добавьте беседу в объединение.');return [];}
    $ok=0;$fail=0;
    foreach($targets as $other){try{if($fn((int)$other)!==false)$ok++;else $fail++;}catch(Throwable $e){$fail++;botLog("UNITY {$action} peer={$other} ERROR: ".$e->getMessage());}}
    botLog("UNITY {$action} actor={$uid} source={$peer} targets=".count($targets)." ok={$ok} fail={$fail}");
    return ['targets'=>count($targets),'ok'=>$ok,'fail'=>$fail];
}
function mentionAll(PDO $p,int $peer,string $text):void{$m=chatMembers($peer);$ids=[];$opt=[];$q=$p->prepare('SELECT user_id FROM chat_users WHERE peer_id=? AND mention_optout=1');$q->execute([$peer]);foreach($q as $r)$opt[(int)$r['user_id']]=true;foreach($m as $x){$id=(int)($x['member_id']??0);if($id>0&&!isset($opt[$id]))$ids[]=$id;}if(!$ids){sendMessage($peer,$text);return;} $out=$text."\n";foreach(array_slice($ids,0,100) as $id)$out.="[id{$id}|❤️ ] ";sendMessage($peer,$out);}
function sendScheduled(PDO $p):void{$now=date('Y-m-d H:i:s');$s=$p->prepare('SELECT * FROM schedules WHERE active=1 AND next_at<=?');$s->execute([$now]);foreach($s as $row){sendMessage((int)$row['peer_id'],$row['text']);$next=date('Y-m-d H:i:s',time()+((int)$row['every_minutes']*60));$p->prepare('UPDATE schedules SET next_at=? WHERE id=?')->execute([$next,$row['id']]);}}

function roleButton(int $peer,int $target,int $actor):string{return actionKeyboard('➖ Снять роль','remove_role',['peer'=>$peer,'target'=>$target,'actor'=>$actor]);}
function nickButton(int $peer,int $target,int $actor):string{return actionKeyboard('➖ Снять ник','remove_nick',['peer'=>$peer,'target'=>$target,'actor'=>$actor]);}
function casinoButton(int $peer,int $actor,int $bet):string{return actionKeyboard('🎰 Повторить','casino_repeat',['peer'=>$peer,'actor'=>$actor,'target'=>$actor,'bet'=>$bet],'positive');}
function ensureChatLeadership(PDO $p,int $peer):void{
    foreach(chatMembers($peer) as $m){$uid=(int)($m['member_id']??0);if($uid<=0)continue;ensureUser($p,$peer,$uid);$role=!empty($m['is_owner'])?6:(!empty($m['is_admin'])?5:1);if($role>1)$p->prepare('UPDATE chat_users SET role_id=? WHERE peer_id=? AND user_id=?')->execute([$role,$peer,$uid]);}
}
function isSysBanned(PDO $p,int $uid):bool{
    $q=$p->prepare('SELECT 1 FROM sysbans WHERE user_id=? LIMIT 1');$q->execute([$uid]);return(bool)$q->fetchColumn();
}
function knownPeers(PDO $p):array{
    $out=[];
    foreach($p->query('SELECT peer_id FROM chat_settings') as $r)$out[]=(int)$r['peer_id'];
    foreach($p->query('SELECT DISTINCT peer_id FROM chat_users') as $r)$out[]=(int)$r['peer_id'];
    foreach($p->query('SELECT peer_id FROM bot_chats WHERE is_active=1') as $r)$out[]=(int)$r['peer_id'];
    return array_values(array_unique(array_filter($out,fn($v)=>$v>=2000000001)));
}
function sysKickFromPeer(int $peer,int $uid):bool{
    $chatId=$peer-2000000000;
    if($chatId<1)return false;
    $r=vk('messages.removeChatUser',['chat_id'=>$chatId,'member_id'=>$uid]);
    if(isset($r['error'])){botLog("SYSBAN KICK ERROR peer={$peer} uid={$uid} ".json_encode($r['error'],JSON_UNESCAPED_UNICODE));return false;}
    return true;
}
function sysKickEverywhere(PDO $p,int $uid):array{
    $peers=knownPeers($p);$ok=0;$fail=0;
    foreach($peers as $peer){if(sysKickFromPeer($peer,$uid))$ok++;else $fail++;}
    botLog("SYSBAN SWEEP uid={$uid} peers=".count($peers)." ok={$ok} fail={$fail}");
    return [$ok,$fail,count($peers)];
}
function checkSysBanAction(PDO $p,int $peer,array $action):bool{
    $type=(string)($action['type']??'');
    if(!in_array($type,['chat_invite_user','chat_invite_user_by_link'],true))return false;
    $uid=abs((int)($action['member_id']??0));
    if($uid<=0 || $uid===0)return false;
    if(!isSysBanned($p,$uid))return false;
    sysKickFromPeer($peer,$uid);
    sendMessage($peer,'⛔ Пользователь '.nameOf($uid).' находится в системном бане и был автоматически исключён из беседы.');
    botLog("SYSBAN AUTO-KICK peer={$peer} uid={$uid} action={$type}");
    return true;
}

function setRoleByPriority(PDO $p,int $peer,int $target,int $priority):bool{$q=$p->prepare('SELECT id FROM roles WHERE priority=? LIMIT 1');$q->execute([$priority]);$rid=(int)($q->fetchColumn()?:0);if(!$rid)return false;$p->prepare('INSERT INTO chat_users(peer_id,user_id,role_id) VALUES(?,?,?) ON DUPLICATE KEY UPDATE role_id=VALUES(role_id)')->execute([$peer,$target,$rid]);return true;}

function handle(PDO $p,array $o):void{
 global $ownerIds,$groupId;
 $peer=(int)($o['peer_id']??0);$from=(int)($o['from_id']??0);$text=trim((string)($o['text']??''));
 if(!$peer)return; if($peer>=2000000001) ensureBotChat($p,$peer,false); if($peer>=2000000001&&$from>0){$sq=$p->prepare('SELECT silence_until FROM chat_settings WHERE peer_id=?');$sq->execute([$peer]);$silence=$sq->fetchColumn();if($silence&&strtotime((string)$silence)>time()&&level($p,$peer,$from)<40){$cmid=(int)($o['conversation_message_id']??0);if($cmid)vk('messages.delete',['peer_id'=>$peer,'cmids'=>$cmid,'delete_for_all'=>1]);return;}} botLog("EVENT message_new peer={$peer} from={$from} text=".json_encode($text,JSON_UNESCAPED_UNICODE));if($from>0)ensureUser($p,$peer,$from);expire($p);$actions=[];if(isset($o['action'])&&is_array($o['action']))$actions[]=$o['action'];if(isset($o['object']['action'])&&is_array($o['object']['action']))$actions[]=$o['object']['action'];foreach($actions as $action){botLog('ACTION '.json_encode($action,JSON_UNESCAPED_UNICODE)); $atype=(string)($action['type']??''); $member=abs((int)($action['member_id']??0)); if($atype==='chat_kick_user' && $member>0 && $member!==$groupId){ $p->prepare('UPDATE chat_users SET role_id=1,immunity=0,mention_optout=0 WHERE peer_id=? AND user_id=?')->execute([$peer,$member]); $p->prepare('DELETE FROM nicknames WHERE peer_id=? AND user_id=?')->execute([$peer,$member]); botLog("RESET MEMBER peer={$peer} user={$member}: role/nickname/immunity/mention settings cleared"); } if($atype==='chat_kick_user' && $member===$groupId){ $p->prepare('UPDATE bot_chats SET is_active=0,last_seen=NOW() WHERE peer_id=?')->execute([$peer]); } elseif($atype==='chat_invite_user' && $member===$groupId){ ensureBotChat($p,$peer,true); } if(checkSysBanAction($p,$peer,$action))return;if(($action['type']??'')==='chat_invite_user'&&abs((int)($action['member_id']??0))!==$groupId){$joined=abs((int)($action['member_id']??0));if($joined>0){$wq=$p->prepare('SELECT welcome FROM chat_settings WHERE peer_id=?');$wq->execute([$peer]);$welcome=trim((string)($wq->fetchColumn()?:''));if($welcome!=='')sendMessage($peer,$welcome);}} if(($action['type']??'')==='chat_invite_user'&&abs((int)($action['member_id']??0))===$groupId){$p->prepare("INSERT IGNORE INTO chat_settings(peer_id,rules,welcome,mentions_enabled) VALUES(?,?,?,1)")->execute([$peer,'Правила беседы ещё не настроены.','Добро пожаловать в RAZE RUSSIA!']); ensureBotChat($p,$peer,true);botLog("BOT INVITED peer={$peer} member_id=".(int)($action['member_id']??0));ensureChatLeadership($p,$peer);sendMessage($peer,"🤖 RAZE RUSSIA подключён!\n\n⚙️ Настройка:\n1) Выдайте сообществу права администратора беседы.\n2) Разрешите управление сообщениями и участниками.\n3) Напишите !помощь — список команд.\n\n🔹 Префиксы: ! / . , # ?\n🔹 Примеры: !пинг, /пинг, .пинг, ,пинг, #пинг, ?пинг\n🔹 Звезда: !звезда [ID]\n🔹 Деньги супер-доступом: !выдатьденьги [ID] [сумма]\n🔹 Репорт: /report текст");return;}}if(!$from)return;
 // Direct diagnostics: these commands bypass alias/priority parsing so they always work for the owner.
 $direct=mb_strtolower(trim($text));
 if(in_array($direct,['!проверкасуперов','/проверкасуперов','.проверкасуперов',',проверкасуперов','#проверкасуперов','?проверкасуперов','!тестрепорт','/тестрепорт','.тестрепорт',',тестрепорт','#тестрепорт','?тестрепорт'],true) && isSuper($from)){
   if(mb_strpos($direct,'тестрепорт')!==false){
      $ids=superIds(); $out="🧪 Тест уведомлений репорта:\n\n";
      if(!$ids) $out.='❌ Не найдено ни одного супер-доступа. Проверь OWNER_IDS или таблицу superusers.';
      foreach($ids as $sid){ $st=dmStatus($sid); if(!$st['ok']){$out.="• ID {$sid} — ⚠️ ошибка API: ".($st['error']??'неизвестно')."\n";continue;} if($st['allowed']===false){$out.="• ID {$sid} — ❌ ЛС запрещены\n";continue;} $ok=sendUser($sid,"🧪 Тестовое уведомление RAZE RUSSIA BOT\nЛС от сообщества разрешены."); $out.="• ID {$sid} — ".($ok?'✅ сообщение отправлено':'❌ ошибка отправки')."\n";}
   } else {
      $out="🔎 Проверка ЛС супер-доступов:\n\n"; $ids=superIds(); if(!$ids)$out.='❌ Список супер-доступов пуст.'; foreach($ids as $sid){$st=dmStatus($sid);$state=$st['ok']?($st['allowed']?'✅ ЛС разрешены':'❌ ЛС запрещены'):'⚠️ ошибка API';$out.="• ID {$sid} — {$state}".($st['error']?" — {$st['error']}":'')."\n";}
   }
   botLog('DIRECT DIAGNOSTIC command='.json_encode($direct,JSON_UNESCAPED_UNICODE).' from='.$from); sendMessage($peer,$out); return;
 }
 [$cmd,$a]=parseCommand($text);if($cmd==='')return;
 $L=level($p,$peer,$from);$target=target($o,$a);$req=[
 'пинг'=>[0,'Участник'],'ping'=>[0,'Участник'],'статус'=>[0,'Участник'],'help'=>[0,'Участник'],'помощь'=>[0,'Участник'],'команды'=>[0,'Участник'],'start'=>[0,'Участник'],'правила'=>[0,'Участник'],'роли'=>[0,'Участник'],'версия'=>[0,'Участник'],'админы'=>[0,'Участник'],'staff'=>[0,'Участник'],'онлайн'=>[0,'Участник'],'history'=>[0,'Участник'],'myid'=>[0,'Участник'],'thereid'=>[0,'Участник'],'id'=>[0,'Участник'],'report'=>[0,'Участник'],'rep'=>[0,'Участник'],'репорты'=>[100,'Владелец'],'репорт'=>[100,'Владелец'],'взять'=>[100,'Владелец'],'ответ'=>[100,'Владелец'],'закрыть'=>[100,'Владелец'],'открытьрепорт'=>[100,'Владелец'],'диалогрепорта'=>[100,'Владелец'],'мои'=>[100,'Владелец'],'суперы'=>[100,'Владелец'],'добавитьсупер'=>[100,'Владелец'],'удалитьсупер'=>[100,'Владелец'],'проверкасуперов'=>[100,'Владелец'],'тестрепорт'=>[100,'Владелец'],'профиль'=>[0,'Участник'],'проф'=>[0,'Участник'],'бонус'=>[0,'Участник'],'bonus'=>[0,'Участник'],'казино'=>[0,'Участник'],'перевод'=>[0,'Участник'],'топ'=>[0,'Участник'],'top'=>[0,'Участник'],'atop'=>[0,'Участник'],'гражданство'=>[0,'Участник'],'страна'=>[0,'Участник'],'страны'=>[0,'Участник'],'брак'=>[0,'Участник'],'развод'=>[0,'Участник'],'браки'=>[0,'Участник'],'поцелуй'=>[0,'Участник'],'kiss'=>[0,'Участник'],'обнять'=>[0,'Участник'],'попытка'=>[0,'Участник'],'пиво'=>[0,'Участник'],
 'сник'=>[20,'Помощник'],'ник'=>[20,'Помощник'],'рник'=>[20,'Помощник'],'нлист'=>[20,'Помощник'],'безников'=>[20,'Помощник'],'мут'=>[20,'Помощник'],'унмут'=>[20,'Помощник'],'кик'=>[20,'Помощник'],'пред'=>[20,'Помощник'],'варн'=>[20,'Помощник'],'унварн'=>[20,'Помощник'],'снятьпред'=>[20,'Помощник'],'предупреждения'=>[20,'Помощник'],'getwarns'=>[20,'Помощник'],'getwarn'=>[20,'Помощник'],'getban'=>[20,'Помощник'],'getmute'=>[20,'Помощник'],'warnlist'=>[20,'Помощник'],'преды'=>[20,'Помощник'],'бан'=>[20,'Помощник'],'унбан'=>[20,'Помощник'],'вызов'=>[20,'Помощник'],'чатинфо'=>[20,'Помощник'],'reg'=>[20,'Помощник'],'упоминать'=>[20,'Помощник'],'неупоминать'=>[20,'Помощник'],
 'звезда'=>[40,'Модератор'],'снятьзвезду'=>[40,'Модератор'],'звезды'=>[0,'Участник'],'star'=>[40,'Модератор'],'unstar'=>[40,'Модератор'],'stars'=>[0,'Участник'],
 'sysrole'=>[100,'Супер-доступ'],'sysban'=>[100,'Супер-доступ'],'sysunban'=>[100,'Супер-доступ'],'role'=>[40,'Модератор'],'removerole'=>[40,'Модератор'],'помощник'=>[40,'Модератор'],'модер'=>[40,'Модератор'],'тишина'=>[40,'Модератор'],'понику'=>[40,'Модератор'],'gzov'=>[40,'Модератор'],'gkick'=>[40,'Модератор'],'gsnick'=>[40,'Модератор'],
 'gban'=>[60,'Администратор'],'gunban'=>[60,'Администратор'],'grole'=>[60,'Администратор'],'гмодер'=>[60,'Администратор'],'гпомощник'=>[60,'Администратор'],'удалить'=>[60,'Администратор'],'gm'=>[60,'Администратор'],'removegm'=>[60,'Администратор'],'gms'=>[60,'Администратор'],
 'pin'=>[80,'Ст. администратор'],'unpin'=>[80,'Ст. администратор'],'admin'=>[80,'Ст. администратор'],'gadmin'=>[80,'Ст. администратор'],'newrole'=>[80,'Ст. администратор'],'gnewrole'=>[80,'Ст. администратор'],'delrole'=>[80,'Ст. администратор'],'welcome'=>[80,'Ст. администратор'],'setrules'=>[80,'Ст. администратор'],'delrules'=>[80,'Ст. администратор'],'неактив'=>[80,'Ст. администратор'],'givemoney'=>[100,'Владелец'],'timeuved'=>[80,'Ст. администратор'],
 'settings'=>[100,'Владелец'],'setup'=>[100,'Владелец'],'unity'=>[0,'Участник'],'addunity'=>[0,'Участник'],'createunity'=>[0,'Участник'],'editunity'=>[0,'Участник'],'removeunity'=>[0,'Участник'],'listunities'=>[0,'Участник'],'unityinfo'=>[0,'Участник'],'leaveunity'=>[0,'Участник'],'deleteunity'=>[0,'Участник'],'sync'=>[100,'Владелец'],'spec'=>[100,'Владелец'],'gspec'=>[100,'Владелец'],'wipe'=>[100,'Владелец'],'games'=>[100,'Владелец'],'editcmd'=>[100,'Владелец'],'geditcmd'=>[100,'Владелец'],'gedit'=>[100,'Владелец'],'gsettings'=>[100,'Владелец'],'owner'=>[100,'Владелец'],'automod'=>[100,'Владелец'],
 'setlog'=>[100,'Владелец'],'zovvv'=>[100,'Владелец'],'addws'=>[100,'Владелец'],'gtimeuvedg'=>[100,'Владелец'],'gzovg'=>[100,'Владелец'],'reportedit'=>[100,'Владелец'],'getdialog'=>[100,'Владелец'],'getreport'=>[100,'Владелец'],'reports'=>[100,'Владелец'],'listunities'=>[0,'Участник'],'listen'=>[100,'Владелец'],'chatlist'=>[100,'Владелец'],'userchats'=>[100,'Владелец'],'ahistory'=>[100,'Владелец'],'checkban'=>[100,'Владелец']];
 if(!isset($req[$cmd]))return;[$need,$role]=$req[$cmd];if($L<$need){sendMessage($peer,requireLevel($L,$need,$role)??'❌ Недостаточно прав.');return;}
 $argText=trim(implode(' ',$a));
 switch($cmd){
 case 'пинг':case'ping':case'статус':sendMessage($peer,'🏓 RAZE RUSSIA BOT: онлайн');break;
 case 'help':case'помощь':case'команды':case'start':sendMessage($peer,helpText());break;
 case 'правила':sendMessage($peer,rulesText($p,$peer));break;
 case 'роли':$rows=$p->query('SELECT name,priority FROM roles ORDER BY priority DESC')->fetchAll();$s="👑 Роли:\n";foreach($rows as $r)$s.="• {$r['name']} ({$r['priority']})\n";sendMessage($peer,$s);break;
 case 'версия':sendMessage($peer,'🤖 RAZE RUSSIA BOT\n📦 Build: FINAL-2026-10-03\n🛠 chatMembers + !staff + !онлайн FIX');break;
 case 'админы':case 'staff':$q=$p->prepare('SELECT u.user_id,r.name,r.priority FROM chat_users u JOIN roles r ON r.id=u.role_id WHERE u.peer_id=? AND r.priority>0 ORDER BY r.priority DESC,u.user_id');$q->execute([$peer]);$rows=$q->fetchAll();$s="👮 STAFF / Администрация:

";foreach($rows as $r)$s.="• ".nameOf((int)$r['user_id'])." — {$r['name']} ({$r['priority']})
";if(!$rows)$s.='Пока никому не выданы роли.
';sendMessage($peer,$s);break;
 case 'онлайн':$m=chatMembers($peer);if(!$m){sendMessage($peer,'⚠️ Не удалось получить список участников беседы через VK API. Проверьте, что бот добавлен в беседу и имеет необходимые права.');break;}$online=array_filter($m,fn($x)=>(int)($x['online']??0)===1);sendMessage($peer,'🟢 Онлайн участников: '.count($online).' из '.count($m));break;
 case 'myid':sendMessage($peer,"🆔 Ваш VK ID: {$from}");break;case'thereid':case'id':sendMessage($peer,"🆔 ID этой беседы: {$peer}");break;
 case 'report':$t=$argText;if($t===''){sendMessage($peer,'Использование: /report [текст]');break;}$p->prepare("INSERT INTO reports(peer_id,user_id,text,status) VALUES(?,?,?,'open')")->execute([$peer,$from,$t]);$rid=(int)$p->lastInsertId();addReportMessage($p,$rid,$from,$t,'user');notifyReportSuper($p,$peer,$rid,$from,$t);$s=$p->prepare('SELECT report_notify_peer FROM chat_settings WHERE peer_id=?');$s->execute([$peer]);$np=(int)($s->fetchColumn()?:0);if($np)sendMessage($np,"🆕 Новый репорт #{$rid}\n👤 От: ".nameOf($from)."\n📝 {$t}");sendMessage($peer,"📨 Репорт #{$rid} принят.\n👤 Автор: ".nameOf($from)."\n✅ Репорт отправлен всем супер-доступам в ЛС.");break;
 case 'упоминать':$p->prepare('INSERT INTO chat_users(peer_id,user_id,role_id,mention_optout) VALUES(?,?,1,0) ON DUPLICATE KEY UPDATE mention_optout=0')->execute([$peer,$from]);sendMessage($peer,'✅ Вы снова участвуете в массовых упоминаниях.');break;case'неупоминать':$p->prepare('INSERT INTO chat_users(peer_id,user_id,role_id,mention_optout) VALUES(?,?,1,1) ON DUPLICATE KEY UPDATE mention_optout=1')->execute([$peer,$from]);sendMessage($peer,'✅ Вы исключены из массовых упоминаний.');break;
 case 'profile':case'профиль':case'проф':ensureEconomy($p,$peer,$target??$from);$q=$p->prepare('SELECT * FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$target??$from]);$e=$q->fetch();sendMessage($peer,"👤 Профиль: ".nameOf($target??$from)."\n💰 Баланс: ".number_format((int)$e['balance'],0,'.',' ')." ₽\n🌍 Страна: ".($e['country']?:'не указана')."\n💍 Партнёр: ".($e['partner_id'] ? nameOf((int)$e['partner_id']) : 'нет'));break;
 case 'bonus':case'бонус':ensureEconomy($p,$peer,$from);$q=$p->prepare('SELECT balance,last_bonus FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);$e=$q->fetch();if($e['last_bonus']&&strtotime($e['last_bonus'])>time()-86400){sendMessage($peer,'⏳ Бонус уже получен. Возвращайтесь через 24 часа.');break;}$p->prepare("UPDATE economy SET balance=balance+1000,last_bonus=NOW() WHERE peer_id=? AND user_id=?")->execute([$peer,$from]);sendMessage($peer,'🎁 Вы получили ежедневный бонус: 1 000 ₽!');break;
 case 'казино':$bet=amount($a[0]??'0');ensureEconomy($p,$peer,$from);$q=$p->prepare('SELECT balance FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);$bal=(int)$q->fetchColumn();if($bet<=0||$bet>$bal){sendMessage($peer,"🎰 Недостаточно средств. Ваш баланс: ".number_format($bal,0,'.',' '));break;}$roll=random_int(1,100);$mult = $roll <= 10 ? 0 : ($roll <= 55 ? 1 : ($roll <= 85 ? 1.5 : 2.5));$delta=(int)round($bet*$mult)-$bet;$p->prepare('UPDATE economy SET balance=balance+?,last_casino=datetime(\'now\') WHERE peer_id=? AND user_id=?')->execute([$delta,$peer,$from]);sendMessageKeyboard($peer,"🎰 Результат: {$mult}×\n".($delta>=0?'Вы выиграли ':'Вы проиграли ').number_format(abs($delta),0,'.',' ')." ₽",casinoButton($peer,$from,$bet));break;
 case 'перевод':$t = $target ?? (isset($a[0]) ? (int)$a[0] : 0);$sum=amount($a[$target?0:1]??'0');if(!$t||$sum<=0){sendMessage($peer,'Использование: !перевод [ID] [сумма]');break;}ensureEconomy($p,$peer,$from);ensureEconomy($p,$peer,$t);$p->beginTransaction();$q=$p->prepare('SELECT balance FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);$bal=(int)$q->fetchColumn();if($bal<$sum){$p->rollBack();sendMessage($peer,'❌ Недостаточно средств.');break;}$p->prepare('UPDATE economy SET balance=balance-? WHERE peer_id=? AND user_id=?')->execute([$sum,$peer,$from]);$p->prepare('UPDATE economy SET balance=balance+? WHERE peer_id=? AND user_id=?')->execute([$sum,$peer,$t]);$p->commit();sendMessage($peer,"💸 Перевод выполнен: ".number_format($sum,0,'.',' ')." ₽ отправлено пользователю ".nameOf($t).'.');break;
 case 'топ':case'top':$q=$p->prepare('SELECT user_id,balance FROM economy WHERE peer_id=? ORDER BY balance DESC LIMIT 10');$q->execute([$peer]);$s="👑 Топ игроков по балансу:\n";$i=1;foreach($q as $r)$s.=$i++.'. '.nameOf((int)$r['user_id']).' — '.number_format((int)$r['balance'],0,'.',' ')." ₽\n";sendMessage($peer,$s);break;
 case 'atop':$q=$p->query('SELECT user_id,SUM(balance) balance FROM economy GROUP BY user_id ORDER BY balance DESC LIMIT 10');$s="👑 Общий топ:\n";$i=1;foreach($q as $r)$s.=$i++.'. '.nameOf((int)$r['user_id']).' — '.number_format((int)$r['balance'],0,'.',' ')." ₽\n";sendMessage($peer,$s);break;
 case 'гражданство':$country=trim($argText);if($country===''){sendMessage($peer,'Укажите страну.');break;}$p->prepare('UPDATE economy SET country=? WHERE peer_id=? AND user_id=?')->execute([$country,$peer,$from]);$p->prepare('INSERT IGNORE INTO countries(peer_id,name,owner_id) VALUES(?,?,?)')->execute([$peer,$country,$from]);sendMessage($peer,"🌍 Гражданство установлено: {$country}");break;case'страна':$q=$p->prepare('SELECT country FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);sendMessage($peer,'🌍 Ваша страна: '.($q->fetchColumn()?:'не указана'));break;case'страны':$q=$p->prepare('SELECT name,COUNT(*) citizens FROM countries c LEFT JOIN economy e ON e.peer_id=c.peer_id AND e.country=c.name WHERE c.peer_id=? GROUP BY c.name ORDER BY citizens DESC');$q->execute([$peer]);$s="🌍 Страны:\n";foreach($q as $r)$s.="• {$r['name']} — {$r['citizens']} граждан\n";sendMessage($peer,$s?:'Стран пока нет.');break;
 case 'брак':$t=$target??(int)($a[0]??0);if(!$t||$t===$from){sendMessage($peer,'Укажите ID другого пользователя.');break;}ensureEconomy($p,$peer,$from);ensureEconomy($p,$peer,$t);$p->prepare('UPDATE economy SET partner_id=? WHERE peer_id=? AND user_id=?')->execute([$t,$peer,$from]);$p->prepare('UPDATE economy SET partner_id=? WHERE peer_id=? AND user_id=?')->execute([$from,$peer,$t]);$p->prepare('INSERT IGNORE INTO marriages(peer_id,user1,user2) VALUES(?,?,?)')->execute([$peer,min($from,$t),max($from,$t)]);sendMessage($peer,'💍 Предложение/брак оформлен с '.nameOf($t).'.');break;case'развод':$q=$p->prepare('SELECT partner_id FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$from]);$t=(int)($q->fetchColumn()?:0);if($t){$p->prepare('UPDATE economy SET partner_id=NULL WHERE peer_id=? AND user_id IN (?,?)')->execute([$peer,$from,$t]);$p->prepare('DELETE FROM marriages WHERE peer_id=? AND ((user1=? AND user2=?) OR (user1=? AND user2=?))')->execute([$peer,min($from,$t),max($from,$t),max($from,$t),min($from,$t)]);sendMessage($peer,'💔 Брак расторгнут.');}else sendMessage($peer,'Брака нет.');break;case'браки':$q=$p->prepare('SELECT user1,user2 FROM marriages WHERE peer_id=? LIMIT 20');$q->execute([$peer]);$s="💍 Браки:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user1']).' + '.nameOf((int)$r['user2'])."\n";sendMessage($peer,$s?:'Браков пока нет.');break;
 case 'поцелуй':case'kiss':$t=$target??(int)($a[0]??0);sendMessage($peer,$t?'💋 '.nameOf($from).' поцеловал(а) '.nameOf($t).'.':'Укажите ID.');break;case'обнять':$t=$target??(int)($a[0]??0);sendMessage($peer,$t?'🤗 '.nameOf($from).' обнял(а) '.nameOf($t).'.':'Укажите ID.');break;case'попытка':sendMessage($peer,'🎲 '.nameOf($from).' — '.(random_int(0,1)?'успех!':'неудача!').' Действие: '.$argText);break;case'пиво':sendMessage($peer,'🍺 '.nameOf($from).' выпил(а) виртуальное пиво.');break;
 case 'history':$t=$target??$from;$q=$p->prepare('SELECT action,details,created_at FROM logs WHERE peer_id=? AND target_id=? AND action IN (\'warn\',\'ban\',\'mute\',\'unwarn\',\'unban\',\'unmute\') ORDER BY id DESC LIMIT 20');$q->execute([$peer,$t]);$s="📜 История наказаний: ".nameOf($t)."\n";foreach($q as $r)$s.="• {$r['created_at']} — {$r['action']} — {$r['details']}\n";sendMessage($peer,$s);break;
 case 'сник':case'ник':$t=$target??$from;if($cmd==='ник'&&!$argText){$q=$p->prepare('SELECT nickname FROM nicknames WHERE peer_id=? AND user_id=?');$q->execute([$peer,$t]);sendMessage($peer,'🏷 Ник: '.($q->fetchColumn()?:'не установлен'));break;}$nick=$target ? trim(implode(' ',array_slice($a,1))) : trim($argText);if($nick===''){sendMessage($peer,'Использование: !сник [ID/@тег] [ник]');break;}$p->prepare('INSERT INTO nicknames(peer_id,user_id,nickname) VALUES(?,?,?) ON DUPLICATE KEY UPDATE nickname=VALUES(nickname)')->execute([$peer,$t,$nick]);sendMessageKeyboard($peer,'✅ Ник установлен для '.nameOf($t).': '.$nick,nickButton($peer,$t,$from));break;
 case 'рник':$t=$target??$from;$p->prepare('DELETE FROM nicknames WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'✅ Ник удалён.');break;case'нлист':$q=$p->prepare('SELECT user_id,nickname FROM nicknames WHERE peer_id=? ORDER BY nickname LIMIT 50');$q->execute([$peer]);$s="🏷 Ники:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user_id']).' — '.$r['nickname']."\n";sendMessage($peer,$s);break;case'безников':$q=$p->prepare('SELECT user_id FROM chat_users WHERE peer_id=? AND user_id NOT IN(SELECT user_id FROM nicknames WHERE peer_id=?) LIMIT 50');$q->execute([$peer,$peer]);$s="👤 Без никнейма:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user_id'])."\n";sendMessage($peer,$s);break;
 case 'пред':case'варн':$t=$target??(int)($a[0]??0);$reason=trim(implode(' ',array_slice($a,$target?1:1)));if(!$t){sendMessage($peer,'Укажите ID/ответ.');break;}$bad=punishAllowed($p,$peer,$from,$t,20);if($bad){sendMessage($peer,$bad);break;}$q=$p->prepare('SELECT COUNT(*) FROM warnings WHERE peer_id=? AND user_id=? AND active=1');$q->execute([$peer,$t]);$cnt=(int)$q->fetchColumn();if($cnt>=3){sendMessage($peer,'❌ У пользователя уже 3 активных предупреждения.');break;}$p->prepare('INSERT INTO warnings(peer_id,user_id,moderator_id,reason) VALUES(?,?,?,?)')->execute([$peer,$t,$from,$reason?:'Без причины']);loga($p,$peer,$from,$t,'warn',$reason?:'Без причины');sendMessage($peer,nameOf($t)." получил предупреждение (".($cnt+1).'/3). Причина: '.($reason?:'не указана'));break;
 case 'унварн':case'снятьпред':$t=$target??(int)($a[0]??0);if(!$t){sendMessage($peer,'Укажите ID/ответ.');break;}$q=$p->prepare('SELECT id FROM warnings WHERE peer_id=? AND user_id=? AND active=1 ORDER BY id DESC LIMIT 1');$q->execute([$peer,$t]);$id=$q->fetchColumn();if($id){$p->prepare('UPDATE warnings SET active=0 WHERE id=?')->execute([$id]);loga($p,$peer,$from,$t,'unwarn','Снято последнее предупреждение');sendMessage($peer,'✅ Последнее предупреждение снято.');}else sendMessage($peer,'Активных предупреждений нет.');break;
 case 'предупреждения':case'getwarns':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT COUNT(*) FROM warnings WHERE peer_id=? AND user_id=? AND active=1');$q->execute([$peer,$t]);sendMessage($peer,'⚠️ Активных предупреждений: '.$q->fetchColumn());break;case'getwarn':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT moderator_id,reason,created_at FROM warnings WHERE peer_id=? AND user_id=? ORDER BY id DESC');$q->execute([$peer,$t]);$s='⚠️ Предупреждения '.nameOf($t).":\n";$i=1;foreach($q as $r)$s.=$i++.'. Выдал: '.nameOf((int)$r['moderator_id']).' | '.$r['reason'].' | '.$r['created_at']."\n";sendMessage($peer,$s);break;case'getban':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT moderator_id,days,reason,created_at,expires_at,active FROM bans WHERE peer_id=? AND user_id=? ORDER BY id DESC');$q->execute([$peer,$t]);$s='🔨 Баны '.nameOf($t).":\n";foreach($q as $r)$s.='• '.($r['active']?'активен':'снят').' | выдал '.nameOf((int)$r['moderator_id']).' | '.$r['days'].' дн. | до '.$r['expires_at'].' | '.$r['reason']."\n";sendMessage($peer,$s);break;case'getmute':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT moderator_id,minutes,reason,created_at,expires_at,active FROM mutes WHERE peer_id=? AND user_id=? ORDER BY id DESC');$q->execute([$peer,$t]);$s='🔇 Муты '.nameOf($t).":\n";foreach($q as $r)$s.='• '.($r['active']?'активен':'снят').' | выдал '.nameOf((int)$r['moderator_id']).' | '.$r['minutes'].' мин. | до '.$r['expires_at'].' | '.$r['reason']."\n";sendMessage($peer,$s);break;
 case 'warnlist':case'преды':$q=$p->prepare('SELECT user_id,COUNT(*) c FROM warnings WHERE peer_id=? AND active=1 GROUP BY user_id ORDER BY c DESC');$q->execute([$peer]);$s="⚠️ Список варнов:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user_id']).' — '.$r['c']."\n";sendMessage($peer,$s);break;
 case 'мут':$t=$target??(int)($a[0]??0);$idx=$target?0:1;$mins=(int)($a[$idx]??0);if(!$t||$mins<=0){sendMessage($peer,'Использование: !мут [ID] [минуты] [причина]');break;}$bad=punishAllowed($p,$peer,$from,$t,20);if($bad){sendMessage($peer,$bad);break;}$reason=trim(implode(' ',array_slice($a,$idx+1)))?:'Без причины';$exp=date('Y-m-d H:i:s',time()+$mins*60);$p->prepare('INSERT INTO mutes(peer_id,user_id,moderator_id,minutes,reason,expires_at) VALUES(?,?,?,?,?,?)')->execute([$peer,$t,$from,$mins,$reason,$exp]);loga($p,$peer,$from,$t,'mute',$mins.' мин. | '.$reason);sendMessage($peer,"🔇 ".nameOf($t)." получил мут на {$mins} мин. Причина: {$reason}");break;case'унмут':$t=$target??(int)($a[0]??0);$p->prepare('UPDATE mutes SET active=0 WHERE peer_id=? AND user_id=? AND active=1')->execute([$peer,$t]);loga($p,$peer,$from,$t,'unmute','Мут снят');sendMessage($peer,'🔊 Мут снят.');break;
 case 'кик':$t=$target??(int)($a[0]??0);$bad=punishAllowed($p,$peer,$from,$t,20);if($bad){sendMessage($peer,$bad);break;}$r=vk('messages.removeChatUser',['chat_id'=>$peer-2000000000,'member_id'=>$t]);sendMessage($peer,isset($r['response'])?'👢 Пользователь исключён.':'❌ VK: '.($r['error']['error_msg']??'ошибка'));break;
 case 'бан':$t=$target??(int)($a[0]??0);$idx=$target?0:1;$days=(int)($a[$idx]??0);if(!$t||$days<=0){sendMessage($peer,'Использование: !бан [ID] [дни] [причина]');break;}$bad=punishAllowed($p,$peer,$from,$t,40);if($bad){sendMessage($peer,$bad);break;}$reason=trim(implode(' ',array_slice($a,$idx+1)))?:'не указана';$exp=date('Y-m-d H:i:s',time()+$days*86400);$p->prepare('INSERT INTO bans(peer_id,user_id,moderator_id,days,reason,expires_at) VALUES(?,?,?,?,?,?)')->execute([$peer,$t,$from,$days,$reason,$exp]);loga($p,$peer,$from,$t,'ban',$days.' дн. | '.$reason);sendMessage($peer,"🔨 ".nameOf($t)." заблокирован на {$days} дн.\nПричина: {$reason}");break;case'унбан':$t=$target??(int)($a[0]??0);$p->prepare('UPDATE bans SET active=0 WHERE peer_id=? AND user_id=? AND active=1')->execute([$peer,$t]);loga($p,$peer,$from,$t,'unban','Бан снят');sendMessage($peer,'✅ Бан снят.');break;
 case 'вызов':mentionAll($p,$peer,$argText?:'📢 Вызов участников!');break;case'чатинфо':$m=chatMembers($peer);$q=$p->prepare('SELECT COUNT(*) FROM chat_users WHERE peer_id=?');$q->execute([$peer]);sendMessage($peer,'ℹ️ ID: '.$peer."\nУчастников VK: ".count($m)."\nПользователей в базе: ".$q->fetchColumn());break;case'reg':$t=$target??(int)($a[0]??$from);$q=$p->prepare('SELECT registered_at FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$t]);sendMessage($peer,'📅 Регистрация: '.($q->fetchColumn()?:'нет данных'));break;
 case 'звезда':case 'star':$t=$target??(int)($a[0]??0);$guard=manageTargetAllowed($p,$peer,$from,$t);if($guard){sendMessage($peer,$guard);break;}if(!$t){sendMessage($peer,'⭐ Использование: !звезда [ID] или ответом на сообщение.');break;}$p->prepare('REPLACE INTO stars(peer_id,user_id,granted_by) VALUES(?,?,?)')->execute([$peer,$t,$from]);sendMessage($peer,'⭐ Звезда выдана '.nameOf($t).'.');break;case 'снятьзвезду':case 'unstar':$t=$target??(int)($a[0]??0);$guard=manageTargetAllowed($p,$peer,$from,$t);if($guard){sendMessage($peer,$guard);break;}if(!$t){sendMessage($peer,'⭐ Использование: !снятьзвезду [ID] или ответом.');break;}$p->prepare('DELETE FROM stars WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'⭐ Звезда снята с '.nameOf($t).'.');break;case 'звезды':case 'stars':$q=$p->prepare('SELECT user_id,granted_by FROM stars WHERE peer_id=? ORDER BY created_at');$q->execute([$peer]);$out='⭐ Звёзды беседы:\n';$i=1;foreach($q as $r)$out.=$i++.'. '.nameOf((int)$r['user_id']).' — выдал '.nameOf((int)$r['granted_by'])."\n";sendMessage($peer,$out);break;case 'sysrole':{
 $t=$target;
 if(!$t){
   if(count($a)<1){sendMessage($peer,'Использование: /sysrole [роль] или ответом: /sysrole [роль]');break;}
   $roleArg=trim(implode(' ', $a));
   $t=$from;
 }else{
   $roleArg=trim(implode(' ', $a));
 }
 if($roleArg===''){sendMessage($peer,'Использование: /sysrole [роль]');break;}
 if(level($p,$peer,$from)<100){sendMessage($peer,'❌ /sysrole доступна только супер-доступу.');break;}
 $rr=null;
 if(is_numeric($roleArg)){
   $rp=(int)$roleArg;
   if($rp<0||$rp>100){sendMessage($peer,'❌ Приоритет должен быть от 0 до 100.');break;}
   $q=$p->prepare('SELECT id,name,priority FROM roles WHERE priority=? LIMIT 1');$q->execute([$rp]);$rr=$q->fetch();
 }else{
   $q=$p->prepare('SELECT id,name,priority FROM roles WHERE name=? LIMIT 1');$q->execute([$roleArg]);$rr=$q->fetch();
 }
 if(!$rr){sendMessage($peer,'❌ Такая роль не найдена. Используйте !роли или !newrole [приоритет] [название].');break;}
 $p->prepare('INSERT INTO chat_users(peer_id,user_id,role_id) VALUES(?,?,?) ON DUPLICATE KEY UPDATE role_id=VALUES(role_id)')->execute([$peer,$t,$rr['id']]);
 sendMessageKeyboard($peer,'🛡 Системная роль выдана: '.nameOf($t).' → '.$rr['name'].' ('.$rr['priority'].')',roleButton($peer,$t,$from));
 break;
}
case 'sysban':{
 if(level($p,$peer,$from)<100){sendMessage($peer,'❌ /sysban доступна только супер-доступу.');break;}
 $t=$target??(int)($a[0]??0);
 if(!$t){sendMessage($peer,'Использование: /sysban [ID/@тег] или ответом на сообщение.');break;}
 $p->prepare('INSERT INTO sysbans(user_id,granted_by) VALUES(?,?) ON DUPLICATE KEY UPDATE granted_by=VALUES(granted_by)')->execute([$t,$from]);
 [$ok,$fail,$total]=sysKickEverywhere($p,$t);
 loga($p,$peer,$from,$t,'sysban','global ban; kicked='.$ok.' failed='.$fail.' total='.$total);
 sendMessage($peer,"⛔ Системный бан выдан: ".nameOf($t).".\n👢 Исключено бесед: {$ok}/{$total}.\n🔒 Если пользователя добавят снова, бот автоматически исключит его.");
 break;
}
case 'sysunban':{
 if(level($p,$peer,$from)<100){sendMessage($peer,'❌ /sysunban доступна только супер-доступу.');break;}
 $t=$target??(int)($a[0]??0);
 if(!$t){sendMessage($peer,'Использование: /sysunban [ID/@тег] или ответом на сообщение.');break;}
 $q=$p->prepare('DELETE FROM sysbans WHERE user_id=?');$q->execute([$t]);
 loga($p,$peer,$from,$t,'sysunban','global ban removed');
 sendMessage($peer,$q->rowCount()?'✅ Системный бан снят с '.nameOf($t).'.':'ℹ️ Пользователь не находился в системном бане.');
 break;
}
case 'role':$t=$target??(int)($a[0]??0);$guard=manageTargetAllowed($p,$peer,$from,$t);if($guard){sendMessage($peer,$guard);break;}$rn=trim(implode(' ',array_slice($a,$target&&isset($o['reply_message'])?0:1)));$rid=null;if(is_numeric($rn)){$q=$p->prepare('SELECT id FROM roles WHERE priority=?');$q->execute([(int)$rn]);$rid=$q->fetchColumn();}else{$q=$p->prepare('SELECT id FROM roles WHERE name=?');$q->execute([$rn]);$rid=$q->fetchColumn();}if(!$t||!$rid){sendMessage($peer,'Использование: !role [ID/@тег] [роль/приоритет]');break;}$rq=$p->prepare('SELECT priority FROM roles WHERE id=?');$rq->execute([$rid]);$newPriority=(int)$rq->fetchColumn();if($newPriority>=level($p,$peer,$from)&&!isSuper($from)){sendMessage($peer,'❌ Нельзя выдать роль, равную или выше вашей.');break;}$p->prepare('INSERT INTO chat_users(peer_id,user_id,role_id) VALUES(?,?,?) ON DUPLICATE KEY UPDATE role_id=VALUES(role_id)')->execute([$peer,$t,$rid]);sendMessageKeyboard($peer,'👑 Роль выдана: '.nameOf($t).' → '.$rn,roleButton($peer,$t,$from));break;case'removerole':$t=$target??(int)($a[0]??0);$guard=manageTargetAllowed($p,$peer,$from,$t);if($guard){sendMessage($peer,$guard);break;}$p->prepare('UPDATE chat_users SET role_id=1 WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'✅ Все роли сняты.');break;case'помощник':case'модер':$t=$target??(int)($a[0]??0);$r=$cmd==='помощник'?2:3;if(!$t){sendMessage($peer,'Использование: !помощник [ID/@тег]');break;}$guard=manageTargetAllowed($p,$peer,$from,$t);if($guard){sendMessage($peer,$guard);break;}if($r>=level($p,$peer,$from)&&!isSuper($from)){sendMessage($peer,'❌ Нельзя выдать роль, равную или выше вашей.');break;}$p->prepare('UPDATE chat_users SET role_id=? WHERE peer_id=? AND user_id=?')->execute([$r,$peer,$t]);$rn=$r===2?'Помощник':'Модератор';sendMessageKeyboard($peer,'👑 Роль назначена: '.nameOf($t).' → '.$rn,roleButton($peer,$t,$from));break;
 case 'тишина':$sv=mb_strtolower(trim($argText));if(in_array($sv,['0','off','выкл','выключить','стоп'],true)){$p->prepare('INSERT INTO chat_settings(peer_id,silence_until) VALUES(?,NULL) ON DUPLICATE KEY UPDATE silence_until=NULL')->execute([$peer]);sendMessage($peer,'🔊 Режим тишины выключен.');break;}$mins=(int)($a[0]??0);if(!$mins)$mins=30;if(str_contains($sv,'час'))$mins=(int)preg_replace('/\D/','',$sv)*60;if(str_contains($sv,'дн'))$mins=(int)preg_replace('/\D/','',$sv)*1440;if($mins<=0){sendMessage($peer,'Использование: !тишина [минуты] или !тишина 0 для отключения.');break;}$until=date('Y-m-d H:i:s',time()+$mins*60);$p->prepare('INSERT INTO chat_settings(peer_id,silence_until) VALUES(?,?) ON DUPLICATE KEY UPDATE silence_until=VALUES(silence_until)')->execute([$peer,$until]);sendMessage($peer,"🔇 Режим тишины включён до {$until}.");break;
 case 'понику':$part=mb_strtolower($argText);$q=$p->prepare('SELECT user_id,nickname FROM nicknames WHERE peer_id=? AND lower(nickname) LIKE ? LIMIT 20');$q->execute([$peer,'%'.$part.'%']);$s='🔎 Поиск:\n';foreach($q as $r)$s.='• '.nameOf((int)$r['user_id']).' — '.$r['nickname']."\n";sendMessage($peer,$s);break;
 case 'gsnick':$t=$target??(int)($a[0]??0);$nick=isset($o['reply_message']['from_id'])?trim(implode(' ',array_slice($a,0))):trim(implode(' ',array_slice($a,1)));if(!$t||$nick===''){sendMessage($peer,'Использование: !gsnick [ID/@тег] [ник]');break;}$res=doGlobal($p,$peer,$from,'gsnick',function(int $c)use($p,$t,$nick){$p->prepare('INSERT INTO nicknames(peer_id,user_id,nickname) VALUES(?,?,?) ON DUPLICATE KEY UPDATE nickname=VALUES(nickname)')->execute([$c,$t,$nick]);return true;});if($res)sendMessage($peer,"🏷 Глобальный ник: {$res['ok']} бесед обновлено из {$res['targets']}.");break;case'gzov':case'gzovg':$msg=$argText?:'📢 Общий вызов!';$targets=unityPeers($p,$peer);if(!$targets)$targets=[$peer];foreach($targets as $c)mentionAll($p,$c,$msg);break;case'zovvv':$msg=$argText?:'📢 Общий вызов!';$all=$p->query('SELECT peer_id FROM chat_settings')->fetchAll(PDO::FETCH_COLUMN);foreach($all as $c)mentionAll($p,(int)$c,$msg);break;case'gkick':$t=$target??(int)($a[0]??0);if(!$t){sendMessage($peer,'Использование: !gkick [ID/@тег]');break;}$res=doGlobal($p,$peer,$from,'gkick',function(int $c)use($t){$chatId=$c-2000000000;if($chatId<1)return false;$r=vk('messages.removeChatUser',['chat_id'=>$chatId,'member_id'=>$t]);if(isset($r['error'])){botLog('GKICK ERROR chat='.$c.' target='.$t.' '.json_encode($r['error'],JSON_UNESCAPED_UNICODE));return false;}return true;});if($res)sendMessage($peer,"👢 Глобальный кик: {$res['ok']} успешно, {$res['fail']} ошибок из {$res['targets']}.");break;
 case 'gban':case'gunban':$t=$target??(int)($a[0]??0);$days=(int)(isset($o['reply_message']['from_id'])?($a[0]??0):($a[1]??0));if(!$t){sendMessage($peer,'Использование: !gban [ID] [дни] [причина]');break;}if($cmd==='gban'&&$days<=0){sendMessage($peer,'❌ Укажите количество дней больше нуля.');break;}$bad=punishAllowed($p,$peer,$from,$t,60);if($bad){sendMessage($peer,$bad);break;}doGlobal($p,$peer,$from,$cmd,function(int $c)use($p,$from,$t,$days,$cmd,$argText){if($cmd==='gban'){$exp=date('Y-m-d H:i:s',time()+$days*86400);$p->prepare('INSERT INTO bans(peer_id,user_id,moderator_id,days,reason,expires_at) VALUES(?,?,?,?,?,?)')->execute([$c,$t,$from,$days,$argText?:'Глобальная блокировка',$exp]);loga($p,$c,$from,$t,'ban',$days.' дн. | глобально | '.$argText);$r=vk('messages.removeChatUser',['chat_id'=>$c-2000000000,'member_id'=>$t]);return !isset($r['error']);}else{$p->prepare('UPDATE bans SET active=0 WHERE peer_id=? AND user_id=?')->execute([$c,$t]);loga($p,$c,$from,$t,'unban','Глобально снят');return true;}});sendMessage($peer,$cmd==='gban'?'🌐 Глобальная блокировка выполнена.':'🌐 Глобальная блокировка снята.');break;
 case 'grole':case'гмодер':case'гпомощник':$t=$target??(int)($a[0]??0);$rn=$cmd==='гмодер'?3:2;if($cmd==='grole'){$rn=(int)(isset($o['reply_message']['from_id'])?($a[0]??3):($a[1]??3));}doGlobal($p,$peer,$from,$cmd,function(int $c)use($p,$t,$rn){$p->prepare('UPDATE chat_users SET role_id=? WHERE peer_id=? AND user_id=?')->execute([$rn,$c,$t]);});sendMessage($peer,'🌐 Глобальная роль обработана.');break;
 case 'удалить':$mid=isset($o['reply_message']['conversation_message_id'])?(int)$o['reply_message']['conversation_message_id']:0;if(!$mid){sendMessage($peer,'🗑 Чтобы удалить сообщение, ответьте на него командой !удалить.');break;} $r=vk('messages.delete',['cmids'=>$mid,'delete_for_all'=>1,'peer_id'=>$peer]);if(isset($r['error'])){sendMessage($peer,'❌ Не удалось удалить сообщение.\nПричина: '.($r['error']['error_msg']??'ошибка VK API'));}else{sendMessage($peer,'🗑 Сообщение удалено.');}break;
 case 'gm':$t=$target??(int)($a[0]??0);$guard=manageTargetAllowed($p,$peer,$from,$t);if($guard){sendMessage($peer,$guard);break;}$p->prepare('UPDATE chat_users SET immunity=CASE WHEN immunity=1 THEN 0 ELSE 1 END WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);$q=$p->prepare('SELECT immunity FROM chat_users WHERE peer_id=? AND user_id=?');$q->execute([$peer,$t]);sendMessage($peer,((int)$q->fetchColumn()===1?'🛡 Иммунитет включён.':'🛡 Иммунитет снят.'));break;case'removegm':$t=$target??(int)($a[0]??0);$guard=manageTargetAllowed($p,$peer,$from,$t);if($guard){sendMessage($peer,$guard);break;}$p->prepare('UPDATE chat_users SET immunity=0 WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'🛡 Иммунитет снят.');break;case'gms':$q=$p->prepare('SELECT user_id FROM chat_users WHERE peer_id=? AND immunity=1');$q->execute([$peer]);$s='🛡 Иммунитет:\n';foreach($q as $r)$s.='• '.nameOf((int)$r['user_id'])."\n";sendMessage($peer,$s);break;
 case 'pin':$mid=(int)($o['reply_message']['conversation_message_id']??0);if(!$mid){sendMessage($peer,'📌 Ответьте на сообщение, которое нужно закрепить.');break;}$r=vk('messages.pin',['peer_id'=>$peer,'cmid'=>$mid]);sendMessage($peer,isset($r['response'])?'📌 Сообщение закреплено.':'❌ VK: '.($r['error']['error_msg']??'не удалось закрепить'));break;case'unpin':$r=vk('messages.unpin',['peer_id'=>$peer]);sendMessage($peer,isset($r['response'])?'📌 Сообщение откреплено.':'❌ VK: '.($r['error']['error_msg']??'не удалось открепить'));break;
 case 'admin':$t=$target??(int)($a[0]??0);if(!$t){sendMessage($peer,'Использование: !admin [ID/@тег]');break;}$guard=manageTargetAllowed($p,$peer,$from,$t);if($guard){sendMessage($peer,$guard);break;}if(level($p,$peer,$from)<=60&&!isSuper($from)){sendMessage($peer,'❌ Для назначения администратора нужен приоритет выше 60.');break;}$p->prepare('UPDATE chat_users SET role_id=4 WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessageKeyboard($peer,'👑 Администратор назначен: '.nameOf($t),roleButton($peer,$t,$from));break;case'gadmin':$t=$target??(int)($a[0]??0);if(!$t){sendMessage($peer,'Использование: !gadmin [ID/@тег]');break;}doGlobal($p,$peer,$from,$cmd,function(int $c)use($p,$t){$p->prepare('UPDATE chat_users SET role_id=4 WHERE peer_id=? AND user_id=?')->execute([$c,$t]);});sendMessage($peer,'🌐 Администратор назначен во всех беседах объединения.');break;
 case 'newrole':case'gnewrole':$pr=(int)($a[0]??0);$rn=trim(implode(' ',array_slice($a,1)));if($rn===''||$pr<0){sendMessage($peer,'Использование: !newrole [приоритет] [название]');break;}$p->prepare('INSERT INTO roles(name,priority) VALUES(?,?) ON DUPLICATE KEY UPDATE priority=VALUES(priority)')->execute([$rn,$pr]);sendMessage($peer,'✅ Роль создана/обновлена.');break;case'delrole':$pr=(int)($a[0]??-1);$p->prepare('DELETE FROM roles WHERE priority=? AND id>6')->execute([$pr]);sendMessage($peer,'✅ Роль удалена.');break;
 case 'welcome':$p->prepare('INSERT INTO chat_settings(peer_id,welcome) VALUES(?,?) ON DUPLICATE KEY UPDATE welcome=VALUES(welcome)')->execute([$peer,$argText]);sendMessage($peer,'✅ Приветствие сохранено.');break;case'setrules':$p->prepare('INSERT INTO chat_settings(peer_id,rules) VALUES(?,?) ON DUPLICATE KEY UPDATE rules=VALUES(rules)')->execute([$peer,$argText]);sendMessage($peer,'✅ Правила сохранены.');break;case'delrules':$p->prepare('UPDATE chat_settings SET rules=NULL WHERE peer_id=?')->execute([$peer]);sendMessage($peer,'✅ Правила удалены.');break;case'неактив':$days=(int)($a[0]??3);$q=$p->prepare("SELECT user_id,last_seen FROM chat_users WHERE peer_id=? AND last_seen<=? LIMIT 50");$q->execute([$peer,date('Y-m-d H:i:s',time()-$days*86400)]);$s="💤 Неактивные за {$days} дн.:\n";foreach($q as $r)$s.='• '.nameOf((int)$r['user_id']).' — '.$r['last_seen']."\n";sendMessage($peer,$s);break;
 case 'givemoney':$t=$target??0;$idx=$target?0:1;if(!$t){sendMessage($peer,'Использование: !givemoney [ID/@тег] [сумма] или ответом: !givemoney [сумма]');break;}$sum=amount($a[$idx]??'0');if($sum===0){sendMessage($peer,'❌ Сумма должна быть отлична от нуля.');break;}ensureEconomy($p,$peer,$t);$p->prepare('UPDATE economy SET balance=balance+? WHERE peer_id=? AND user_id=?')->execute([$sum,$peer,$t]);$action=$sum>0?'💰 Выдано ':'💸 Снято ';sendMessage($peer,$action.number_format(abs($sum),0,'.',' ').' ₽ '.($sum>0?'пользователю ':'с пользователя ').nameOf($t).'.');break;case'timeuved':$v=$a[0]??'0';$mins=(int)$v;if(str_contains(mb_strtolower($v),'ч'))$mins=(int)$v*60;$msg=trim(implode(' ',array_slice($a,1)));if($mins<=0||$msg===''){sendMessage($peer,'Использование: !timeuved 2 текст');break;}$next=date('Y-m-d H:i:s',time()+$mins*60);$p->prepare('INSERT INTO schedules(peer_id,owner_id,every_minutes,text,next_at) VALUES(?,?,?,?,?)')->execute([$peer,$from,$mins,$msg,$next]);sendMessage($peer,'⏰ Автоуведомление создано.');break;
 case 'settings':$q=$p->prepare('SELECT * FROM chat_settings WHERE peer_id=?');$q->execute([$peer]);$r=$q->fetch()?:[];sendMessage($peer,'⚙️ Настройки:\nGames: '.(!empty($r['games_enabled'])?'ON':'OFF')."\nAutoMod: ".(!empty($r['automod_enabled'])?'ON':'OFF')."\nMentions: ".(!empty($r['mentions_enabled'])?'ON':'OFF'));break;case'setup':$p->prepare('INSERT IGNORE INTO chat_settings(peer_id,rules,welcome,games_enabled,mentions_enabled) VALUES(?,\'Правила беседы ещё не настроены.\',\'Добро пожаловать в RAZE RUSSIA!\',0,1)')->execute([$peer]);sendMessage($peer,'✅ Первичная настройка выполнена.');break;case'games':$p->prepare('INSERT INTO chat_settings(peer_id,games_enabled) VALUES(?,1) ON DUPLICATE KEY UPDATE games_enabled=CASE WHEN games_enabled=1 THEN 0 ELSE 1 END')->execute([$peer]);$q=$p->prepare('SELECT games_enabled FROM chat_settings WHERE peer_id=?');$q->execute([$peer]);sendMessage($peer,'🎮 Игры: '.((int)$q->fetchColumn()?'включены':'выключены'));break;case'automod':$p->prepare('INSERT INTO chat_settings(peer_id,automod_enabled) VALUES(?,1) ON DUPLICATE KEY UPDATE automod_enabled=CASE WHEN automod_enabled=1 THEN 0 ELSE 1 END')->execute([$peer]);sendMessage($peer,'🛡 Автомод переключён.');break;
 case 'wipe':$p->prepare('DELETE FROM nicknames WHERE peer_id=?')->execute([$peer]);$p->prepare('UPDATE bans SET active=0 WHERE peer_id=?')->execute([$peer]);$p->prepare('UPDATE warnings SET active=0 WHERE peer_id=?')->execute([$peer]);sendMessage($peer,'🧹 Ники, баны и предупреждения сброшены.');break;case'sync':foreach(chatMembers($peer) as $m)if(isset($m['member_id']))ensureUser($p,$peer,(int)$m['member_id']);sendMessage($peer,'🔄 Участники синхронизированы.');break;case'owner':$t=(int)($a[0]??0);$p->prepare('UPDATE chat_users SET role_id=1 WHERE peer_id=? AND user_id!=? AND role_id=6')->execute([$peer,$t]);$p->prepare('UPDATE chat_users SET role_id=6 WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'👑 Владелец назначен.');break;case'spec':$t=(int)($a[0]??0);$p->prepare('UPDATE chat_users SET role_id=6 WHERE peer_id=? AND user_id=?')->execute([$peer,$t]);sendMessage($peer,'⭐ Главный администратор назначен.');break;case'gspec':$t=(int)($a[0]??0);if(!$t){sendMessage($peer,'Использование: !gspec [ID]');break;}doGlobal($p,$peer,$from,'gspec',function(int $c)use($p,$t){$p->prepare('UPDATE chat_users SET role_id=6 WHERE peer_id=? AND user_id=?')->execute([$c,$t]);});sendMessage($peer,'⭐ Главный администратор назначен во всех беседах объединения.');break;case'addws':$t=(int)($a[0]??0);$p->prepare('INSERT IGNORE INTO superusers(user_id) VALUES(?)')->execute([$t]);sendMessage($peer,'🛡 Супер-доступ выдан.');break;
 case 'unity':case 'createunity':
     if(!isSuper($from) && level($p,$peer,$from)<100){sendMessage($peer,'❌ Создать объединение может только владелец беседы.');break;}
     if($argText===''){ $uid=unityIdByPeer($p,$peer); if($uid){$u=unityInfo($p,$uid);sendMessage($peer,"🌐 Объединение #{$uid} «{$u['name']}».\n!unity [название] — создать\n!addunity [ID] — добавить беседу\n!removeunity — убрать беседу\n!editunity [название] — переименовать\n!unityinfo — информация");}else sendMessage($peer,'Использование: !unity [название]'); break; }
     if(unityIdByPeer($p,$peer)){sendMessage($peer,'❌ Эта беседа уже состоит в объединении.');break;}
     $name=mb_substr(trim($argText),0,191);$q=$p->prepare('SELECT id FROM unities WHERE name=? LIMIT 1');$q->execute([$name]);$u=(int)($q->fetchColumn()?:0);
     if($u){$info=unityInfo($p,$u);if((int)$info['owner_id']!==$from&&!isSuper($from)){sendMessage($peer,'❌ Объединение с таким названием уже существует.');break;}}
     else{$p->prepare('INSERT INTO unities(name,owner_id) VALUES(?,?)')->execute([$name,$from]);$u=(int)$p->lastInsertId();}
     $p->prepare('INSERT INTO unity_chats(unity_id,peer_id) VALUES(?,?)')->execute([$u,$peer]);sendMessage($peer,"🌐 Объединение «{$name}» создано. 🆔 #{$u}\n💬 Беседа добавлена.");break;
 case 'addunity':
     $u=(int)($a[0]??0);if(!$u){sendMessage($peer,'Использование: !addunity [ID объединения]');break;}$info=unityInfo($p,$u);if(!$info){sendMessage($peer,'❌ Объединение не найдено.');break;}if(unityIdByPeer($p,$peer)){sendMessage($peer,'❌ Эта беседа уже состоит в объединении.');break;}if((int)$info['owner_id']!==$from&&!isSuper($from)){sendMessage($peer,'❌ Добавлять беседы может только владелец объединения.');break;}$p->prepare('INSERT INTO unity_chats(unity_id,peer_id) VALUES(?,?)')->execute([$u,$peer]);sendMessage($peer,"✅ Беседа добавлена в «{$info['name']}» (#{$u}).");break;
 case 'removeunity':
     $u=unityIdByPeer($p,$peer);if(!$u){sendMessage($peer,'❌ Эта беседа не состоит в объединении.');break;}$info=unityInfo($p,$u);if((int)$info['owner_id']!==$from&&!isSuper($from)){sendMessage($peer,'❌ У вас нет прав удалить беседу из объединения.');break;}$p->prepare('DELETE FROM unity_chats WHERE peer_id=?')->execute([$peer]);sendMessage($peer,"🚪 Беседа удалена из «{$info['name']}».");break;
 case 'editunity':
     $u=unityIdByPeer($p,$peer);$name=mb_substr(trim($argText),0,191);if(!$u||$name===''){sendMessage($peer,'Использование: !editunity [новое название]');break;}$info=unityInfo($p,$u);if((int)$info['owner_id']!==$from&&!isSuper($from)){sendMessage($peer,'❌ Переименовать объединение может только владелец.');break;}$q=$p->prepare('SELECT id FROM unities WHERE name=? AND id<>?');$q->execute([$name,$u]);if($q->fetchColumn()){sendMessage($peer,'❌ Такое название уже занято.');break;}$p->prepare('UPDATE unities SET name=? WHERE id=?')->execute([$name,$u]);sendMessage($peer,"✏️ Объединение переименовано в «{$name}».");break;
 case 'listunities':
     $page=max(1,(int)($a[0]??1));$per=10;$off=($page-1)*$per;$total=(int)$p->query('SELECT COUNT(*) FROM unities')->fetchColumn();$q=$p->prepare('SELECT u.id,u.name,u.owner_id,COUNT(uc.peer_id) members FROM unities u LEFT JOIN unity_chats uc ON uc.unity_id=u.id GROUP BY u.id ORDER BY u.id DESC LIMIT '.$per.' OFFSET '.$off);$q->execute();$rows=$q->fetchAll();$s="🌐 Объединения — страница {$page}\n\n";foreach($rows as $r){$s.="#{$r['id']} «{$r['name']}» — 👑 {$r['owner_id']} — 💬 {$r['members']} бесед\n";}if(!$rows)$s.='Нет объединений.';else $s.="\n📄 Всего: {$total}";sendMessage($peer,$s);break;
 case 'unityinfo':
     $u=(int)($a[0]??0)?:unityIdByPeer($p,$peer);$info=unityInfo($p,$u);if(!$info){sendMessage($peer,'❌ Объединение не найдено.');break;}$q=$p->prepare('SELECT peer_id FROM unity_chats WHERE unity_id=? ORDER BY peer_id');$q->execute([$u]);$ch=$q->fetchAll(PDO::FETCH_COLUMN);$s="🌐 Объединение #{$u} «{$info['name']}»\n👑 Владелец: {$info['owner_id']}\n💬 Бесед: ".count($ch)."\n\n";foreach($ch as $i=>$c){ensureBotChat($p,(int)$c,true);$title=botChatName($p,(int)$c);$s.=($i+1).". {$title}".($c===$peer?' ← вы':'')."\n";}if((int)$info['owner_id']===$from||isSuper($from))$s.="\n⚙️ Управление:\n• !addunity {$u} — добавить текущую беседу\n• !removeunity — убрать текущую беседу\n• !editunity новое название\n• !deleteunity {$u} — удалить объединение";sendMessageKeyboard($peer,$s,unityKeyboard($u));break;
 case 'leaveunity':
     $u=unityIdByPeer($p,$peer);if(!$u){sendMessage($peer,'❌ Эта беседа не состоит в объединении.');break;}$info=unityInfo($p,$u);if((int)$info['owner_id']===$from&&!isSuper($from)){sendMessage($peer,'❌ Владелец не может выйти из объединения.');break;}$p->prepare('DELETE FROM unity_chats WHERE peer_id=?')->execute([$peer]);sendMessage($peer,"🚪 Беседа вышла из «{$info['name']}».");break;
 case 'deleteunity':
     $u=(int)($a[0]??0)?:unityIdByPeer($p,$peer);$info=unityInfo($p,$u);if(!$info){sendMessage($peer,'❌ Объединение не найдено.');break;}if((int)$info['owner_id']!==$from&&!isSuper($from)){sendMessage($peer,'❌ Удалить объединение может только владелец.');break;}$p->prepare('DELETE FROM unity_chats WHERE unity_id=?')->execute([$u]);$p->prepare('DELETE FROM unities WHERE id=?')->execute([$u]);sendMessage($peer,"🗑 Объединение «{$info['name']}» удалено.");break;
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
 case 'listen':$v=$a[0]??'';if(strtolower($v)==='stop'){$p->exec('DELETE FROM listenings');sendMessage($peer,'👂 Прослушки остановлены.');break;}$lp=(int)$v;if($lp){$p->prepare('INSERT INTO listenings(peer_id,owner_id,expires_at) VALUES(?,?,?) ON DUPLICATE KEY UPDATE owner_id=VALUES(owner_id),expires_at=VALUES(expires_at)')->execute([$lp,$from,date('Y-m-d H:i:s',time()+86400)]);sendMessage($peer,'👂 Прослушка включена на 24 часа.');}else sendMessage($peer,'Использование: !listen [peerId] или !listen stop');break;case'chatlist':$ids=$p->query('SELECT peer_id FROM bot_chats WHERE is_active=1 ORDER BY peer_id')->fetchAll(PDO::FETCH_COLUMN);$s='💬 Беседы, где установлен бот:\n\n';foreach($ids as $cid){ensureBotChat($p,(int)$cid,true);$s.='• '.botChatName($p,(int)$cid).'\n  🔗 '.botChatLink($p,(int)$cid).'\n';}if(!$ids)$s.='Нет зарегистрированных бесед.';sendMessage($peer,$s);break;case'userchats':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT DISTINCT peer_id FROM chat_users WHERE user_id=?');$q->execute([$t]);$s='💬 Беседы пользователя:\n';foreach($q as $r)$s.='• '.$r['peer_id']."\n";sendMessage($peer,$s);break;case'ahistory':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT peer_id,action,details,created_at FROM logs WHERE target_id=? AND action IN (\'warn\',\'ban\',\'mute\') ORDER BY id DESC LIMIT 30');$q->execute([$t]);$s='📜 Глобальная история:\n';foreach($q as $r)$s.='• '.$r['peer_id'].' '.$r['action'].' '.$r['details'].' '.$r['created_at']."\n";sendMessage($peer,$s);break;case'checkban':$t=$target??(int)($a[0]??0);$q=$p->prepare('SELECT peer_id,days,reason,expires_at FROM bans WHERE user_id=? AND active=1');$q->execute([$t]);$s='🔨 Активные блокировки:\n';foreach($q as $r)$s.='• '.$r['peer_id'].' — '.$r['days'].' дн. до '.$r['expires_at'].' — '.$r['reason']."\n";sendMessage($peer,$s);break;
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
    if(!is_array($payload)||!$uid){if($eventId)vk('messages.sendMessageEventAnswer',['event_id'=>$eventId,'user_id'=>$uid,'peer_id'=>$peer,'event_data'=>json_encode(['type'=>'show_snackbar','text'=>'Ошибка кнопки'],JSON_UNESCAPED_UNICODE)]);return;}
    $cmd=(string)($payload['cmd']??'');$rid=(int)($payload['id']??0);$actor=(int)($payload['actor']??0);$target=(int)($payload['target']??0);$answer=['type'=>'show_snackbar','text'=>'Готово'];
    if(in_array($cmd,['remove_role','remove_nick','casino_repeat'],true)){
      if($actor!==$uid){$answer=['type'=>'show_snackbar','text'=>'Кнопка доступна тому, кто выполнил действие'];goto event_answer;}
      if($cmd==='remove_role'){if(level($pdo,$peer,$uid)<40){$answer=['type'=>'show_snackbar','text'=>'Недостаточно прав'];goto event_answer;}$guard=manageTargetAllowed($pdo,$peer,$uid,$target);if($guard){$answer=['type'=>'show_snackbar','text'=>$guard];goto event_answer;}$pdo->prepare('UPDATE chat_users SET role_id=1 WHERE peer_id=? AND user_id=?')->execute([$peer,$target]);sendMessage($peer,'➖ Роль снята с '.nameOf($target).'.');$answer=['type'=>'show_snackbar','text'=>'Роль снята'];goto event_answer;}
      if($cmd==='remove_nick'){if(level($pdo,$peer,$uid)<20){$answer=['type'=>'show_snackbar','text'=>'Недостаточно прав'];goto event_answer;}$guard=manageTargetAllowed($pdo,$peer,$uid,$target);if($guard){$answer=['type'=>'show_snackbar','text'=>$guard];goto event_answer;}$pdo->prepare('DELETE FROM nicknames WHERE peer_id=? AND user_id=?')->execute([$peer,$target]);sendMessage($peer,'➖ Ник снят с '.nameOf($target).'.');$answer=['type'=>'show_snackbar','text'=>'Ник снят'];goto event_answer;}
      if($cmd==='casino_repeat'){ensureEconomy($pdo,$peer,$uid);$bet=(int)($payload['bet']??0);$q=$pdo->prepare('SELECT balance FROM economy WHERE peer_id=? AND user_id=?');$q->execute([$peer,$uid]);$bal=(int)$q->fetchColumn();if($bet<=0||$bet>$bal){sendMessage($peer,'🎰 Недостаточно средств. Ваш баланс: '.number_format($bal,0,'.',' '));$answer=['type'=>'show_snackbar','text'=>'Недостаточно средств'];goto event_answer;}$roll=random_int(1,100);$mult=$roll<=10?0:($roll<=55?1:($roll<=85?1.5:2.5));$delta=(int)round($bet*$mult)-$bet;$pdo->prepare('UPDATE economy SET balance=balance+?,last_casino=NOW() WHERE peer_id=? AND user_id=?')->execute([$delta,$peer,$uid]);sendMessageKeyboard($peer,'🎰 Результат: '.$mult.'×\n'.($delta>=0?'Вы выиграли ':'Вы проиграли ').number_format(abs($delta),0,'.',' ').' ₽',casinoButton($peer,$uid,$bet));$answer=['type'=>'show_snackbar','text'=>'Ставка повторена'];goto event_answer;}
    }
    if(in_array($cmd,['unity_refresh','unity_add','unity_remove','unity_leave','unity_delete'],true)){
      $u=(int)($payload['unity_id']??0); $info=unityInfo($pdo,$u);
      if(!$info){$answer=['type'=>'show_snackbar','text'=>'Объединение не найдено'];goto event_answer;}
      $isOwner=((int)$info['owner_id']===$uid)||isSuper($uid);
      if($cmd==='unity_refresh'){
        $q=$pdo->prepare('SELECT peer_id FROM unity_chats WHERE unity_id=? ORDER BY peer_id');$q->execute([$u]);$ch=$q->fetchAll(PDO::FETCH_COLUMN);$out="🌐 Объединение #{$u} «{$info['name']}»\n👑 Владелец: {$info['owner_id']}\n💬 Бесед: ".count($ch)."\n\n";foreach($ch as $i=>$c){ensureBotChat($pdo,(int)$c,true);$out.=($i+1).". ".botChatName($pdo,(int)$c).(((int)$c===$peer)?' ← вы':'')."\n";}sendMessageKeyboard($peer,$out,unityKeyboard($u));$answer=['type'=>'show_snackbar','text'=>'Обновлено'];goto event_answer;
      }
      if(!$isOwner && in_array($cmd,['unity_add','unity_remove','unity_delete'],true)){$answer=['type'=>'show_snackbar','text'=>'Только владелец объединения'];goto event_answer;}
      if($cmd==='unity_add'){if(unityIdByPeer($pdo,$peer)){$answer=['type'=>'show_snackbar','text'=>'Беседа уже состоит в объединении'];goto event_answer;}$pdo->prepare('INSERT IGNORE INTO unity_chats(unity_id,peer_id) VALUES(?,?)')->execute([$u,$peer]);sendMessage($peer,"✅ Беседа «".botChatName($pdo,$peer)."» добавлена в «{$info['name']}».");}
      elseif($cmd==='unity_remove'){if(unityIdByPeer($pdo,$peer)!==$u){$answer=['type'=>'show_snackbar','text'=>'Эта беседа не в данном объединении'];goto event_answer;}$pdo->prepare('DELETE FROM unity_chats WHERE unity_id=? AND peer_id=?')->execute([$u,$peer]);sendMessage($peer,"🚪 Беседа вышла из «{$info['name']}».");}
      elseif($cmd==='unity_leave'){if((int)$info['owner_id']===$uid){$answer=['type'=>'show_snackbar','text'=>'Владелец не может выйти'];goto event_answer;}if(unityIdByPeer($pdo,$peer)===$u)$pdo->prepare('DELETE FROM unity_chats WHERE unity_id=? AND peer_id=?')->execute([$u,$peer]);sendMessage($peer,"🚪 Беседа вышла из «{$info['name']}».");}
      elseif($cmd==='unity_delete'){$pdo->prepare('DELETE FROM unity_chats WHERE unity_id=?')->execute([$u]);$pdo->prepare('DELETE FROM unities WHERE id=?')->execute([$u]);sendMessage($peer,"🗑 Объединение «{$info['name']}» удалено.");}
      $answer=['type'=>'show_snackbar','text'=>'Готово'];goto event_answer;
    }
    if(!isSuper($uid)){if($eventId)vk('messages.sendMessageEventAnswer',['event_id'=>$eventId,'user_id'=>$uid,'peer_id'=>$peer,'event_data'=>json_encode(['type'=>'show_snackbar','text'=>'Нет доступа'],JSON_UNESCAPED_UNICODE)]);return;}
    
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
event_answer:
    if($eventId)vk('messages.sendMessageEventAnswer',['event_id'=>$eventId,'user_id'=>$uid,'peer_id'=>$peer,'event_data'=>json_encode($answer,JSON_UNESCAPED_UNICODE)]);
}

function lp():array{global $groupId;for($i=0;$i<5;$i++){$r=vk('groups.getLongPollServer',['group_id'=>$groupId]);if(isset($r['response']))return$r['response'];sleep(2);}throw new RuntimeException('Cannot get VK Long Poll server');}

botLog("MYSQL SCHEMA READY");botLog("RAZE RUSSIA VK BOT MYSQL started.");startupCheck();
while(true){try{$s=lp();$key=$s['key'];$server=$s['server'];$ts=$s['ts'];while(true){sendScheduled($pdo);$u=$server.'?act=a_check&key='.rawurlencode($key).'&wait=25&ts='.rawurlencode($ts);$c=stream_context_create(['http'=>['timeout'=>35,'ignore_errors'=>true]]);$r=@file_get_contents($u,false,$c);if($r===false)throw new RuntimeException('Long Poll connection failed');$d=json_decode($r,true);if(!is_array($d))throw new RuntimeException('Invalid Long Poll response');if(isset($d['ts']))$ts=$d['ts'];if(isset($d['failed']))break;foreach(($d['updates']??[])as$x){if(($x['type']??'')==='message_event'){handleMessageEvent($x);continue;}if(($x['type']??'')!=='message_new')continue;$o=$x['object']??[];if(isset($o['message'])&&is_array($o['message']))$o=$o['message'];handle($pdo,$o);}}}catch(Throwable$e){botLog('WARN: '.$e->getMessage());sleep(3);}}