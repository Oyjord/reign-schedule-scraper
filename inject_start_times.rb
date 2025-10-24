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

# --- Build lookup: "Fri, Oct 24" => ISO8601 Pacific Time ---
lookup = {}
events.each do |event|
  date_str = event.dtstart.strftime("%a, %b %-d")  # Matches game["date"]

  # Convert to UTC time first, then shift to Pacific-local
  utc_time = event.dtstart.to_time
  local = tz.utc_to_local(utc_time)
  lookup[date_str] = local.iso8601

  puts "🧪 Event: #{event.summary}, UTC: #{utc_time}, Pacific: #{local.iso8601}"
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

# --- Optional: Preview a few injected values
puts "🧾 Sample injected times:"
schedule.first(5).each do |game|
  puts "#{game['date']} → #{game['scheduled_start']}"
end
