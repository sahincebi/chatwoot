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

## 27.12.2025 04:39 (TR)
Tarih/Saat (TR): 27.12.2025 04:39
Amac: Docker-only Windows dev akisinda db task'leri ve commit hook'lari stabil calissin.
Sorun / Belirti: db:migrate annotate sonrasinda abort oluyor; lint-staged host'ta yoksa pre-commit fail ediyor.
Kok Neden (Varsa): annotate hook db task'lerde calisip hata veriyor; lint-staged host node_modules gerektiriyor.
Yapilan Degisiklikler (dosya bazli): lib/tasks/auto_annotate_models.rake; .husky/pre-commit; docs/WORKLOG.md;
docs/TROUBLESHOOTING.md.
Calistirilan Komutlar:
```sh
Get-Content -Path lib/tasks/auto_annotate_models.rake
Get-Content -Path .husky/pre-commit
docker compose exec rails bundle install
docker compose exec rails bundle exec rails db:migrate
```
Dogrulama: docker compose exec rails bundle exec rails db:migrate (exit 0, annotate calismadi).
Notlar / Riskler: Neden: Docker-only akista host node_modules yokken hook'lar fail ediyordu.
Geri Alma: lib/tasks/auto_annotate_models.rake ve .husky/pre-commit degisikliklerini geri al.
Sonraki Adimlar: Gerekirse db:seed calistir.
