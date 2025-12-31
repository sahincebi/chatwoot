# AI Temsilci Platformu — Rehber ve İş Listesi (Chatwoot Fork)

Bu doküman, Chatwoot fork’unda “AI müşteri temsilcisi” mimarisinin **mevcut durumunu**, **yapılacakları** ve **geliştirme backlog’unu** tek yerde toplar.
Amaç: Codex ile adım adım ilerlerken, her değişikliğin izini sürmek ve “ne bitti / ne kaldı”yı net tutmak.

> Kural: Codex her task sonunda `docs/WORKLOG.md`’ye **yeni bir kayıt** ekler (dosya/komut/doğrulama dahil).
> Kural: Bu dokümandaki checklist’ler task tamamlandıkça güncellenir.

---

## 0) Hedef Kapsam

### Ürün hedefi (özet)
- Her Account için **1 adet AI Temsilci** (User) otomatik oluşur.
- Her Account’un OpenAI tarafındaki prompt’u **(prompt_id + version)** ile yönetilir.
- Yeni sohbetler default olarak **AI Temsilci’ye atanır**.
- İnsan temsilci sohbeti kendine atarsa **AI devre dışı kalır**; tekrar AI Temsilci’ye atanırsa **AI devam eder**.
- Token kullanımı ve maliyet **loglanır**; bakiye (wallet) üzerinden **düşülür**.
- Süper admin tek bir Account’un prompt version’ını sık sık günceller; **restart gerekmemelidir**.

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

### 1.2 Otomasyon akışı (olay bazlı)
1) **Account create**
- `Account::ProvisionAiAgentJob` enqueue
- `Account::ProvisionAiAgentService` idempotent olarak AI user oluşturur ve `accounts.ai_agent_user_id` set eder.

2) **Conversation create**
- `Conversation#assign_ai_agent` çalışır:
  - assignee yoksa → `assignee_id = account.ai_agent_user_id`

3) **Incoming Message create**
- `Message#enqueue_ai_reply`:
  - incoming + private değil + conversation.assignee.is_ai_agent? ise
  - `Ai::RespondToMessageJob.perform_later(message.id)`

4) **AI cevap**
- `Ai::RespondToMessageJob` gating:
  - conversation **AI’ya atanmış olmalı**
  - account.ai_enabled? true
  - ai_prompt_id dolu
  - ai_wallet var ve balance > 0
- OpenAI Responses API çağrısı:
  - endpoint: `AI_OPENAI_ENDPOINT` veya `OPENAI_BASE_URL` veya default `https://api.openai.com`
  - path: `/v1/responses`
  - payload:
    - `input`: (son 30 mesajdan context + latest message)
    - `prompt`: `{ id: ai_prompt_id, version: ai_prompt_version }`
    - opsiyonel `model`: ENV `AI_MODEL` varsa
- Usage → cost hesaplanır (ENV rate’leriyle)
- Wallet’tan düşülür → `AiTransaction(kind: debit)` + `AiUsageLog` yazılır
- Outgoing mesaj conversation’a AI user adına eklenir
- “JSON string dönen cevap” normalize edilip plain text gönderilir (WORKLOG’de notlu)

### 1.3 İlgili dosyalar (kısa referans)
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
- Yardımcı gating (var, kullanım doğrulanacak):
  - `lib/integrations/llm_base_service.rb` (ai_allowed?)

---

## 2) Yapılmışlar (Checklist)

### 2.1 Core altyapı (DB + akış)
- [x] Account bazlı AI alanları eklendi (enabled, prompt_id, prompt_version, ai_agent_user_id)
- [x] AI wallet / transaction / usage logs tabloları eklendi
- [x] Users tablosuna `is_ai_agent` eklendi
- [x] Account create sonrası AI Temsilci otomatik provision ediliyor
- [x] Yeni conversation default AI Temsilci’ye atanıyor
- [x] Incoming message sonrası (AI’ya atanmışsa) AI cevap job’u tetikleniyor
- [x] OpenAI Responses API ile prompt id/version üzerinden cevap alınıyor
- [x] Token/cost hesap → wallet debit → transaction + usage log yazımı yapılıyor
- [x] AI cevabındaki JSON string normalize edilip plain text dönüyor

### 2.2 Backfill script
- [x] Rake tasks:
  - `rake ai:backfill_wallets`
  - `rake ai:backfill_agents`

---

## 3) Yapılacaklar (Öncelikli / P0)

> P0 = Üretim güvenliği ve doğru para/usage takibi için şart.

### P0-1: **Idempotency / Double-charge & Double-reply koruması**
**Sorun:** Sidekiq retry veya race condition durumunda aynı message için ikinci kez debit/usage log yazılabilir.
- [ ] DB unique index:
  - `ai_usage_logs` üzerinde `[:account_id, :message_id]` unique
- [ ] Job başında dedupe:
  - aynı `(account_id, message_id)` usage log varsa **return**
- [ ] Transaction dedupe:
  - `provider_ref` (response_id) ile gerekirse ekstra kontrol

**Doğrulama:**
- Aynı message_id için job iki kez çalıştırılsa bile 1 kez debit olmalı.

---

### P0-2: **Yeni Account’ta wallet otomatik oluşturulsun**
Şu an wallet backfill var; yeni account’ta wallet yoksa AI tamamen skip ediyor.
- [ ] `Account::ProvisionAiAgentService` veya `Account` after_create_commit içinde:
  - `AiWallet.find_or_create_by!(account_id: account.id)`

