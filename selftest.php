<?php
declare(strict_types=1);
$root=__DIR__;
$src=file_get_contents($root.'/bot.php');
if($src===false){fwrite(STDERR,"[FAIL] cannot read bot.php\n");exit(1);}
$fail=0;$pass=0;
function check(bool $ok,string $name):void{global $fail,$pass;if($ok){echo "[OK] {$name}\n";$pass++;}else{echo "[FAIL] {$name}\n";$fail++;}}
$lint=[];$code=0;exec('php -l '.escapeshellarg($root.'/bot.php').' 2>&1',$lint,$code);check($code===0,'PHP syntax');
check(str_contains($src,'v7.0.0'),'version banner');
check(str_contains(file_get_contents($root.'/Dockerfile')?:'','docker-php-ext-install pdo_mysql mbstring'),'Docker installs PDO MySQL and mbstring');
check(str_contains($src, "case'addws':") && str_contains($src, '$target??(int)($a[0]??$from)'), 'addws target/reply/author fallback');
check(str_contains($src, 'catch(Throwable $eventError)') && str_contains($src, 'EVENT ERROR:'), 'per-event exception guard');
check(strpos($src, "'reply_to'=>")===false && strpos($src, "'reply_to' =>")===false, 'messages.send does not use reply_to');
check(str_contains($src,"'inline'=>true"),'inline keyboards use boolean true');
check(str_contains($src,'CREATE TABLE IF NOT EXISTS reports'),'reports table exists');
check(str_contains($src,'CREATE TABLE IF NOT EXISTS report_messages'),'report history table exists');
check(str_contains($src,'CREATE TABLE IF NOT EXISTS superusers'),'superusers table exists');
check(str_contains($src,'CREATE TABLE IF NOT EXISTS sysbans'),'system bans table exists');
check(str_contains($src,'CREATE TABLE IF NOT EXISTS command_levels'),'command permission overrides table exists');
check(str_contains($src,'CREATE TABLE IF NOT EXISTS system_roles'),'global system roles table exists');
check(str_contains($src,'CREATE TABLE IF NOT EXISTS system_mutes'),'global system mutes table exists');
check(str_contains($src,"case 'sysmute':") && str_contains($src,"case 'sysunmute':") && str_contains($src,"case 'syskick':") && str_contains($src,"case 'sysstaff':"), 'super-system command handlers exist');
check(str_contains($src, "if(\$cmd==='sysrole'&&!isset(\$o['reply_message']['from_id'])&&count(\$a)===1&&is_numeric((string)\$a[0]))"), 'sysrole single priority targets author');
check(str_contains($src, "case 'editcmd':case'geditcmd':") && str_contains($src, "case 'gsettings':"), 'settings commands have implementations');
check(is_file($root.'/database.sql'),'database.sql exists');
check(is_file($root.'/Dockerfile'),'Dockerfile exists');
// Load only the pure parser function from bot.php to test command normalization without connecting to VK/MySQL.
if(!function_exists('mb_strtolower')) { function mb_strtolower($s,$encoding=null){ return strtr(strtolower((string)$s), ['А'=>'а','Б'=>'б','В'=>'в','Г'=>'г','Д'=>'д','Е'=>'е','Ё'=>'ё','Ж'=>'ж','З'=>'з','И'=>'и','Й'=>'й','К'=>'к','Л'=>'л','М'=>'м','Н'=>'н','О'=>'о','П'=>'п','Р'=>'р','С'=>'с','Т'=>'т','У'=>'у','Ф'=>'ф','Х'=>'х','Ц'=>'ц','Ч'=>'ч','Ш'=>'ш','Щ'=>'щ','Ъ'=>'ъ','Ы'=>'ы','Ь'=>'ь','Э'=>'э','Ю'=>'ю','Я'=>'я']); } }
if(preg_match('/function parseCommand\(string \$t\):array\{.*?\n\}\nfunction resolveUserToken/s',$src,$m)){
  $fn=preg_replace('/\nfunction resolveUserToken.*$/s','',$m[0]);
  try{eval($fn);$cases=[
    ['/help','команды'],['!!!help','команды'],['/ HELP','команды'],['/help@club241953865','команды'],['！help','команды'],['／help','команды'],['．help','команды'],["/he\u{200B}lp",'команды'],['/HELP','команды'],['/помощь','команды'],['!staff','staff'],['/addws','addws']
  ];
  foreach($cases as [$input,$expected]){[$got]=parseCommand($input);check($got===$expected,'parser '.json_encode($input,JSON_UNESCAPED_UNICODE).' => '.$expected);}
  }catch(Throwable $e){check(false,'parser test execution: '.$e->getMessage());}
}else{check(false,'parser function extraction');}
echo "RESULT: {$pass} passed, {$fail} failed\n";exit($fail?1:0);
