FROM php:8.2-cli
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libsqlite3-dev \
        sqlite3 \
        pkg-config \
    && docker-php-ext-install pdo_sqlite \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY . /app
RUN mkdir -p /app/data && chmod -R 775 /app/data
CMD ["php","-d","display_errors=1","-d","error_reporting=E_ALL","/app/bot.php"]
