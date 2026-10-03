FROM composer:2 AS composer

FROM php:8.2-cli

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libsqlite3-dev \
        sqlite3 \
        libcurl4-openssl-dev \
        libonig-dev \
        pkg-config \
    && docker-php-ext-install pdo_sqlite mbstring curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer /usr/bin/composer /usr/bin/composer

WORKDIR /app
COPY composer.json /app/composer.json
RUN composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader

COPY . /app
RUN mkdir -p /app/data && chmod -R 775 /app/data

CMD ["php", "-d", "display_errors=1", "-d", "error_reporting=E_ALL", "/app/bot.php"]
