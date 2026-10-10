FROM php:8.2-cli
ENV TZ=Europe/Moscow PHP_MEMORY_LIMIT=256M
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates tzdata libcurl4-openssl-dev libsqlite3-dev libonig-dev \
    && docker-php-ext-install pdo_sqlite curl mbstring \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . /app
RUN mkdir -p /app/data && chmod -R 775 /app/data
CMD ["php", "/app/bot.php"]
