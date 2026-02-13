require 'rails_helper'

RSpec.describe Ai::Tools::CheckDemoAvailability do
  let(:account) { create(:account) }

  it 'accepts requested date and returns availability' do
    result = described_class.call(
      account: account,
      args: {
        'date' => '2026-01-10',
        'tz' => 'Europe/Istanbul'
      }
    )

    expect(result[:status]).to eq('ok')
    expect(result[:date]).to eq('2026-01-10')
    expect(result[:slots]).to include('15:00-16:00', '16:00-17:00')
  end

  it 'treats adjacent slots as non-overlapping (half-open)' do
    zone = Time.find_zone('Europe/Istanbul')
    date = '2026-01-02'
    slot_start = zone.parse("#{date} 16:00")
    slot_end = zone.parse("#{date} 17:00")
    event_start = zone.parse("#{date} 15:00")
    event_end = zone.parse("#{date} 16:00")

    expect(described_class.overlap?(slot_start, slot_end, event_start, event_end)).to eq(false)
  end

  it 'keeps adjacent slot when busy event ends exactly at slot start' do
    result = described_class.call(
      account: account,
      args: {
        'date' => '2026-01-10',
        'tz' => 'Europe/Istanbul',
        'busy' => [
          {
            'start_time' => '2026-01-10T15:00:00+03:00',
            'end_time' => '2026-01-10T16:00:00+03:00'
          }
        ]
      }
    )

    expect(result[:status]).to eq('ok')
    expect(result[:slots]).not_to include('15:00-16:00')
    expect(result[:slots]).to include('16:00-17:00')
  end
end
