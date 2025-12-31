# WORKLOG

## 2025-12-31 16:28
- Amaç: AI auto-reply cevaplarýnýn JSON yerine duz metin olarak gonderilmesi.
- Sorun / Belirti: Responses API'den donen yapisal JSON metinleri kullaniciya ham olarak gorunuyordu.
- Kok Neden: AI cevabi normalize edilmeden MessageBuilder'a aktariliyordu.
- Yapilan Degisiklikler:
  - app/jobs/ai/respond_to_message_job.rb: JSON -> duz metin normalize helper ve hata logu eklendi.
  - app/models/message.rb: AI reply tetikleme hattinda mevcut davranis korunuyor.
- Calistirilan Komutlar: (yok)
- Dogrulama: (manuel) Widget'tan mesaj atinca JSON yerine duz metin gonderimi.
- Notlar / Riskler: Yok.
- Sonraki Adimlar: Gerekirse prompt formati ve usage loglari ile ek testler ekle.
