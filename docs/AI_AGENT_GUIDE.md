# AI Temsilci Platformu — Rehber ve Is Listesi (Chatwoot Fork)

Bu dokuman, Chatwoot fork’unda “AI musteri temsilcisi” mimarisinin mevcut durumunu, yapilacaklari ve gelistirme backlog’unu tek yerde toplar.
Amac: Codex ile adim adim ilerlerken, her degisikligin izini surmek ve “ne bitti / ne kaldi”yi net tutmak.

> Kural: Codex her task sonunda `docs/WORKLOG.md`’ye yeni bir kayit ekler (dosya/komut/dogrulama dahil).
> Kural: Bu dokumandaki checklist’ler task tamamlandikca guncellenir.

---

## 0) Hedef Kapsam

### Urun hedefi (ozet)
- Her Account icin 1 adet AI Temsilci (User) otomatik olusur.
- Her Account’un OpenAI tarafindaki prompt’u (prompt_id + version) ile yonetilir.
- Yeni sohbetler default olarak AI Temsilci’ye atanir.
- Insan temsilci sohbeti kendine atarsa AI devre disi kalir; tekrar AI Temsilci’ye atanirsa AI devam eder.
- Token kullanimi ve maliyet loglanir; bakiye (wallet) uzerinden dusulur.
- Super admin tek bir Account’un prompt version’ini sik sik gunceller; restart gerekmemelidir.

---

## 1) Mevcut Mimari (Repo’da Var Olan)

### 1.1 Veri modeli (DB)
**accounts**
- `ai_enabled` (boolean, default true, null false)
- `ai_prompt_id` (string)
- `ai_prompt_version` (integer, default 1, null false)
- `ai_agent_user_id` (bigint, FK users.id, indexed)

**users**
- `is_ai_agent` (boolean, default false, null false, indexed)

**ai_wallets**
- `account_id` (unique)
- `balance_cents` (>=0)
- `currency` (default USD)
- `status` (enum)

**ai_transactions**
- `account_id`
- `kind` (topup/debit/refund/adjustment)
- `amount_cents` (>0)
- `provider`, `provider_ref`, `meta`

**ai_usage_logs**
- `account_id`
- `conversation_id`, `message_id`
- `prompt_id`, `prompt_version`, `model`
- `input_tokens`, `output_tokens`, `total_tokens`
- `cost_cents`, `currency`, `meta`

### 1.2 Otomasyon akisi (olay bazli)
1) **Account create**
- `Account::ProvisionAiAgentJob` enqueue
- `Account::ProvisionAiAgentService` idempotent olarak AI user olusturur ve `accounts.ai_agent_user_id` set eder.

2) **Conversation create**
- `Conversation#assign_ai_agent` calisir:
  - assignee yoksa -> `assignee_id = account.ai_agent_user_id`

3) **Incoming Message create**
- `Message#enqueue_ai_reply`:
  - incoming + private degil + conversation.assignee.is_ai_agent? ise
  - `Ai::RespondToMessageJob.perform_later(message.id)`

4) **AI cevap**
- `Ai::RespondToMessageJob` gating:
  - conversation AI’ya atanmıs olmali
  - account.ai_enabled? true
  - ai_prompt_id dolu
  - ai_wallet var ve balance > 0
- OpenAI Responses API cagrisi:
  - endpoint: `AI_OPENAI_ENDPOINT` veya `OPENAI_BASE_URL` veya default `https://api.openai.com`
  - path: `/v1/responses`
  - payload:
    - `input`: (son 30 mesajdan context + latest message)
    - `prompt`: `{ id: ai_prompt_id, version: ai_prompt_version }`
    - opsiyonel `model`: ENV `AI_MODEL` varsa
- Usage -> cost hesaplanir (ENV rate’leriyle)
- Wallet’tan dusulur -> `AiTransaction(kind: debit)` + `AiUsageLog` yazilir
- Outgoing mesaj conversation’a AI user adina eklenir
- “JSON string donen cevap” normalize edilip plain text gonderilir (WORKLOG’de notlu)

### 1.3 Ilgili dosyalar (kisa referans)
- Migrations:
  - `db/migrate/20251231023000_add_ai_fields_to_accounts.rb`
  - `db/migrate/20251231023010_create_ai_wallets_transactions_usage_logs.rb`
  - `db/migrate/20251231030000_add_is_ai_agent_to_users.rb`
