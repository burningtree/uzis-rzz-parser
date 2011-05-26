#!/usr/bin/ruby
require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'openssl'
require 'json'
require 'cgi'
require 'digest/md5'
require 'progressbar'
require 'iconv'

############ config

base_uri = 'https://snzr.uzis.cz/viewzz/RZZHledat1.htm'
base_region_uri = 'https://snzr.uzis.cz/viewzz/lb/RZZSeznam.pl?KRAJ={id}&WAIT_PAGE=ON'
base_item_uri = 'https://snzr.uzis.cz/viewzz/lb/RZZDetail.pl?{id}=Detail&WAIT_PAGE=ON'

DB_FILE = './data.json'
CACHE_DIR = './cache'

############ app

OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE

class String
	def sanity
		self.gsub(/\302\240/, " ").strip
	end
end
def get_page(uri)
	fname = CACHE_DIR + "/" + Digest::MD5.hexdigest(uri) + ".html"
	if File.exists?(fname) && File.size(fname) > 0
		begin
			file = File.open(fname).read
		rescue Timeout
			retry
		end
	else
		file = open(uri).read
		File.open(fname, 'w') { |f| f.write(file) }
	end
	Nokogiri::HTML(file)
end
def msg(text)
	$stdout.write text
	$stdout.flush
end

def parse_item(uri)
	# zakladni udaje
	doc = get_page(uri)
	data = {}

	doc.css('table[width="616"][border="1"] tr').each do |r|
		col = r.css('td:nth-child(1)').text.sanity
		data[col] = r.css('td:nth-child(2)').text.sanity
	end

	doc.css('table[width="617"]').each do |t| 
		name = t.css('tr:nth-child(1) td').first.text.sanity
		case name
			# oddeleni
			when "Oddělení"
				data[name] = []
				cols = []
				t.css('tr:nth-child(1) td').each { |cn| cols << cn.text.sanity }
				t.css('tr:not(:nth-child(1))').each do |r|
					part = {}; i = 0
					r.css('td').each do |c|
						cn = cols[i]
						part[cn] = c.text.sanity
						i = i+1
					end
					data[name] << part
				end

			# smlouvy s pojistovnami
			when "smlouvy s pojišťovnami :"
				data[name] = []
				t.css('tr:not(:nth-child(1))').each do |r|
					data[name] << r.text.sanity
				end
		end
	end
	data
end

def parse_list(uri)
	doc = get_page(uri)
	base_vals = { :type_id => nil, :type_name => nil, :orp => nil }
	list = []

	doc.css('body > table').each do |t|
		if t['width'] == "800"
			t.css('tr > td > table > tr > td > table > tr').each do |l|
				next if l.css('td:nth-child(1)').first.text == 'Název'
				rzz_id = l.css('td:nth-child(4) a')[0]['onclick'].match(/pl\?(\d+)=D/)[1]
				list << rzz_id
			end
		end
	end
	list
end

# load db
db = (File.exists?(DB_FILE) ? JSON::load( File.open( DB_FILE )) : {});
msg "Database file: #{DB_FILE} (#{db.size} items)\n"

# fetch regions
regions = []
get_page(base_uri).css('select#kraj option').each do |o|
	regions << { :id => o['value'], :name => o.text }
end

# process
begin
	converter = Iconv.new("cp1250", "utf8")
	regions.each do |region|
		msg "===> #{region[:name]} .. "
		v = CGI.escape(converter.iconv(region[:id]))
		list = parse_list(base_region_uri.sub('{id}', v))

		# find loaded items
		to_load = []
		list.each { |i| (to_load << i) if !db.include?(i) }
		msg "#{list.size} items on web, #{list.size-to_load.size} in local database, " +
			"#{to_load.size} to fetch\n"


		# fetch not loaded items
		pbar = ProgressBar.new(region[:name], to_load.size)
		to_load.each do |i|
			db[i] = parse_item(base_item_uri.sub('{id}', i))
			db[i]['id'] = i
			pbar.inc
		end
		pbar.finish
	end

rescue Exception
	msg($!.class.to_s == "Interrupt" ? "\n\nPressing CTRL-C. Aborting .. \n" : 
			 "\n\nerror: [#{$!.class}] #{$!}\nbacktrace:\n#{$!.backtrace.join("\n")}\n\n")
ensure
	# save database
	msg "Saving database .. "
	File.open(DB_FILE, "w") { |f| f.write(JSON.dump(db)) }
	msg "ok\n"
end

