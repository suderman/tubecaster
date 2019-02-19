require 'sinatra'
require 'fileutils'
require 'uri'
require 'yaml'

# Path to build directory
build_dir = File.expand_path(File.join(File.dirname(__FILE__), 'build'))

# Path to config directory
config_dir = File.expand_path(File.join(File.dirname(__FILE__), 'config'))

# Path to yml file
channel_yml = File.join(config_dir, 'channel.yml')
unless File.file?(channel_yml) 
  File.write(channel_yml, [
		":title: 'My Podcast'",
		":description: 'Edit this file to configure your podcast.'",
		":url: 'http://localhost:3000/'",
    ":mp3_dir: '#{Dir.home}}/Downloads'",
		":youtube_dl: '/usr/local/bin/youtube-dl'"
	].join("\n"))
end
$channel = YAML.load_file(channel_yml)
$channel[:channel_yml] = channel_yml

# Path to mp3 directory
mp3_dir = File.expand_path($channel[:mp3_dir] || build_dir)
mp3_dir = build_dir unless (Dir.exist?(mp3_dir))
set :public_folder, mp3_dir
$channel[:mp3_dir] = mp3_dir

# Path to rss file
feed_rss = File.join(build_dir, 'index.rss')
FileUtils.touch(feed_rss)
$channel[:feed_rss] = feed_rss

# Path to html file
feed_html = File.join(build_dir, 'index.html')
FileUtils.touch(feed_html)
$channel[:feed_html] = feed_html

get '/rss' do
  send_file $channel[:feed_rss] 
end

get '/' do
  send_file $channel[:feed_html] 
end

# Path to image file
feed_jpg = File.join(config_dir, 'image.jpg')
unless File.file?(feed_jpg) 
  template_jpg = File.join(File.expand_path(File.dirname(__FILE__)), 'templates', 'image.jpg')
  FileUtils.cp(template_jpg, feed_jpg)
end
$channel[:feed_jpg] = feed_jpg

get '/jpg' do
  send_file $channel[:feed_jpg]
end

# Path to youtube-dl
$channel[:youtube_dl] = $channel[:youtube_dl] || 'youtube-dl'

# YouTube-DL command
def youtube(url)
  command = <<~HEREDOC
    cd "#{$channel[:mp3_dir]}" && \
    #{$channel[:youtube_dl]}      \
       --quiet                    \
       --no-warnings              \
       --add-metadata             \
       --extract-audio            \
       --audio-format=mp3         \
       --embed-thumbnail          \
       --restrict-filenames       \
    "#{url}"
  HEREDOC
  return command.gsub!(/\s+/, ' ')
end


# Path to dropcaster binary
$channel[:dropcaster] = File.join(
  `bundle info dropcaster 2> /dev/null | grep Path:`.split(' ').last, 
  'bin/dropcaster'
) 

# Dropcaster command
def dropcaster

  # Path to dropcaster templates
  template_html = File.join(File.expand_path(File.dirname(__FILE__)), 'templates', 'channel.html.erb')
  template_rss  = File.join(File.expand_path(File.dirname(__FILE__)), 'templates', 'channel.rss.erb')

  command = <<~HEREDOC
      cd "#{$channel[:mp3_dir]}"              \
      &&                                      \
      #{$channel[:dropcaster]}                \
        --channel="#{$channel[:channel_yml]}" \
        --channel-template="#{template_html}" \
      |                                       \ 
      tr -cd "[:print:]\\n"                   \
      > "#{$channel[:feed_html]}"             \
      &&                                      \
      #{$channel[:dropcaster]}                \
        --channel="#{$channel[:channel_yml]}" \
        --channel-template="#{template_rss}"  \
      |                                       \ 
      tr -cd "[:print:]\\n"                   \
      > "#{$channel[:feed_rss]}"
  HEREDOC
  return command.gsub!(/\s+/, ' ')

end

get '/new/*' do |url|
  url = URI.decode(params[:splat].first)
  url = url.gsub('http://','http:/').gsub('http:/', 'http://')
  url = url.gsub('https://', 'https:/').gsub('https:/','https://')
  pid = spawn("#{youtube(url)} && #{dropcaster}")
  Process.detach(pid)
  redirect "/"
end

get '/new' do 
  pid = spawn(dropcaster)
  Process.detach(pid)
  redirect "/"
end
