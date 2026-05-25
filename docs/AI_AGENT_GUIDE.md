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
- `ai_tool_policy` (jsonb, default `{limits, enabled, allowed_tools}`, null false) — tool yetkilendirme
- `openai_project_id` (string, nullable) — per-account OpenAI projesi

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
- `provider_cost_cents`, `billed_cost_cents`, `billing_multiplier` (decimal 8,4 default 1.0) — billing markup (×N)
- **UNIQUE index** `(account_id, message_id)` — idempotency garantisi (migration `20251231190000`)

**ai_payment_orders** (PayTR sipariş izleme — migration `20260217120000`)
- `account_id` (FK)
- `merchant_oid` (unique, PayTR sipariş kimliği)
- `amount_cents`, `currency`
- `status` (pending/paid/failed)
- `payment_amount_cents`, `payment_currency`, `fx_rate`
- `meta`

**ai_integrations** (Account bazlı 3. parti bağlantılar — migration `20260101004200`)
- Account başına Google Calendar vb. credential yönetimi (P1-3 randevu altyapısı)

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

### 1.4 HTTP endpoint'leri (özet)

**Account scope (`/api/v1/accounts/:id/...`)** — hepsi `ensure_admin!` (SuperAdmin veya account admin):

| Method | Yol | Controller | İş |
|---|---|---|---|
| GET | `/ai_settings` | `AiSettingsController#show` | AI ayarları + tool_policy + google_calendar entegrasyon durumu |
| PUT | `/ai_settings` | `AiSettingsController#update` | enabled / prompt_id / prompt_version / tool_policy güncelle |
| GET | `/ai_wallet` | `AiWalletsController#show` | balance + `low_balance` flag + threshold |
| GET | `/ai_wallet/transactions` | `AiWalletsController#transactions` | İşlem geçmişi (Kaminari pagination, `kind` filter) |
| GET | `/ai_wallet/usage_logs` | `AiWalletsController#usage_logs` | Kullanım kayıtları (date range filter, totals meta) |
| POST | `/ai_wallet/topup` | `AiWalletsController#topup` | **403** — PayTR akışı zorunlu (yukarıda P0-4 notu) |
| POST | `/ai_wallet/paytr_checkout` | `AiWalletsController#paytr_checkout` | PayTR token al, `checkout_url` döner |

**Public (PayTR webhook)** — `routes.rb:392`:

| Method | Yol | Controller | İş |
|---|---|---|---|
| POST | `/api/v1/payments/paytr/callback` | `PaytrCallbacksController#create` | PayTR'den gelen ödeme bildirimi |

Güvenlik:
- IP allowlist (`PAYTR_CALLBACK_IP_ALLOWLIST` ENV, boşsa devre dışı)
- HMAC-SHA256 imza doğrulaması (`paytr_service.rb:288-294`) — `ActiveSupport::SecurityUtils.secure_compare` ile timing-attack güvenli
- Hata kodları: 422 (payload bozuk), 401 (imza), 422 (config), 403 (IP), 500 (diğer)

**Super Admin (`/super_admin/...`)** — ayrı Devise scope:

| Method | Yol | İş |
|---|---|---|
| GET | `/ai_billings` | Tüm hesapların AI faturalandırma özeti, KPI |
| GET | `/ai_billings/:account_id` | Hesap detayı, transaction/usage geçmişi |
| POST | `/ai_billings/:account_id/topup` | Manuel topup (PayTR bypass — sadece super admin) |
| POST | `/ai_billings/update_pricing` | Fiyatlandırma config'i güncelle |

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

### 2.3 Idempotency (Aralık 2025 – Şubat 2026)
- [x] `ai_usage_logs` `(account_id, message_id)` unique index — migration `20251231190000`
- [x] `ai_transactions` PayTR partial unique index — migration `20260217153000`
- [x] `ai_payment_orders` tablosu (PayTR sipariş takibi) — migration `20260217120000`

### 2.4 Tool calling altyapısı (Ocak 2026)
- [x] `accounts.ai_tool_policy` kolonu (limits, enabled, allowed_tools) — migration `20260101004159`
- [x] `ai_integrations` tablosu (Google Calendar bağlantısı için) — migration `20260101004200`, fix `20260217180000`
- [x] Tool loop / tool registry kodlandı (WORKLOG ref: 2026-01-01)
  > Not: Tool seti kapsamı P1-1'de kod seviyesinde ayrıca doğrulanacak.

