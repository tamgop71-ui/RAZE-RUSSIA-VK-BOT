<?php
// Включаем отображение ошибок только в лог, чтобы не ломать ответ для ВК
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('error_log', __DIR__ . '/bot_errors.log');

if (!file_exists(__DIR__ . '/config.php')) {
    error_log("КРИТИЧЕСКАЯ ОШИБКА: Файл config.php не найден! Переименуйте config.example.php или создайте новый.");
    die('ok'); // Возвращаем ok, чтобы ВК не спамил запросами
}

require_once __DIR__ . '/config.php';

// Получаем данные от ВКонтакте
$data = json_decode(file_get_contents('php://input'));
if (!$data) die('ok');

// Проверка секретного ключа
if (isset($data->secret) && VK_SECRET !== '' && $data->secret !== VK_SECRET) {
    error_log("ОШИБКА: Неверный секретный ключ.");
    die('ok');
}

// Подтверждение сервера
if ($data->type == 'confirmation') {
    die(VK_CONFIRM);
}

// Обработка входящего сообщения
if ($data->type == 'message_new') {
    $msg = $data->object->message;
    $peer_id = $msg->peer_id;
    $from_id = $msg->from_id;
    $text = mb_strtolower(trim($msg->text));

    // Инициализация PDO для работы с MySQL
    try {
        $pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    } catch (PDOException $e) {
        error_log("ОШИБКА БАЗЫ ДАННЫХ: " . $e->getMessage());
        vk_send($peer_id, "Технические неполадки с базой данных. Разработчик уже проверяет логи.");
        die('ok');
    }

    // Авторегистрация пользователя
    $stmt = $pdo->prepare("SELECT * FROM users WHERE vk_id = ?");
    $stmt->execute([$from_id]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$user) {
        $pdo->prepare("INSERT INTO users (vk_id) VALUES (?)")->execute([$from_id]);
        $stmt->execute([$from_id]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
    }

    $reply = "";
    $args = explode(' ', $text);
    $cmd = $args[0];

    // ======== ЛОГИКА БОТА ========
    
    // 1. Профиль
    if (in_array($cmd, ['профиль', 'статистика'])) {
        $reply = "👤 Твой профиль:\n"
               . "🆔 ID: {$user['id']}\n"
               . "👑 Роль: {$user['role']}\n"
               . "💰 Наличные: " . number_format($user['balance']) . " $\n"
               . "💳 В банке: " . number_format($user['bank']) . " $\n"
               . "🌟 Рейтинг: {$user['rating']}";
    } 
    // 2. Экономика: Казино
    elseif ($cmd == 'казино') {
        $bet = isset($args[1]) ? $args[1] : 0;
        if ($bet === 'все') $bet = $user['balance'];
        else $bet = (int)$bet;
        
        if ($bet <= 0 || $bet > $user['balance']) {
            $reply = "⚠ Неверная ставка! На твоем балансе: " . number_format($user['balance']) . " $";
        } else {
            $win = rand(1, 100) > 55; // 45% шанс победы
            if ($win) {
                $pdo->prepare("UPDATE users SET balance = balance + ? WHERE vk_id = ?")->execute([$bet, $from_id]);
                $reply = "🎰 Казино \n✅ Ты выиграл " . number_format($bet) . " $! \n💰 Баланс: " . number_format($user['balance'] + $bet) . " $";
            } else {
                $pdo->prepare("UPDATE users SET balance = balance - ? WHERE vk_id = ?")->execute([$bet, $from_id]);
                $reply = "🎰 Казино \n❌ Ты проиграл " . number_format($bet) . " $! \n💰 Баланс: " . number_format($user['balance'] - $bet) . " $";
            }
        }
    }
    // 3. Мини-игра Кубик
    elseif ($cmd == 'кубик') {
        $dice = rand(1, 6);
        $reply = "🎲 Бросаю кубик... Выпало число: {$dice}";
    }
    // 4. RP-команды
    elseif (in_array($cmd, ['обнять', 'ударить', 'поцеловать', 'убить', 'пожать'])) {
        $action = '';
        if ($cmd == 'обнять') $action = 'крепко обнял(а)';
        if ($cmd == 'ударить') $action = 'сильно ударил(а)';
        if ($cmd == 'поцеловать') $action = 'страстно поцеловал(а)';
        if ($cmd == 'убить') $action = 'жестоко убил(а)';
        if ($cmd == 'пожать') $action = 'пожал(а) руку';

        $reply = "✨ Ты {$action} этого пользователя!";
    } 
    // 5. Помощь
    elseif (in_array($cmd, ['помощь', 'команды', 'help'])) {
        $reply = "🤖 Доступные команды:\n"
               . "👤 Профиль — статистика аккаунта\n"
               . "🎰 Казино [ставка/все] — сыграть на деньги\n"
               . "🎲 Кубик — бросить игральный кубик\n"
               . "🎭 РП команды: обнять, ударить, поцеловать, убить, пожать";
    }

    if (!empty($reply)) {
        vk_send($peer_id, $reply);
    }
    
    die('ok');
}

function vk_send($peer_id, $message) {
    $url = 'https://api.vk.com/method/messages.send';
    $params = [
        'peer_id' => $peer_id,
        'message' => $message,
        'random_id' => rand(1, 999999999),
        'access_token' => VK_TOKEN,
        'v' => '5.131'
    ];
    $res = file_get_contents($url . '?' . http_build_query($params));
    // Логируем ошибки ВК API, если они есть
    $decoded = json_decode($res, true);
    if (isset($decoded['error'])) {
        error_log("VK API ERROR: " . print_r($decoded['error'], true));
    }
}
?>