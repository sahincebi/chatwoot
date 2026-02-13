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
        tomorrow = zone.today + 1
        return { error: 'date_not_allowed', message: 'only_tomorrow', tool: tool_name } if args['date'] != tomorrow.strftime('%F')

        # TODO: Replace with real Google Calendar availability lookup.
        # If busy intervals are provided, filter slots with half-open overlap.
        busy = args['busy'].is_a?(Array) ? args['busy'] : []
        {
          status: 'ok',
          tool: tool_name,
          date: args['date'],
          timezone: args['tz'],
          slots: filter_slots(
            slots: ['15:00-16:00', '16:00-17:00'],
            date: args['date'],
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
        range = slot.to_s.strip.tr('–—', '-').split('-', 2)
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
    end
  end
end
