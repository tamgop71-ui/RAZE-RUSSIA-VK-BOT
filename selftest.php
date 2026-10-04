<?php
declare(strict_types=1);
$bot=__DIR__.'/bot.php';
$src=file_get_contents($bot);
$ok=true;
function t(string $name,bool $pass):void{global $ok;echo ($pass?'[OK] ':'[FAIL] ').$name."\n";if(!$pass)$ok=false;}
t('bot.php exists',is_file($bot));
exec('php -l '.escapeshellarg($bot),$out,$code);t('PHP syntax', $code===0);
t('no keyboard parameter', preg_match('/[\"\']keyboard[\"\']\s*=>/i',$src)===0);
t('no reply_to parameter', preg_match('/[\"\']reply_to[\"\']/i',$src)===0);
$reqPart=substr($src,strpos($src,'$req=['),strpos($src,'if(!isset($req[$cmd]))')-strpos($src,'$req=['));
$req=array_unique(preg_match_all("/'([^']+)'\s*=>\s*\[/",$reqPart,$m)?$m[1]:[]);
$sw=substr($src,strpos($src,'switch($cmd)'));
$cases=preg_match_all("/case\\s*'([^']+)'/",$sw,$m2)?$m2[1]:[];
t('all permission entries have handlers',count(array_diff($req,$cases))===0);
$c=array_count_values($cases);t('no duplicate case labels',count(array_filter($c,fn($n)=>$n>1))===0);
t('database.sql exists',is_file(__DIR__.'/database.sql'));
$schema=file_get_contents(__DIR__.'/database.sql');
foreach(['roles','chat_users','chat_settings','warnings','bans','mutes','logs','nicknames','reports','economy','system_roles','system_bans','system_mutes'] as $table)t('schema table '.$table,strpos($schema,'CREATE TABLE IF NOT EXISTS `'.$table.'`')!==false || strpos($schema,'CREATE TABLE IF NOT EXISTS '.$table)!==false);
exit($ok?0:1);
