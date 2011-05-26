#!/usr/bin/ruby

require 'rubygems'
require 'csv'
require 'json'

INPUT_FILE = "./data.json"
OUTPUT_FILE = "./data.csv"

#########################

data = JSON.load(File.open(INPUT_FILE))

# cols
cols = []
data.first[1].each_key do |cn|
	cols << cn
end

lines = 0

# values
items = ""
data.each do |row, values|
	item = {}

	values.each do |k, val|
		if !cols.include?(k)
			cols << k
		end
		item[k] = val
	end

	arr = []
	cols.each do |k|
		if item[k].class == Array
			arr << ""
		else
			arr << item[k]
		end
		lines += 1
	end
	items += arr.map { |x| "\"#{x}\"" }.join(";") + "\n"
end

out = cols.map { |x| "\"#{x}\"" }.join(";")+"\n"
out += items

# save to file
File.open(OUTPUT_FILE, "w") { |f| f.write(out) }

puts "Done. #{lines} lines converted from #{INPUT_FILE} to #{OUTPUT_FILE}"

