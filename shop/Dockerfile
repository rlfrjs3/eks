FROM php:8.2-apache

RUN docker-php-ext-install \
    mysqli \
    pdo \
    pdo_mysql

RUN a2enmod rewrite headers

COPY apache/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY php/custom.ini /usr/local/etc/php/conf.d/custom.ini

COPY app/ /var/www/html/

RUN chown -R www-data:www-data /var/www/html

WORKDIR /var/www/html

EXPOSE 80

CMD ["apache2-foreground"]