### 2.5 Billing markup ve Super Admin (Şubat 2026)
- [x] `ai_usage_logs` cost_breakdown kolonları (`provider_cost_cents`, `billed_cost_cents`, `billing_multiplier`) — migration `20260214021000`
- [x] PayTR servisi (token, callback, HMAC, idempotency) — `app/services/ai/payments/paytr_service.rb`
- [x] Super Admin AI Billing sayfası (`/super_admin/ai_billings`)
- [x] Per-account OpenAI projesi — migration `20260416120000`

### 2.6 Müşteri Billing UI (Mayıs 2026)
- [x] Bakiye gösterimi + PayTR top-up modal (`BillingIndex.vue`)
- [x] İşlem geçmişi sekmesi (`TransactionHistory.vue` + `GET /ai_wallet/transactions`)
- [x] Kullanım detayları sekmesi (`UsageLogs.vue` + `GET /ai_wallet/usage_logs`)
- [x] Düşük bakiye uyarı bannerı (`LowBalanceBanner.vue` + `AiWallet::LOW_BALANCE_THRESHOLD_CENTS`)
- [x] V3 (`ai.cebimedya.com`) ile PayTR pos paylaşımı — `merchant_oid` `AI*` prefix'li ödemeler V3 callback'inden `panel.cebimedya.com/api/v1/payments/paytr/callback`'e forward edilir

---

## 3) Yapılacaklar (Öncelikli / P0)

> P0 = Üretim güvenliği ve doğru para/usage takibi için şart.

### P0-1: **Idempotency / Double-charge & Double-reply koruması**
**Sorun:** Sidekiq retry veya race condition durumunda aynı message için ikinci kez debit/usage log yazılabilir.
- [x] DB unique index:
  - `ai_usage_logs` üzerinde `[:account_id, :message_id]` unique (migration `20251231190000_add_unique_index_to_ai_usage_logs.rb`)
- [x] Job başında dedupe (3 katman — `app/jobs/ai/respond_to_message_job.rb`):
  - **Katman 1 (satır 70):** `AiUsageLog.exists?(account_id:, message_id:)` ile erken return
  - **Katman 2 (satır 141):** wallet `with_lock` içinde tekrar kontrol (race condition)
  - **Katman 3 (satır 198):** `rescue ActiveRecord::RecordNotUnique` — DB index ihlali yakalanıyor
- [x] Transaction dedupe:
  - `ai_transactions` `(account_id, provider, provider_ref)` partial unique WHERE `provider='paytr'` (migration `20260217153000_add_unique_paytr_provider_ref_index_to_ai_transactions.rb`)

**Doğrulama:**
- Aynı message_id için job iki kez çalıştırılsa bile 1 kez debit olmalı.

---

### P0-2: **Yeni Account’ta wallet otomatik oluşturulsun**
Şu an wallet backfill var; yeni account’ta wallet yoksa AI tamamen skip ediyor.
- [x] `Account` modelinde callback (`app/models/account.rb` satır 131 + 233-241):
  - `after_create_commit :provision_ai_wallet`
  - `provision_ai_wallet` metodu: `AiWallet.find_or_create_by!(account_id: id)` + `RecordNotUnique` rescue

**Doğrulama:**
- Yeni account create → ai_wallet otomatik var.

---

### P0-3: **Admin API: Account AI Settings güncelleme (prompt_id/version, enable/disable)**
Süper admin çok sık değişiklik yapacak; restart yok → DB update yeterli.
- [x] API endpoint:
  - GET `/api/v1/accounts/:id/ai_settings`
  - PUT `/api/v1/accounts/:id/ai_settings`
- [x] GET payload alanları (`AiSettingsController#show`):
  - `ai_enabled`, `ai_prompt_id`, `ai_prompt_version`
  - `ai_tool_policy` (defaults ile birlikte) — tool yetkilendirme
  - `ai_integrations.google_calendar` (`enabled`, `has_refresh_token`, `calendar_id`, `timezone`)
- [x] PUT update edilebilir alanlar (strong params):
  - `ai_enabled`, `ai_prompt_id`, `ai_prompt_version`, `ai_tool_policy`
  - Validation: `ai_prompt_version >= 1`; tool_policy limit'leri (`max_tools_per_turn 1..10`, `max_total_steps 1..20`)
  - [ ] **Açık:** `openai_project_id` (Nisan 2026 kolonu) update edilebilir alanlarda **YOK** — Super Admin tarafına bırakılmış mı, unutuldu mu netleştirilmeli
- [x] AuthZ:
  - `before_action :ensure_admin!` → `SuperAdmin` veya `Current.account_user.administrator?`

