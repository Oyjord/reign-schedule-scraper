
require 'open-uri'
require 'json'

FEED_URL = "https://lscluster.hockeytech.com/feed/index.php?feed=statviewfeed&view=schedule&team=403&season=90&month=-1&location=homeaway&key=ccb91f29d6744675&client_code=ahl&site_id=0&league_id=4&conference_id=-1&division_id=-1&lang=en&callback=angular.callbacks._0"

def fetch_schedule
  raw = URI.open(FEED_URL).read.strip

  # Debug: show first 100 chars of raw feed
  puts "🔍 Raw feed starts with: #{raw[0..100]}"

  # Step 1: Strip JSONP wrapper
  if raw.start_with?('angular.callbacks._0(')
    raw = raw.sub(/^angular\.callbacks\._0/, '').sub(/\s*$/, '')
  end

  # Step 2: Strip extra parentheses wrapper: ([ ... ])
  if raw.start_with?('([') && raw.end_with?('])')
    raw = raw[1..-2]
  end

  JSON.parse(raw)
end

def extract_reign_games(rows)
  rows.select do |row|
    r = row["row"]
    r["home_team_city"] == "Ontario" || r["visiting_team_city"] == "Ontario"
  end.map do |game|
    r = game["row"]
    p = game["prop"]
    {
      game_id: p["game_center"]["gameLink"].to_i,
      date: r["date"],
      opponent: r["home_team_city"] == "Ontario" ? r["visiting_team_city"] : r["home_team_city"],
      location: r["home_team_city"] == "Ontario" ? "Home" : "Away"
    }
  end
end

data = fetch_schedule
rows = data[0]["sections"][0]["data"]
reign_games = extract_reign_games(rows)

File.write("reign_game_ids.json", JSON.pretty_generate(reign_games))
puts "✅ Extracted #{reign_games.size} reign Rabbits games to reign_game_ids.json"
