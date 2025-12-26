# RUNBOOK

## Ilk Kurulum
```sh
copy .env.example .env
docker compose up -d --build
```

## Fresh Start (Windows + Docker)
```sh
docker compose down -v
docker compose up -d --build
docker compose exec rails bundle exec rails db:chatwoot_prepare
docker compose exec rails bundle exec rails db:seed
```
Son olarak `http://localhost:3000` kontrol et.

## DB Hazirlama
```sh
docker compose exec rails bundle exec rails db:chatwoot_prepare
```

Alternatif:
```sh
docker compose exec rails bundle exec rails db:create
docker compose exec rails bundle exec rails db:migrate
docker compose exec rails bundle exec rails db:seed
```

## Gunluk Kullanim
```sh
docker compose logs -f rails
docker compose logs -f vite
docker compose logs -f sidekiq
docker compose restart rails
docker compose down
docker compose down -v
```

## Sorun Giderme Hizli Komutlar
```sh
docker ps
docker compose logs -f rails
docker compose logs -f vite
docker compose logs -f sidekiq
docker compose logs -f postgres
```
