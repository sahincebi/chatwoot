# WORKLOG

## Format
Tarih/Saat (TR):
Amac:
Sorun / Belirti:
Kok Neden (Varsa):
Yapilan Degisiklikler (dosya bazli):
Calistirilan Komutlar:
Dogrulama:
Notlar / Riskler:
Sonraki Adimlar:

## 27.12.2025 00:51 (TR)
Tarih/Saat (TR): 27.12.2025 00:51
Amac: Windows Docker dev akisini stabil hale getirip DB'yi hazirlamak ve teknik not altyapisini kurmak.
Sorun / Belirti: rails/vite entrypoint CRLF nedeniyle "exec ... no such file or directory"; Postgres init password/DB env uyumsuzluklari; pg_isready "too many command-line arguments"; ActiveRecord::NoDatabaseError chatwoot_dev.
Kok Neden (Varsa): Windows CRLF line ending'leri; eksik/yanlis env degerleri; acts-as-taggable-on cache API degisikligi; annotate task'i migration sonu YAML parse hatasi.
Yapilan Degisiklikler (dosya bazli): .gitattributes; docker/entrypoints/rails.sh; docker/entrypoints/vite.sh; docker/entrypoints/helpers/pg_database_url.rb; docker-compose.yaml; .env; db/migrate/20231211010807_add_cached_labels_list.rb; lib/tasks/auto_annotate_models.rake; db/schema.rb; docs/WORKLOG.md; docs/RUNBOOK.md; docs/TROUBLESHOOTING.md; docs/ADR/0001-dev-docker-windows.md.
Calistirilan Komutlar:
```sh
docker compose exec rails bundle exec rails db:create
docker compose exec rails bundle exec rails db:migrate
docker compose exec rails bundle exec rails db:migrate --trace
docker compose exec rails sh -c "SKIP_ANNOTATE=1 bundle exec rails db:migrate"
docker compose exec rails bundle exec rails db:seed
docker compose exec rails bundle exec ruby -e "require 'acts-as-taggable-on'; puts ActsAsTaggableOn::Taggable.constants.sort"
git status --short
git diff --stat
git diff .devcontainer/devcontainer.json
git diff Gemfile.lock
git restore .devcontainer/devcontainer.json Gemfile.lock
```
Dogrulama: db:create mevcut DB'leri onayladi; db:migrate (SKIP_ANNOTATE=1) tamamlandi; db:seed tamamlandi.
Notlar / Riskler: Gemfile.lock ve .devcontainer/devcontainer.json container kaynakli degisiklikleri incele/karar verilecek (gecici revert edildi); bin/rails CRLF warning devam edebilir (opsiyonel LF normalize).
Sonraki Adimlar: docker compose logs -f rails ile servis acilisini kontrol et; gerekirse bin/rails LF normalize et.

## 27.12.2025 01:07 (TR)
Tarih/Saat (TR): 27.12.2025 01:07
Amac: CRLF uyarilarini temizleyip repo genelinde LF politikasini netlestirmek ve bin/rails CRLF uyarisini kalici cozumlemek.
Sorun / Belirti: Git CRLF uyarilari; bin/rails shebang CRLF uyarisi.
Kok Neden (Varsa): Windows CRLF line ending'leri.
CRLF normalization + .gitattributes: Neden: Windows CRLF uyarilari; Dosyalar: bin/rails, db/migrate/20231211010807_add_cached_labels_list.rb, db/schema.rb, docker-compose.yaml, lib/tasks/auto_annotate_models.rake, .gitattributes; Dogrulama: docker compose exec rails bundle exec rails -v denemesinde CRLF uyarisi gorunmedi (komut bundler-audit eksikligi nedeniyle sonlandi).
Yapilan Degisiklikler (dosya bazli): bin/rails; db/migrate/20231211010807_add_cached_labels_list.rb; db/schema.rb; docker-compose.yaml; lib/tasks/auto_annotate_models.rake; .gitattributes; docs/WORKLOG.md.
Calistirilan Komutlar:
```sh
@'
from pathlib import Path

files = [
    Path('bin/rails'),
    Path('db/migrate/20231211010807_add_cached_labels_list.rb'),
    Path('db/schema.rb'),
    Path('docker-compose.yaml'),
    Path('lib/tasks/auto_annotate_models.rake'),
]

for path in files:
    data = path.read_bytes()
    normalized = data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
    if normalized != data:
        path.write_bytes(normalized)
'@ | python -

@'
from pathlib import Path

files = [
    Path('.gitattributes'),
    Path('docs/WORKLOG.md'),
    Path('docs/RUNBOOK.md'),
    Path('docs/TROUBLESHOOTING.md'),
    Path('docs/ADR/0001-dev-docker-windows.md'),
]

for path in files:
    data = path.read_bytes()
    normalized = data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
    if normalized != data:
        path.write_bytes(normalized)
'@ | python -

@'
from pathlib import Path

files = [
    Path('db/migrate/20231211010807_add_cached_labels_list.rb'),
    Path('lib/tasks/auto_annotate_models.rake'),
    Path('bin/rails'),
]

for path in files:
    data = path.read_bytes()
    print(path.as_posix(), b'\r\n' in data, b'\r' in data)
'@ | python -

git update-index --chmod=+x bin/rails
docker compose exec rails bundle exec rails -v
git status --short
git diff --stat
git add .
git diff --cached --name-only
```
Dogrulama: container icinde bin/rails calistirma denemesinde CRLF uyarisi gorunmedi; komut bundler-audit gemi eksik oldugu icin sonlandi.
Notlar / Riskler: CRLF uyarisi yok ama bundler icin eksik gem kurulumu gerekebilir.
Sonraki Adimlar: Gerekirse bundle install calistirip bin/rails tekrar dogrula.

