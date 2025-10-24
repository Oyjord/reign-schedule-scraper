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

# --- Timezone setup ---
tz = TZInfo::Timezone.get('America/Los_Angeles')

# --- Build lookup: "Fri, Oct 24" => ISO8601 Pacific Time ---
lookup = {}
events.each do |event|
  date_str = event.dtstart.strftime("%a, %b %-d")  # Matches game["date"]

  # ✅ Preserve original local time and apply Pacific offset
  local_dt = event.dtstart.value  # Ruby DateTime with TZ-aware value
  local_time = Time.new(
    local_dt.year, local_dt.month, local_dt.day,
    local_dt.hour, local_dt.min, local_dt.sec,
    tz.period_for_local(local_dt).utc_total_offset
  )

  lookup[date_str] = local_time.iso8601
  puts "🧪 Event: #{event.summary}, Final: #{local_time.iso8601}"
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
