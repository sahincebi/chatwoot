class AiDemoMailer < ApplicationMailer
  def demo_email(to_name:, to_email:, date:, time:, meet_link:)
    @to_name = to_name
    @date = date
    @time = time
    @meet_link = meet_link

    mail(
      to: to_email,
      subject: 'Demo Randevu Onayi',
      body: "Merhaba #{@to_name}, demo randevunuz #{date} #{time} icin olusturuldu. Baglanti: #{@meet_link}"
    )
  end
end
