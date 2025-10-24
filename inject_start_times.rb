require 'open-uri'
require 'json'
require 'icalendar'
require 'tzinfo'

# --- Load reign_schedule.json ---
schedule_path = "reign_schedule.json"
schedule = JSON.parse(File.read(schedule_path))

# --- Parse .ics calendar ---
ics_url = "https://ontarioreign.com/calendar/schedule/"
ics_data = URI.open(ics_url).read
events = Icalendar::Calendar.parse(ics_data).first.events

# --- Timezone conversion setup ---
tz = TZInfo::Timezone.get('America/Los_Angeles')

# --- Build lookup: "Fri, Oct 31" => ISO8601 Pacific Time ---
lookup = {}
events.each do |event|
  date_str = event.dtstart.strftime("%a, %b %-d")  # Matches game["date"]

  # 🧪 Debug log to inspect timezone and ISO output
  puts "🧪 Event: #{event.summary}, DTSTART: #{event.dtstart}, Offset: #{event.dtstart.offset}, ISO: #{event.dtstart.iso8601}"

  lookup[date_str] = event.dtstart.iso8601  # ✅ Preserves -07:00 or -08:00 offset
end

# --- Inject scheduled_start into schedule ---
injected_count = 0
schedule.each do |game|
  if lookup[game["date"]]
    game["scheduled_start"] = lookup[game["date"]]
    injected_count += 1
  end
end

# --- Write updated schedule ---
File.write(schedule_path, JSON.pretty_generate(schedule))
puts "✅ Injected scheduled_start into #{injected_count} games"
