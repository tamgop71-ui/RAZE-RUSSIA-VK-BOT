<?php
declare(strict_types=1);

require_once __DIR__ . '/vendor/autoload.php';
require_once __DIR__ . '/src/Core.php';

use DigitalStars\SimpleVK\LongPoll;
use DigitalStars\SimpleVK\SimpleVK;

if (!class_exists(LongPoll::class)) {
    fwrite(STDERR, "ERROR: SimpleVK is not installed. Run composer install.\n");
    exit(1);
}

$simpleVk = SimpleVK::create($token, '5.199');
$vkLongPoll = LongPoll::create($token, '5.199');

fwrite(STDOUT, "=== RAZE RUSSIA BOT / SimpleVK 3 ===\n");
fwrite(STDOUT, "SimpleVK Long Poll transport enabled.\n");
startupCheck();

while (true) {
    try {
        $vkLongPoll->listen(function ($data) use ($pdo) {
            if (!is_array($data)) return;
            $type = $data['type'] ?? '';
            if ($type !== 'message_new') return;

            $o = $data['object'] ?? [];
            if (isset($o['message']) && is_array($o['message'])) {
                $o = $o['message'];
            }
            if (!is_array($o)) return;

            // SimpleVK supplies the raw VK event, so reply_message/conversation_message_id
            // remain available for moderation commands without using messages.send reply_to.
            handle($pdo, $o);
        });
    } catch (Throwable $e) {
        fwrite(STDERR, 'SimpleVK Long Poll ERROR: ' . $e->getMessage() . "\n");
        sleep(3);
    }
}
