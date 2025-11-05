# enrich_game.rb
require 'open-uri'
require 'nokogiri'
require 'json'
require 'time'
require 'icalendar'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=ahl&game_id="

def fetch_ics_events
  url = "https://ontarioreign.com/calendar/schedule/"
  data = URI.open(url).read
  Icalendar::Calendar.parse(data).first.events
rescue => e
  warn "⚠️ Failed to fetch .ics calendar: #{e}"
  []
end

def match_ics_start(game, events)
  return nil unless game && game["date"] && game["opponent"]

  begin
    game_date = Date.parse(game["date"].gsub('.', '').strip)
  rescue
    return nil
  end

  events.find do |event|
    event.start.to_date == game_date &&
    event.summary.downcase.include?(game["opponent"].downcase)
  end&.start
end

def parse_game_sheet(game_id, game = nil)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc  = Nokogiri::HTML(html)

  # ---------- SCORING table ----------
  scoring_table = doc.css('table').find { |t| t.text.include?('SCORING') }
  unless scoring_table
    return {
      "game_id" => game_id.to_i,
      "date" => game["date"],
      "opponent" => game["opponent"],
      "location" => game["location"],
      "status" => "Upcoming",
      "home_score" => 0,
      "away_score" => 0,
      "home_goals" => [],
      "away_goals" => [],
      "overtime_type" => nil,
      "result" => nil,
      "game_report_url" => url
 # --  "scheduled_start" => game["scheduled_start"] || match_ics_start(game, fetch_ics_events)&.iso8601
    }
  end

  rows = scoring_table.css('tr')[2..3]
  raise "Unexpected scoring table structure for game #{game_id}" unless rows && rows.size == 2

  away_cells = rows[0].css('td').map { |td| td.text.gsub("\u00A0", ' ').strip }
  home_cells = rows[1].css('td').map { |td| td.text.gsub("\u00A0", ' ').strip }

  away_team = away_cells[0]
  home_team = home_cells[0]
  away_score = away_cells.last.to_i
  home_score = home_cells.last.to_i

  # ---------- GOAL SUMMARY table ----------
  goal_table = doc.css('table').find { |t| t.at_css('tr')&.text&.match?(/Goal|Scorer/i) }
  home_goals, away_goals = [], []

  if goal_table
    headers = goal_table.css('tr').first.css('td,th').map(&:text).map(&:strip)
    idx_team   = headers.index { |h| h.match?(/Team/i) } || 3
    idx_goal   = headers.index { |h| h.match?(/Goal|Scorer/i) } || 5
    idx_assist = headers.index { |h| h.match?(/Assist/i) } || 6

    ontario_is_home = game["location"] == "Home"

    goal_table.css('tr')[1..]&.each do |row|
      tds = row.css('td')
      next if tds.size < [idx_team, idx_goal, idx_assist].max + 1

      team_code = tds[idx_team]&.text&.gsub(/\u00A0/, '')&.strip&.upcase
      scorer    = tds[idx_goal]&.text&.split('(')&.first&.strip
      assists   = tds[idx_assist]&.text&.strip
      next if scorer.nil? || scorer.empty?

      entry = assists.nil? || assists.empty? ? scorer : "#{scorer} (#{assists})"

      if team_code == "ONT"
        ontario_is_home ? home_goals << entry : away_goals << entry
      else
        ontario_is_home ? away_goals << entry : home_goals << entry
      end
    end
  end

meta_table = doc.css('table').find { |t| t.text.match?(/Game Start|Game End|Game Length/i) }
meta = {}
if meta_table
  meta_table.css('tr').each do |r|
    tds = r.css('td').map { |td| td.text.gsub("\u00A0", ' ').strip }
    next unless tds.size >= 2
    meta[tds[0].gsub(':', '').strip] = tds[1].strip
  end
end

game_status_raw = meta['Game Status']
  
game_end_raw   = meta['Game End']
game_length_raw = meta['Game Length']
  
  # ---------- Status ----------
scheduled_start = nil
begin
  scheduled_start = Time.iso8601(game["scheduled_start"]) if game && game["scheduled_start"]
rescue
  scheduled_start = nil
end

now = Time.now

