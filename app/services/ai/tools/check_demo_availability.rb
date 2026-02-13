module Ai
  module Tools
    class CheckDemoAvailability < BaseTool
      def self.tool_name
        'check_demo_availability'
      end

      def self.tool_schema
        {
          type: 'function',
          name: tool_name,
          description: 'Check demo availability for a given date.',
          parameters: {
            type: 'object',
            properties: {
              date: { type: 'string', description: 'Date in YYYY-MM-DD' },
              tz: { type: 'string', description: 'IANA timezone' }
            },
            required: %w[date tz]
          },
          strict: true
        }
      end

      def self.required_params
        %w[date tz]
      end

      def self.param_types
        {
          'date' => String,
          'tz' => String
        }
      end

      def self.execute(account:, args:, **_context)
        zone = ActiveSupport::TimeZone[args['tz']] || Time.zone
        requested_date = parse_requested_date(args['date'], zone)
        return { error: 'validation_error', message: 'invalid_date', tool: tool_name } unless requested_date

        # TODO: Replace with real Google Calendar availability lookup.
        # If busy intervals are provided, filter slots with half-open overlap.
        busy = args['busy'].is_a?(Array) ? args['busy'] : []
        {
          status: 'ok',
          tool: tool_name,
          date: requested_date.strftime('%F'),
          timezone: zone.tzinfo.name,
          slots: filter_slots(
            slots: ['15:00-16:00', '16:00-17:00'],
            date: requested_date.strftime('%F'),
            zone: zone,
            busy: busy
          )
        }
      end

      def self.filter_slots(slots:, date:, zone:, busy:)
        return slots if busy.empty?

        slots.reject do |slot|
          slot_start, slot_end = parse_slot_range(date, zone, slot)
          next false unless slot_start && slot_end

          busy.any? do |item|
            event_start = parse_event_time(item['start_time'] || item['start'], zone)
            event_end = parse_event_time(item['end_time'] || item['end'], zone)
            next false unless event_start && event_end

            overlap?(slot_start, slot_end, event_start, event_end)
          end
        end
      end

      def self.parse_slot_range(date, zone, slot)
        range = slot.to_s.strip.gsub(/\u2013|\u2014/, '-').split('-', 2)
        return [nil, nil] if range.size != 2

        start_str = range[0].strip
        end_str = range[1].strip
        start_time = zone.parse("#{date} #{start_str}")
        end_time = zone.parse("#{date} #{end_str}")
        [start_time, end_time]
      rescue StandardError
        [nil, nil]
      end

      def self.parse_event_time(value, zone)
        return nil if value.blank?
        return Time.zone.parse(value) if value.include?('T')

        zone.parse(value.to_s)
      rescue StandardError
        nil
      end

      def self.overlap?(slot_start, slot_end, event_start, event_end)
        slot_start < event_end && slot_end > event_start
      end

      def self.parse_requested_date(value, zone)
        return nil if value.blank?

        parsed = zone.parse(value.to_s)
        parsed&.to_date
      rescue StandardError
        nil
      end
    end
  end
end
