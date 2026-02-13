require 'rails_helper'

RSpec.describe Ai::Tools::CheckDemoAvailability do
  it 'treats adjacent slots as non-overlapping (half-open)' do
    zone = Time.find_zone('Europe/Istanbul')
    date = '2026-01-02'
    slot_start = zone.parse("#{date} 16:00")
    slot_end = zone.parse("#{date} 17:00")
    event_start = zone.parse("#{date} 15:00")
    event_end = zone.parse("#{date} 16:00")

    expect(described_class.overlap?(slot_start, slot_end, event_start, event_end)).to eq(false)
  end
end
