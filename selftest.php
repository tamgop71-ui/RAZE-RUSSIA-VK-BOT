<?php
declare(strict_types=1);
$bot=__DIR__.'/bot.php'; $ok=true; $src=is_file($bot)?file_get_contents($bot):'';
function t(string $name,bool $pass):void{global $ok;echo ($pass?'[OK] ':'[FAIL] ').$name."\n";if(!$pass)$ok=false;}
t('bot.php exists',is_file($bot));
exec('php -l '.escapeshellarg($bot),$out,$code);t('PHP syntax',$code===0);
t('MySQL driver check',strpos($src,"extension_loaded('pdo_mysql')")!==false);
t('no accidental SQLite driver dependency',strpos($src,"pdo_sqlite")===false);
t('help keyboard inline is boolean true',preg_match("/'inline'\\s*=>\\s*true/",$src)===1);
t('help article URL',strpos($src,'https://vk.ru/@-241953865-cmd')!==false);
t('no reply_to parameter',preg_match('/[\"\']reply_to[\"\']/i',$src)===0);
t('VK API version 5.199',strpos($src,"v']='5.199")!==false);
t('target has author fallback',strpos($src,'$defaultUid>0?$defaultUid:null')!==false);
t('target explicit detector exists',strpos($src,'function targetIsExplicit')!==false);
t('outgoing message cleaner exists',strpos($src,'function cleanOutgoing')!==false);
t('outgoing cleaner removes /n',strpos($src,'"/n"')!==false);
$reqPos=strpos($src,'$req=['); $swPos=strpos($src,'switch($cmd)');
$reqPart=$reqPos!==false&&$swPos!==false?substr($src,$reqPos,$swPos-$reqPos):'';
$req=preg_match_all("/'([^']+)'\\s*=>\\s*\\[/",$reqPart,$m)?array_values(array_unique($m[1])):[];
$sw=$swPos!==false?substr($src,$swPos):''; $cases=preg_match_all("/case\\s*'([^']+)'/",$sw,$m2)?$m2[1]:[];
t('all permission entries have handlers',count(array_diff($req,$cases))===0);
$c=array_count_values($cases);t('no duplicate case labels',count(array_filter($c,fn($n)=>$n>1))===0);
$schema=is_file(__DIR__.'/database.sql')?file_get_contents(__DIR__.'/database.sql'):'';
foreach(['roles','chat_users','chat_settings','warnings','bans','mutes','logs','nicknames','reports','report_messages','economy','marriages','countries','unities','unity_chats','superusers','system_roles','system_bans','system_mutes','schedules','listenings','bot_meta'] as $table)t('schema table '.$table,preg_match('/CREATE TABLE IF NOT EXISTS `?'.preg_quote($table,'/').'`?/',$schema)===1);
if(preg_match('/(function lowerText\(.*?\n\})\nfunction vk/s',$src,$m))eval($m[1]);
if(preg_match('/(function parseCommand\(.*?\n\})\nfunction target/s',$src,$m))eval($m[1]);
if(function_exists('parseCommand')){
 $tests=['!help','/help','.help','!!!help','/help@club241953865','!HELP','/помощь','/ПОМОЩЬ','/пинг',' .пинг ',"!help\u{200B}",'／help','！help','．help','/ help'];
 $want=['help','help','help','help','help','help','помощь','помощь','пинг','пинг','help','help','help','help','help'];
 foreach($tests as $i=>$input){[$cmd,$args]=parseCommand($input);t('parser '.json_encode($input,JSON_UNESCAPED_UNICODE),$cmd===$want[$i]);}
}else t('real command parser extracted',false);
if(preg_match('/(function target\(.*?\n\})\nfunction targetIsExplicit/s',$src,$m))eval($m[1]);
if(preg_match('/(function targetIsExplicit\(.*?\n\})\nfunction nameOf/s',$src,$m))eval($m[1]);
if(function_exists('target')){
 t('target reply wins',target(['reply_message'=>['from_id'=>222]],['111'],999)===222);
 t('target explicit ID',target([],['[id333|User]'],999)===333);
 t('target author fallback',target([],[],999)===999);
 t('target explicit detector reply',targetIsExplicit(['reply_message'=>['from_id'=>222]],[]));
 t('target explicit detector ID',targetIsExplicit([],['333']));
 t('target explicit detector fallback',!targetIsExplicit([],[]));
}
if(preg_match('/(function cleanOutgoing\(.*?\n\})\nfunction sendMessage/s',$src,$m))eval($m[1]);
if(function_exists('cleanOutgoing')){
 t('cleaner converts literal backslash-n',cleanOutgoing('A\\nB')==="A\nB");
 t('cleaner converts /n artifact',cleanOutgoing('A/nB')==="A\nB");
 t('cleaner strips excessive blank lines',cleanOutgoing("A\n\n\n\nB")==="A\n\nB");
}
if(preg_match('/(function nameOf\(.*?\n\})\nfunction targetName/s',$src,$m)){
 function vk(array|string $m,array $p=[]):array{return ['response'=>[['first_name'=>'Test','last_name'=>'User']]];}
 eval($m[1]);
 if(function_exists('nameOf'))t('nameOf generates clickable VK mention',nameOf(123)==='[id123|Test User]');
}
exit($ok?0:1);
