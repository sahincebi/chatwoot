# TROUBLESHOOTING

## db:migrate aborts after migration due to annotate
Belirti: Migrasyon biterken annotate calisir ve `TypeError: no implicit conversion of Hash into String` ile rake abort eder.
Cozum:
- db task'lerde annotate skip edilir (lib/tasks/auto_annotate_models.rake).
- Gecici cozum: `SKIP_ANNOTATE=1` ile db task calistir.
Geri Alma:
- lib/tasks/auto_annotate_models.rake degisikliklerini geri al ve annotate'in db task'lerde calismasina izin ver.

## pre-commit fails: lint-staged missing
Belirti: `npx --no-install lint-staged` host'ta yoksa commit fail eder.
Cozum:
- `pnpm install` calistir ve node_modules/.bin/lint-staged olustur.
- Ya da hook lint-staged yoksa skip edecek sekilde ayarla.
Geri Alma:
- .husky/pre-commit degisikliklerini geri al ve lint-staged'i zorunlu kil.