**Doğrulama:**
- Version 3→4 update sonrası bir sonraki mesajda log’da `prompt_version=4` görülmeli.

---

### P0-4: **Wallet Top-up / Bakiye yönetimi (Admin)**
- [x] Top-up endpoint:
  - POST `/api/v1/accounts/:id/ai_wallet/topup` (amount_cents)
  - **Davranış değişti:** Endpoint **403 forbidden** döner (`manual topup is disabled; use paytr_checkout`). Bilinçli karar — para akışı PayTR'a zorlanmış (audit + idempotency için).
  - Account admin için: PayTR akışı zorunlu (`POST /api/v1/accounts/:id/ai_wallet/paytr_checkout`).
  - Super admin için: manuel topup hâlâ mümkün → `POST /super_admin/ai_billings/:account_id/topup` (`AiTransaction(kind: topup)` + wallet artırma).
- [x] UI: müşteri tarafı `BillingIndex.vue` (3 sekme: Genel Bakış / İşlemler / Kullanım) + `LowBalanceBanner` + PayTR top-up modal — commit `3e4770c48` (Mayıs 2026)

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
> **Altyapı TAMAM** — Loop + ToolRegistry + Policy üçü de çalışıyor (`app/jobs/ai/respond_to_message_job.rb` satır 345-540, `app/services/ai/tools/tool_registry.rb`). Eksik olan: e-ticaret tool seti.

- [x] OpenAI Responses tool loop:
  - `extract_tool_calls` hem `tool_call` hem `function_call` tipini destekliyor
  - `max_total_steps` ve `max_tools_per_turn` policy’den okunup limit uygulanıyor
  - Her tool turn’unda usage accumulation (cached_tokens dahil)
- Mevcut tool set (`app/services/ai/tools/`):
  - [x] `add_label_to_conversation`, `remove_label_from_conversation`
  - [x] `add_contact_note`, `add_private_note_to_conversation`
  - [x] `calendar_query_availability`, `calendar_create_event`
  - [x] `check_demo_availability`, `create_demo_appointment`, `send_demo_email`
  - [x] `close_conversation_log`
- Eksik tool set (P1-1’in **gerçek açık kısmı**):
  - [ ] `create_payment_link`
  - [ ] `get_shipment_status`
  - [ ] `search_products`
  - [ ] `create_order`
  - [ ] `get_order_status`
  - [ ] `create_refund_request`
- [x] Hesap bazlı tool yetkilendirme (policy):
  - `accounts.ai_tool_policy` jsonb (`allowed_tools`, `limits`, `enabled`)
  - `ToolRegistry.allowed_by_policy?` kontrolü her tool çağrısında çalışıyor
  - Yeni e-ticaret araçları geldiğinde policy katmanı **hazır**; sadece tool sınıfı + registry kaydı eklenecek.
- [x] Tool execution güvenliği:
  - Allowlist: policy üzerinden tool_name kontrolü
  - Schema normalize: `ToolRegistry.normalize_schema` ile JSON Schema validation
  - `tool_not_allowed`, `invalid_tool_schema` gibi hata kodları log’lanıyor

**Doğrulama:**
- AI “ürün ara” dediğinde tool çalışır, sonuçla final cevap üretir.

---

### P1-2: **Etiket, not ve müşteri profil yönetimi**
- [x] AI’nın:
  - [x] conversation label/tag ekleyebilmesi (`add_label_to_conversation`, `remove_label_from_conversation`)
  - [x] contact / conversation note ekleyebilmesi (`add_contact_note`, `add_private_note_to_conversation`)
  - [ ] lead stage alanlarını yazabilmesi (custom attributes) — **henüz tool yok**
- [ ] Audit trail:
  - bu aksiyonlar AI tarafından yapıldıysa meta’ya `by_ai_agent=true` — **doğrulanmadı, açık**

---

### P1-3: **Randevu modülü (Google Calendar) entegrasyonu**
- [x] Account bazlı calendar connection (credentials): `ai_integrations` tablosu + `app/controllers/api/v1/accounts/ai_integrations/google_calendar_controller.rb`
- [x] Uygunluk sorgusu + event yaratma + teyit mesajı:
  - `calendar_query_availability` (uygunluk sorgusu)
  - `calendar_create_event` (event yaratma)
  - Demo akışı: `check_demo_availability`, `create_demo_appointment`, `send_demo_email`
- [ ] Aynı conversation içinde “reschedule/cancel” akışları — **henüz tool yok**

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
