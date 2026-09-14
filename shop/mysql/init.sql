CREATE DATABASE IF NOT EXISTS shoppingmall
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE shoppingmall;

CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(255),
    price INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO products (name, description, price)
VALUES
('AWS 클라우드 상품', 'AWS 기반 클라우드 서비스', 10000),
('Kubernetes 상품', 'Kubernetes 컨테이너 서비스', 20000),
('DevOps 상품', 'CI/CD 자동화 서비스', 30000),
('Monitoring 상품', 'Prometheus & Grafana 모니터링', 15000);