## 27.12.2025 01:24 (TR)
Tarih/Saat (TR): 27.12.2025 01:24
Amac: bundle install ile bundler-audit eksigini gidermek, rails calistirma dogrulamasi yapmak, RUNBOOK/TROUBLESHOOTING guncellemek.
Sorun / Belirti: `bundle exec rails -v` sirasinda bundler-audit eksigi; CRLF warning dogrulamasi ihtiyaci.
Kok Neden (Varsa): Container icinde bundler-audit gemi yuklu degildi; Gemfile.lock 0.9.1 bekliyordu.
Yapilan Degisiklikler (dosya bazli): Gemfile.lock (bundler-audit 0.9.3); docs/TROUBLESHOOTING.md; docs/RUNBOOK.md; docs/WORKLOG.md.
Calistirilan Komutlar:
```sh
rg -n "bundler-audit" Gemfile Gemfile.lock
rg -n "bundler-audit" Gemfile.lock
docker compose exec rails bundle install
docker compose exec rails bundle exec rails -v
docker compose logs -f rails --tail 20
docker compose logs rails | rg -n "Listening on|listening on"
docker compose logs rails | rg -n "Puma|listening"
```
Dogrulama: `bundle exec rails -v` basarili; loglarda "* Listening on http://0.0.0.0:3000" goruldu; CRLF warning cikmadi.
Notlar / Riskler: logo*.svg degisiklikleri user change (Codex degil).
Sonraki Adimlar: Gerekirse Gemfile.lock bundler-audit surumu icin karar ver ve sabitle.

## 27.12.2025 01:51 (TR)
Tarih/Saat (TR): 27.12.2025 01:51
Amac: Rack::File NameError sorununu gidermek icin mini-profiler'i devde kapatmak ve entrypoint CRLF kalintilarini temizlemek.
Sorun / Belirti: Loglarda "NameError: uninitialized constant Rack::File"; entrypoint helper'da "env: can't execute 'ruby\r'".
Kok Neden (Varsa): rack-mini-profiler 3.2.0 Rack::File kullaniyor, Rack 3.x ile uyumsuz; docker/entrypoints/helpers/pg_database_url.rb CRLF line ending.
Yapilan Degisiklikler (dosya bazli): .env (DISABLE_MINI_PROFILER=true); .env.example; docker/entrypoints/rails.sh; docker/entrypoints/vite.sh; docker/entrypoints/helpers/pg_database_url.rb; docs/TROUBLESHOOTING.md; docs/WORKLOG.md.
Calistirilan Komutlar:
```sh
rg -n "mini-profiler|rack-mini-profiler|Rack::File" Gemfile Gemfile.lock config/initializers
Get-Content -Path config/initializers/rack_profiler.rb
rg -n "DISABLE_MINI_PROFILER" .env .env.example
python - (update DISABLE_MINI_PROFILER in .env)
docker compose up -d --force-recreate rails
docker compose exec rails printenv DISABLE_MINI_PROFILER
docker compose logs rails --since 5m | rg -n "Rack::File|mini-profiler"
docker compose logs rails --since 5m | rg -n "Listening on|Puma"
docker compose logs rails --since 10m | rg -n "Listening on"
docker compose logs rails --tail 50
python - (normalize docker/entrypoints/**/*.sh, docker/entrypoints/**/*.rb)
python - (CRLF check for docker/entrypoints/rails.sh, docker/entrypoints/vite.sh, docker/entrypoints/helpers/pg_database_url.rb)
docker compose restart rails
docker compose logs rails --tail 50
docker compose logs rails --tail 200 | rg -n "Rack::File|mini-profiler"
```
Dogrulama: DISABLE_MINI_PROFILER env set edildi; son loglarda Rack::File hatasi gorunmedi; Puma "Listening on http://0.0.0.0:3000" goruldu; entrypoint helper CRLF hatasi kayboldu.
Notlar / Riskler: logo*.svg degisiklikleri user change (Codex degil).
Sonraki Adimlar: mini-profiler gerekirse uyumlu surume guncelleme karari ver.

## 27.12.2025 02:13 (TR)
Tarih/Saat (TR): 27.12.2025 02:13
Amac: Rack::File NameError kaynagini netlestirip dev icin minimal cozum olarak mini-profiler'i kapali tutmak.
Sorun / Belirti: Rails loglarinda mini-profiler kaynakli `NameError: uninitialized constant Rack::File`.
Kok Neden (Varsa): rack-mini-profiler 3.2.0 `Rack::File` kullaniyor; Rack 3.x'de sinif `Rack::Files` olarak degisti.
Yapilan Degisiklikler (dosya bazli): docs/TROUBLESHOOTING.md; docs/WORKLOG.md.
Calistirilan Komutlar:
```sh
rg -n "DISABLE_MINI_PROFILER" .env .env.example
docker compose exec rails sh -c 'grep -R -n "Rack::File" /gems/ruby/3.4.0/gems/rack-mini-profiler-3.2.0/lib'
docker compose logs rails --tail 200 | rg -n "Rack::File|mini-profiler"
docker compose logs rails | rg -n "Listening on"
Get-Content -Path docs/TROUBLESHOOTING.md
```
Dogrulama: `Rack::File|mini-profiler` log satiri gorunmedi; Rails loglarinda `Listening on http://0.0.0.0:3000` bulundu.
Notlar / Riskler: mini-profiler devde kapali (DISABLE_MINI_PROFILER=true).
Sonraki Adimlar: Ihtiyac olursa rack-mini-profiler'i Rack 3.x uyumlu surume guncelle.