- Modeller:
  - `app/models/account.rb`
  - `app/models/ai_wallet.rb`, `app/models/ai_transaction.rb`, `app/models/ai_usage_log.rb`
- Provision:
  - `app/jobs/account/provision_ai_agent_job.rb`
  - `app/services/account/provision_ai_agent_service.rb`
- Atama:
  - `app/models/conversation.rb` (assign_ai_agent)
- Trigger + Job:
  - `app/models/message.rb` (enqueue_ai_reply)
  - `app/jobs/ai/respond_to_message_job.rb`
- Yardimci gating (var, kullanim dogrulanacak):
  - `lib/integrations/llm_base_service.rb` (ai_allowed?)

---

## 2) Yapilmislar (Checklist)

### 2.1 Core altyapi (DB + akis)
- [x] Account bazli AI alanlari eklendi (enabled, prompt_id, prompt_version, ai_agent_user_id)
- [x] AI wallet / transaction / usage logs tablolari eklendi
- [x] Users tablosuna `is_ai_agent` eklendi
- [x] Account create sonrasi AI Temsilci otomatik provision ediliyor
- [x] Yeni conversation default AI Temsilci’ye atanıyor
- [x] Incoming message sonrasi (AI’ya atanmis ise) AI cevap job’u tetikleniyor
- [x] OpenAI Responses API ile prompt id/version uzerinden cevap alinıyor
- [x] Token/cost hesap -> wallet debit -> transaction + usage log yazimi yapiliyor
- [x] AI cevabindaki JSON string normalize edilip plain text donuyor

### 2.2 Backfill script
- [x] Rake tasks:
  - `rake ai:backfill_wallets`
  - `rake ai:backfill_agents`

---

## 3) Yapilacaklar (Oncelikli / P0)

> P0 = Uretim guvenligi ve dogru para/usage takibi icin sart.

### P0-1: **Idempotency / Double-charge & Double-reply korumasi**
**Sorun:** Sidekiq retry veya race condition durumunda ayni message icin ikinci kez debit/usage log yazilabilir.
- [x] DB unique index:
  - `ai_usage_logs` uzerinde `[:account_id, :message_id]` unique
- [x] Job basinda dedupe:
  - ayni `(account_id, message_id)` usage log varsa return
- [x] Transaction dedupe:
  - `provider_ref` (response_id) ile gerekirse ekstra kontrol

**Dogrulama:**
- Ayni message_id icin job iki kez calistirilsa bile 1 kez debit olmali.

---

### P0-2: **Yeni Account’ta wallet otomatik olusturulsun**
Su an wallet backfill var; yeni account’ta wallet yoksa AI tamamen skip ediyor.
- [x] `Account::ProvisionAiAgentService` veya `Account` after_create_commit icinde:
  - `AiWallet.find_or_create_by!(account_id: account.id)`

**Dogrulama:**
- Yeni account create -> ai_wallet otomatik var.

---

### P0-3: **Admin API: Account AI Settings guncelleme (prompt_id/version, enable/disable)**
Super admin cok sik degisiklik yapacak; restart yok -> DB update yeterli.
- [ ] API endpoint:
  - GET `/api/v1/accounts/:id/ai_settings`
  - PUT `/api/v1/accounts/:id/ai_settings`
- [ ] Alanlar:
  - `ai_enabled`, `ai_prompt_id`, `ai_prompt_version`
  - (opsiyonel) `currency` / `wallet` goruntuleme (read)
- [ ] AuthZ:
  - sadece super admin veya account admin

**Dogrulama:**
- Version 3->4 update sonrasi bir sonraki mesajda log’da `prompt_version=4` gorunmeli.

---

### P0-4: **Wallet Top-up / Bakiye yonetimi (Admin)**
- [ ] Top-up endpoint:
  - POST `/api/v1/accounts/:id/ai_wallet/topup` (amount_cents)
  - `AiTransaction(kind: topup)` + wallet.balance_cents artir
- [ ] UI sonra; once API

**Dogrulama:**
- Topup sonrasi AI cevap verebilmeli.

---

### P0-5: **Observability / Debug standardi**
- [ ] `Ai::RespondToMessageJob` log formatini standardize et:
  - account, conversation, message, response_id, tokens, cost, balance_after, prompt_version
- [ ] Hata loglarinda openai body truncate + status zaten var; bunu koru.
- [ ] “skip reason”’lar sabit liste ve dokumante.

