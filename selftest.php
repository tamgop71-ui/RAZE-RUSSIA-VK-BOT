<?php
$path=__DIR__.'/bot.php'; $s=file_get_contents($path); $ok=true;
function T($n,$v){global $ok; echo ($v?'[OK] ':'[FAIL] ').$n."\n"; if(!$v)$ok=false;}
T('PHP syntax', shell_exec('php -l '.escapeshellarg($path).' 2>&1') && str_contains((string)shell_exec('php -l '.escapeshellarg($path).' 2>&1'),'No syntax errors detected'));
T('v6 banner', str_contains($s,'v6.0.0'));
T('addws uses target fallback', str_contains($s,"case'addws':\$t=\$target"));
T('sysrole uses target fallback', str_contains($s,'$t=$target;')) ;
T('super priority', str_contains($s,'return max(priority($p,$peer,$uid),systemPriority($uid))'));
T('system target hierarchy', str_contains($s,'$tl=level($p,$peer,$target)'));
T('report create', str_contains($s,"case 'report':case'/report'"));
T('report reply', str_contains($s,"case 'reportmsg'"));
T('report close', str_contains($s,"case 'closereport'"));
T('report dialog', str_contains($s,"case'getdialog'"));
T('keyboard boolean true', str_contains($s,"'inline'=>true"));
T('no reply_to', !str_contains($s,"'reply_to'"));
T('target VK link', str_contains($s,'vk.com') && str_contains($s,'id(\\d+)'));
$req=preg_match('/\$req=\[(.*?)\];\n if\(!isset\(\$req/s',$s,$m)?$m[1]:''; preg_match_all("/'([^']+)'\s*=>\s*\[/",$req,$rm); preg_match_all("/case\s*'([^']+)'/",$s,$cm); $missing=array_diff($rm[1],$cm[1]); T('all permission commands have handlers',count($missing)===0); T('no duplicate case labels',count($cm[1])===count(array_unique($cm[1])));
exit($ok?0:1);
