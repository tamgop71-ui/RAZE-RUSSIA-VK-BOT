FROM php:8.2-cli
RUN docker-php-ext-install pdo_sqlite
WORKDIR /app
COPY . /app
RUN mkdir -p /app/data && chmod -R 775 /app/data
CMD ["php","-d","display_errors=1","-d","error_reporting=E_ALL","/app/bot.php"]
