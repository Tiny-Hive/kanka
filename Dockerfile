FROM node:22-alpine AS assets
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY vite.config.js tailwind.config.js ./
COPY resources/ resources/
COPY public/ public/
RUN yarn build

FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist --ignore-platform-reqs
COPY . .
RUN composer dump-autoload --optimize --no-dev

FROM php:8.4-fpm-alpine

RUN apk add --no-cache \
    nginx supervisor curl \
    libpng libjpeg-turbo freetype libwebp \
    libzip icu-libs oniguruma libxml2 \
    && apk add --no-cache --virtual .build-deps \
    libpng-dev libjpeg-turbo-dev freetype-dev libwebp-dev \
    libzip-dev icu-dev oniguruma-dev libxml2-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) \
    pdo_mysql gd zip intl mbstring xml bcmath opcache pcntl \
    && apk del .build-deps \
    && rm -rf /tmp/* /var/cache/apk/*

RUN { \
    echo 'opcache.memory_consumption=256'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=20000'; \
    echo 'opcache.validate_timestamps=0'; \
    echo 'opcache.enable_cli=1'; \
    } > /usr/local/etc/php/conf.d/opcache.ini \
    && { \
    echo 'upload_max_filesize=64M'; \
    echo 'post_max_size=64M'; \
    echo 'memory_limit=512M'; \
    echo 'max_execution_time=120'; \
    } > /usr/local/etc/php/conf.d/kanka.ini

COPY docker/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/php-fpm.conf /usr/local/etc/php-fpm.d/zz-kanka.conf

WORKDIR /var/www/html

COPY --from=vendor /app/vendor vendor
COPY . .
COPY --from=assets /app/public/build public/build

RUN chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
