<?php
// Запускайте по cron раз в минуту.
$config=require __DIR__.'/config.php';
$pdo=new PDO("mysql:host={$config['mysql']['host']};port={$config['mysql']['port']};dbname={$config['mysql']['database']};charset={$config['mysql']['charset']}",$config['mysql']['username'],$config['mysql']['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->exec("UPDATE bans SET active=0 WHERE active=1 AND expires_at IS NOT NULL AND expires_at<=NOW()");
$pdo->exec("UPDATE mutes SET active=0 WHERE active=1 AND expires_at IS NOT NULL AND expires_at<=NOW()");