**Doğrulama:**
- Yeni account create → ai_wallet otomatik var.

---

### P0-3: **Admin API: Account AI Settings güncelleme (prompt_id/version, enable/disable)**
Süper admin çok sık değişiklik yapacak; restart yok → DB update yeterli.
- [x] API endpoint:
  - GET `/api/v1/accounts/:id/ai_settings`
  - PUT `/api/v1/accounts/:id/ai_settings`
- [x] Alanlar:
  - `ai_enabled`, `ai_prompt_id`, `ai_prompt_version`
  - (opsiyonel) `currency` / `wallet` görüntüleme (read)
- [x] AuthZ:
  - sadece super admin veya account admin

**Doğrulama:**
- Version 3→4 update sonrası bir sonraki mesajda log’da `prompt_version=4` görülmeli.

---

### P0-4: **Wallet Top-up / Bakiye yönetimi (Admin)**
- [x] Top-up endpoint:
  - POST `/api/v1/accounts/:id/ai_wallet/topup` (amount_cents)
  - `AiTransaction(kind: topup)` + wallet.balance_cents artır
- [ ] UI sonra; önce API

**Doğrulama:**
- Topup sonrası AI cevap verebilmeli.

---

### P0-5: **Observability / Debug standardı**
- [ ] `Ai::RespondToMessageJob` log formatını standardize et:
  - account, conversation, message, response_id, tokens, cost, balance_after, prompt_version
- [ ] Hata loglarında openai body truncate + status zaten var; bunu koru.
- [ ] “skip reason”’lar sabit liste ve dokümante.

---

## 4) Yapılacaklar (Ürün Özellikleri / P1)

> P1 = “Satış yapabilen, randevu alabilen, not/etiket yönetebilen AI” için şart.

### P1-1: **Tool-calling / Aksiyon yürütme döngüsü**
Şu an AI sadece text dönüyor. Tool’lar çalıştırılmıyor.
- [ ] OpenAI Responses tool loop:
  - Response’da tool call varsa → tool’u çalıştır → sonucu tekrar modele ver → final text al
- [ ] Minimum tool set (başlangıç):
  - `search_products`
  - `create_order`
  - `get_order_status`
  - `create_refund_request`
  - `close_conversation`
  - (randevu için) `calendar_query_availability`, `calendar_create_event` vb.
- [ ] Tool execution güvenliği:
  - allowlist tool isimleri
  - request validation (JSON schema)
  - timeout/retry policy

**Doğrulama:**
- AI “ürün ara” dediğinde tool çalışır, sonuçla final cevap üretir.

---

### P1-2: **Etiket, not ve müşteri profil yönetimi**
- [ ] AI’nın:
  - conversation label/tag ekleyebilmesi
  - contact / conversation note ekleyebilmesi
  - lead stage alanlarını yazabilmesi (custom attributes)
- [ ] Audit trail:
  - bu aksiyonlar AI tarafından yapıldıysa meta’ya `by_ai_agent=true`

---

### P1-3: **Randevu modülü (Google Calendar) entegrasyonu**
- [ ] Account bazlı calendar connection (credentials)
- [ ] Uygunluk sorgusu + event yaratma + teyit mesajı
- [ ] Aynı conversation içinde “reschedule/cancel” akışları

---

### P1-4: **İnsan devralma UX’i (assignment semantics netleştirme)**
Mevcut yaklaşım doğru: “assignee = AI → AI aktif; assignee = human → AI pasif”.
- [ ] UI/UX:
  - hızlı “AI’ye devret” / “Ben devralıyorum” aksiyonları
- [ ] Edge case:
  - “unassigned” olursa ne olacak? (öneri: unassigned → AI değil)

---

## 5) Geliştirilecekler (İyileştirmeler / P2-P3)

### P2-1: Maliyet hesaplamayı model bazlı hale getirme
Şu an ENV rate’leri global.
- [ ] Rate table (model → input/output $/1M)
- [ ] (opsiyonel) account bazlı override

### P2-2: Conversation context iyileştirme
Şu an “plain text context”.
- [ ] Daha iyi prompt variables (structured)
- [ ] Daha uzun memory için:
  - son N mesaj + önemli özet + profile attributes

### P2-3: Performans ve kuyruk optimizasyonu
- [ ] Batching / debounce (15 sn buffer gibi)
- [ ] Rate limit + per-account concurrency
- [ ] Job timeout + circuit breaker

### P3-1: Dashboard metrikleri
- [ ] Günlük/haftalık token, cost, bakiye grafikleri
- [ ] “AI resolved conversations”, “handover rate”, “conversion rate” gibi KPI’lar

---

## 6) Operasyon Notları (Build/Assets)

Bazı UI değişiklikleri ancak aşağıdaki komutlardan sonra görünüyorsa, prod-benzeri asset pipeline kullanılıyor olabilir:

```bash
docker compose exec -T rails bundle exec rails assets:clobber
docker compose exec -T rails bundle exec rails assets:precompile
docker compose restart rails sidekiq
```

Hedef: Dev ortamında mümkünse HMR/Vite üzerinden çalışıp bu ihtiyacı azaltmak.
Ancak prod deployment’da precompile normaldir.

Codex Çalışma Standardı
Her task için beklenen çıktı

Kod değişikliği

Minimum test/doğrulama komutu

docs/WORKLOG.md’ye yeni kayıt:

Amaç

Dosya bazlı değişiklik listesi

Çalıştırılan komutlar

Doğrulama adımları

Risk/Not

WORKLOG kayıt şablonu

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
