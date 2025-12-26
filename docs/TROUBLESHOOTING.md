# TROUBLESHOOTING

## "exec ... no such file or directory" (Windows CRLF)
Belirti: Docker entrypoint script'leri calismiyor, exec hatasi aliniyor.
Cozum:
- Script dosyalarini LF'ye cevir (CRLF -> LF).
- .gitattributes ile docker/entrypoints ve docker altindaki .sh/.rb icin eol=lf uygula.
- Entry point dosyalarinin executable oldugunu kontrol et.

## Postgres "password not specified"
Belirti: Postgres servisinden sifre hatasi gelir, container ayaga kalkmaz.
Cozum:
- .env icinde POSTGRES_PASSWORD degerini bos birakma.
- docker-compose.yaml icinde postgres servisi env_file .env kullansin.

## pg_isready "too many command-line arguments"
Belirti: Postgres readiness kontrolu hata verir.
Cozum:
- .env icinde POSTGRES_HOST ve POSTGRES_PORT degerlerini dogrula.
- Entry point script'lerinde pg_isready argumanlarinin dogru gectigini kontrol et.

## ActiveRecord::NoDatabaseError chatwoot_dev
Belirti: http://localhost:3000 acilinca DB hatasi gelir.
Cozum:
```sh
docker compose exec rails bundle exec rails db:create
docker compose exec rails bundle exec rails db:migrate
docker compose exec rails bundle exec rails db:seed
```
Alternatif:
```sh
docker compose exec rails bundle exec rails db:chatwoot_prepare
docker compose exec rails bundle exec rails db:seed
```

## bin/rails CRLF warning
Belirti: "shebang line ending with \r may cause problems" uyarisi gorunur.
Cozum:
- bin/rails dosyasini LF line ending'e cevir.

## bundler-audit missing
Belirti: `bundle exec rails` sirasinda `Could not find bundler-audit-0.9.1` hatasi.
Cozum:
- `docker compose exec rails bundle install` calistir.
- Gerekirse Gemfile.lock icindeki bundler-audit surumunu guncelle ve bundle install tekrar et.

## NameError: uninitialized constant Rack::File (mini-profiler)
Belirti: Loglarda mini-profiler isteklerinde `NameError: uninitialized constant Rack::File` gorunur.
Cozum Oncesi / Kok Neden: rack-mini-profiler 3.2.0 `Rack::File` kullaniyor; Rack 3.x'de sinif `Rack::Files` olarak degisti.
Cozum:
- `.env` veya `.env.example` icinde `DISABLE_MINI_PROFILER=true` ayarla ve container'i yeniden baslat.
- Alternatif: rack-mini-profiler'i Rack 3.x uyumlu surume guncelle.