---

## 4) Yapilacaklar (Urun Ozellikleri / P1)

> P1 = “Satis yapabilen, randevu alabilen, not/etiket yonetebilen AI” icin sart.

### P1-1: **Tool-calling / Aksiyon yurutme dongusu**
Su an AI sadece text donuyor. Tool’lar calistirilmiyor.
- [ ] OpenAI Responses tool loop:
  - Response’da tool call varsa -> tool’u calistir -> sonucu tekrar modele ver -> final text al
- [ ] Minimum tool set (baslangic):
  - `search_products`
  - `create_order`
  - `get_order_status`
  - `create_refund_request`
  - `close_conversation`
  - (randevu icin) `calendar_query_availability`, `calendar_create_event` vb.
- [ ] Tool execution guvenligi:
  - allowlist tool isimleri
  - request validation (JSON schema)
  - timeout/retry policy

**Dogrulama:**
- AI “urun ara” dediginde tool calisir, sonucla final cevap uretir.

---

### P1-2: **Etiket, not ve musteri profil yonetimi**
- [ ] AI’nin:
  - conversation label/tag ekleyebilmesi
  - contact / conversation note ekleyebilmesi
  - lead stage alanlarini yazabilmesi (custom attributes)
- [ ] Audit trail:
  - bu aksiyonlar AI tarafindan yapildiysa meta’ya `by_ai_agent=true`

---

### P1-3: **Randevu modulu (Google Calendar) entegrasyonu**
- [ ] Account bazli calendar connection (credentials)
- [ ] Uygunluk sorgusu + event yaratma + teyit mesaji
- [ ] Ayni conversation icinde “reschedule/cancel” akislari

---

### P1-4: **Insan devralma UX’i (assignment semantics netlestirme)**
Mevcut yaklasim dogru: “assignee = AI -> AI aktif; assignee = human -> AI pasif”.
- [ ] UI/UX:
  - hizli “AI’ye devret” / “Ben devraliyorum” aksiyonlari
- [ ] Edge case:
  - “unassigned” olursa ne olacak? (oneri: unassigned -> AI degil)

---

## 5) Gelistirilecekler (Iyilestirmeler / P2-P3)

### P2-1: Maliyet hesaplamayi model bazli hale getirme
Su an ENV rate’leri global.
- [ ] Rate table (model -> input/output $/1M)
- [ ] (opsiyonel) account bazli override

### P2-2: Conversation context iyilestirme
Su an “plain text context”.
- [ ] Daha iyi prompt variables (structured)
- [ ] Daha uzun memory icin:
  - son N mesaj + onemli ozet + profile attributes

### P2-3: Performans ve kuyruk optimizasyonu
- [ ] Batching / debounce (15 sn buffer gibi)
- [ ] Rate limit + per-account concurrency
- [ ] Job timeout + circuit breaker

### P3-1: Dashboard metrikleri
- [ ] Gunluk/haftalik token, cost, bakiye grafikleri
- [ ] “AI resolved conversations”, “handover rate”, “conversion rate” gibi KPI’lar

---

## 6) Operasyon Notlari (Build/Assets)

Bazi UI degisiklikleri ancak asagidaki komutlardan sonra gorunuyorsa, prod-benzeri asset pipeline kullaniliyor olabilir:

```bash
docker compose exec -T rails bundle exec rails assets:clobber
docker compose exec -T rails bundle exec rails assets:precompile
docker compose restart rails sidekiq
```

Hedef: Dev ortaminda mumkunse HMR/Vite uzerinden calisip bu ihtiyaci azaltmak.
Ancak prod deployment’da precompile normaldir.

Codex Calisma Standardi
Her task icin beklenen cikti

Kod degisikligi

Minimum test/dogrulama komutu

docs/WORKLOG.md’ye yeni kayit:

Amac

Dosya bazli degisiklik listesi

Calistirilan komutlar

Dogrulama adimlari

Risk/Not

WORKLOG kayit sablonu

## YYYY-MM-DD HH:MM
- Tarih/Saat (TR): YYYY-MM-DD HH:MM
- Amac:
- Sorun / Belirti:
- Kok Neden (Varsa):
- Yapilan Degisiklikler (dosya bazli):
  - path/to/file
- Calistirilan Komutlar:
  - ...
- Dogrulama:
  - ...
- Notlar / Riskler:
  - ...
