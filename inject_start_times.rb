require 'open-uri'
require 'json'
require 'icalendar'
require 'time'

# --- Load reign_schedule.json ---
schedule = JSON.parse(File.read("reign_schedule.json"))

# --- Parse .ics calendar ---
ics_url = "https://ontarioreign.com/calendar/schedule/"
ics_data = URI.open(ics_url).read
events = Icalendar::Calendar.parse(ics_data).first.events

# --- Build lookup: "Fri, Oct 31|San Jose" => ISO8601 time ---
lookup = {}
events.each do |event|
  date_str = event.start.strftime("%a, %b %-d") # e.g. "Fri, Oct 31"
  opponent = event.summary.split('@').last.strip rescue nil
  next unless opponent

  key = "#{date_str}|#{opponent}"
  lookup[key] = event.start.iso8601
end

# --- Inject scheduled_start into schedule ---
schedule.each do |game|
  key = "#{game["date"]}|#{game["opponent"]}"
  game["scheduled_start"] = lookup[key] if lookup[key]
end

# --- Write updated schedule ---
File.write("reign_schedule.json", JSON.pretty_generate(schedule))
puts "✅ Injected scheduled_start into #{schedule.count { |g| g["scheduled_start"] }} games"
