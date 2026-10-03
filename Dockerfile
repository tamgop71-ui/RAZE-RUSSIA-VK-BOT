FROM php:8.2-cli
RUN docker-php-ext-install pdo_sqlite
WORKDIR /app
COPY . /app
CMD ["php", "/app/bot.php"]