has_final_indicator =
  (game_length_raw && game_length_raw.match?(/\d+:\d+/)) ||
  (game_end_raw && !game_end_raw.empty?)

#this is good just not reading "unoffical final" reimplement if problems in game
  #  status =
#  if doc.text.include?("This game is not available")
#    "Upcoming"
#  elsif scheduled_start && now < scheduled_start
 #   "Upcoming"
#  elsif game_status_raw&.downcase&.include?("Unofficial Final")
#    "Final"
#  elsif game_end_raw && !game_end_raw.strip.empty?
#    "Final"
#  elsif scheduled_start && now >= scheduled_start
#    "Live"
#  else
#    "Upcoming"
#  end

  status =
  if doc.text.include?("This game is not available")
    "Upcoming"
  elsif scheduled_start && now < scheduled_start
    "Upcoming"
  elsif game_status_raw&.downcase&.include?("unofficial final")
    "Final"
 elsif has_final_indicator
    "Final"
  elsif scheduled_start && now >= scheduled_start
    "Live"
  else
    "Upcoming"
  end


# ---------- Debug (optional) ----------
if game_id.to_s == "1027839"
  warn "🧪 scheduled_start: #{scheduled_start}"
  warn "🧪 now: #{now}"
  warn "🧪 now >= scheduled_start: #{now >= scheduled_start}" if scheduled_start
  warn "🧪 status: #{status}"
  warn "🧪 has_final_indicator: #{has_final_indicator}"
end
  
  # ---------- OT/SO ----------
  normalize = ->(v) { v.to_s.gsub(/\u00A0/, '').strip }
  ot_away = away_cells.length > 5 ? normalize.call(away_cells[4]) : ""
  ot_home = home_cells.length > 5 ? normalize.call(home_cells[4]) : ""
  so_away = away_cells.length > 5 ? normalize.call(away_cells[5]) : ""
  so_home = home_cells.length > 5 ? normalize.call(home_cells[5]) : ""

  overtime_type = nil
  if status == "Final"
  #  ot_goals = ot_away.to_i + ot_home.to_i
   # so_goals = so_away.to_i + so_home.to_i
   # overtime_type = "OT" if ot_goals > 0
  #  overtime_type = "SO" if so_goals > 0
     ot_goals = ot_away.to_i + ot_home.to_i
     so_goals = so_away.to_i + so_home.to_i

     overtime_type =
       if ot_goals > 0
         "OT"
       elsif so_goals > 0
         "SO"
       else
         nil
       end
  end

    

  # ---------- Result ----------
  result = nil
  if status == "Final"
    ontario_is_home = home_team =~ /ontario/i
    ontario_score = ontario_is_home ? home_score : away_score
    opponent_score = ontario_is_home ? away_score : home_score

    prefix =
      if overtime_type == "SO"
        ontario_score > opponent_score ? "W(SO)" : "L(SO)"
      elsif overtime_type == "OT"
        ontario_score > opponent_score ? "W(OT)" : "L(OT)"
      else
        ontario_score > opponent_score ? "W" : "L"
      end

    result = "#{prefix} #{[ontario_score, opponent_score].max}-#{[ontario_score, opponent_score].min}"
  end

  {
    "game_id" => game_id.to_i,
    "date" => game["date"],
    "opponent" => game["opponent"],
    "location" => game["location"],
    "status" => status,
    "home_score" => home_score,
    "away_score" => away_score,
    "home_goals" => home_goals,
    "away_goals" => away_goals,
    "overtime_type" => overtime_type,
    "result" => result,
    "game_report_url" => url,
    "scheduled_start" => game["scheduled_start"]
  }
rescue => e
  warn "⚠️ Failed to parse game sheet for #{game_id}: #{e}"
  nil
end

# ---------- CLI ----------
if ARGV.empty?
  warn "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
game = nil
if File.exist?("reign_schedule.json")
  begin
    games = JSON.parse(File.read("reign_schedule.json"))
    game = games.find { |g| g["game_id"].to_s == game_id.to_s }
  rescue
    game = nil
  end
end

data = parse_game_sheet(game_id, game)
puts JSON.pretty_generate(data) if data
