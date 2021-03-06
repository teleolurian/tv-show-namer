#! /usr/bin/env ruby
%w{rubygems tvdb_party highline/import ostruct}.each {|x| require x}
API_KEY = 'GET-YOUR-OWN-KEY'
class String; def /(k); [self,k].join ?/; end; end

data = OpenStruct.new

# First, initialize tvdb_party
data.tvdb = TvdbParty::Search.new(API_KEY)

# Get the name stuff
data.pwd = Dir.pwd

# Figure out the series name
data.series_name = data.pwd.split(?/)[1..-1]
if data.series_name.last =~ /se(ason|ries)/i
  data.found_season = data.series_name.pop.match(/se(?:ason|ries).*(\d+)/i)[1]
end
data.series_name = data.series_name.last

# Find the show
data.show_matches = data.tvdb.search(data.series_name)

# Give a choice if there's too many
if data.show_matches.length < 1
  raise "No show matches found!"
elsif data.show_matches.length == 1
  data.show = choose do |menu|
    sm = data.show_matches[0]
    puts "It looks like the show #{sm['SeriesName']} #{sm['FirstAired']}."
    menu.choice("Yes") { sm }
    menu.choice("Nope - Abort") { :abort }
  end
else
  data.show = choose do |menu|
    puts "Please select one of the following shows:"
    data.show_matches.each do |show|
      menu.choice("#{show['SeriesName']} (#{show['FirstAired']})") { show }
    end
    menu.choice("Abort") { :abort }
  end
end
raise 'Aborted!' if data.show == :abort
data.show = data.tvdb.get_series_by_id(data.show['id'])

# Match episodes
data.sources = {}
Dir.glob("*.{mp*,avi,mkv,wmv,mov,tp,ts,m2ts,vob}").each do |filename|
  match = filename.match(/S(?:eason)*\W*(\d+)E(?:p\w*)*\W*(\d+)/i)
  match ||= filename.match(/\b(\d+)x(\d+)\b/)
  if data.found_season
    match ||= filename.match(/ep\w*\s*(\d+)/i)
    match = match ? [nil, data.found_season, match[1]] : false
  end
  match ||= filename.match(/(\d)(\d{2})/)
  next unless match

  season, episode = match[1..2].map(&:to_i)
  ext = filename.split(?.).last
  ref = data.show.get_episode(season, episode)
  next unless ref
  data.sources[filename] = {
    :season     => season,
    :episode    => episode,
    :ref        => ref
  }
  stext = season.to_s.rjust(2,?0)
  etext = episode.to_s.rjust(2,?0)

  data.sources[filename][:target] = "S#{stext}E#{etext} #{ref.name}.#{ext}".gsub(/[\?\#\!\/\\]+/, '-')
end

puts $/ + $/
puts "The following move is proposed"
data.sources.keys.sort.each do |filename|
  puts filename
  puts data.sources[filename][:target]
  puts $/
end

copy = choose do |menu|
  menu.choice("Yes") { true }
  menu.choice("No") { false }
end

exit unless copy

# get fanart

fan_art = []

data.show.fanart('en').each do |fanart|
  fm = fanart.path.match(/(\d+)\.jpg/)
  fan_art << fm[0]
  Dir.mkdir('.backdrops') unless File.exists?('.backdrops')
  puts "Downloading fanart #{fm[0]}..."
  Kernel.system "curl \"#{fanart.url}\" -o .backdrops/#{fm[0]}"
end
fan_art = fan_art.map {|x| "<backdrop>./.backdrops/#{x}</backdrop>"}.join('')


data.sources.each_pair do |filename, v|
  FileUtils.mv filename, v[:target] rescue true
  ref = v[:ref]
  metadata = %Q{<?xml version="1.0" encoding="utf-8"?>
    <details>
      <year>#{ref.air_date}</year>
      <title>#{ref.name}</title>
      <overview>#{ref.overview}</overview>
      #{data.show.genres.collect {|x| "<genre>#{x}</genre>"}.join('')}
      <director>#{ref.director}</director>
      #{data.show.actors.collect {|x| "<actor>#{x.name}</actor>"}.join('')}
      #{fan_art}
    </details>}
  metadata_filename = v[:target].sub(/\.\w+$/, '.xml')
  IO.write(metadata_filename, metadata)
end

puts "Done! Exiting." + $/












