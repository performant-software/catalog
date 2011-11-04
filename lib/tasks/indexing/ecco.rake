# encoding: UTF-8
##########################################################################
# Copyright 2011 Applied Research in Patacriticism and the University of Virginia
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################
$KCODE = 'UTF8'

namespace :xxx_ecco do
	def xxx_writelog(file, str)
		open(file, 'a') { |f|
			f.puts str
		}
	end

	def xxx_process_ecco_spreadsheets(hits, max_recs = 9999999)
		src = CollexEngine.new(["archive_estc"])
		total_recs = 0
		total_added = 0
		total_already_found = 0
		total_cant_find = 0
		Dir["#{MARC_PATH}/ecco/*.csv"].each {|f|
			File.open(f, 'r') { |f2|
				text = f2.read
				lines = text.split("\n")
				lines.each {|line|
					total_recs += 1
					line = line.gsub('"', '')
					rec = line.split(',', 2)
					# remove zeroes from between the letter and the non-zero part of the number
					reg_ex = /(.)0*(.+)/.match(rec[0])
					estc_id = reg_ex[1] + reg_ex[2]
					estc_uri = "lib://estc/#{estc_id}"
					obj = src.get_object(estc_uri, true)
					if obj == nil
						writelog("#{Rails.root}/log/ecco_error.log", "Can't find object: #{estc_uri}")
						total_cant_find += 1
					else
						arr = rec[1].split('bookId=')
						if arr.length == 1
							writelog("#{Rails.root}/log/ecco_error.log", "Unusual URL encountered: #{rec[1]}")
						else
							arr2 = arr[1].split('&')
							obj['archive'] = "ECCO"
							obj['url'] = [ rec[1] ]
							ecco_id = "lib://ECCO/#{arr2[0]}"
							obj['uri'] = ecco_id
							writelog("#{Rails.root}/log/ecco_error.log", "No year_sort: #{estc_uri} #{obj['uri']}") if obj['year_sort'] == nil
							writelog("#{Rails.root}/log/ecco_error.log", "No title_sort: #{estc_uri} #{obj['uri']}") if obj['title_sort'] == nil
							hits.push(obj)
							total_added += 1
							#puts "estc: #{estc_id} ecco: #{ecco_id}"
						end
					end
					CollexEngine.report_line("Total: #{total_recs} Added: #{total_added} Found: #{total_already_found} Can't find: #{total_cant_find}") if total_recs % 500 == 0
					return if total_recs >= max_recs
				}
			}
		}
		CollexEngine.report_line("Finished: Total: #{total_recs} Added: #{total_added} Found: #{total_already_found} Can't find: #{total_cant_find}")
	end

	def xxx_find_hit(hits, target)
		hits.each_with_index { |hit, i|
			return i if hit['uri'] == target['uri']
			return -1 if hit['uri'] > target['uri']
		}
		return -1
	end

	def xxx_process_ecco_fulltext(hits)
		require "#{Rails.root}/script/lib/process_gale_objects.rb"
		include ProcessGaleObjects
		src = CollexEngine.new(["archive_estc"])
		count = 0
		GALE_OBJECTS.each {|arr|
			filename = arr[0]
			estc_uri = arr[1]
			url = arr[3]
			text = ''
			File.open("#{ECCO_PATH}/#{filename}.txt", "r") { |f|
				text = f.read
			}
			obj = src.get_object(estc_uri, true)
			if obj == nil
				writelog("#{Rails.root}/log/ecco_error.log", "Can't find object: #{estc_uri}")
			else
				obj['text'] = text
				obj['has_full_text'] = true
				obj['freeculture'] = false
				obj['source'] = "Full text provided by the Text Creation Partnership."
				obj['archive'] = "ECCO"
				obj['url'] = [ url ]
				arr = url.split('bookId=')
				if arr.length == 1
					writelog("#{Rails.root}/log/ecco_error.log", "Unusual URL encountered: #{url}")
				else
					arr2 = arr[1].split('&')
					obj['uri'] = "lib://ECCO/#{arr2[0]}"
					writelog("#{Rails.root}/log/ecco_error.log", "No year_sort: #{estc_uri} #{obj['uri']}") if obj['year_sort'] == nil
					writelog("#{Rails.root}/log/ecco_error.log", "No title_sort: #{estc_uri} #{obj['uri']}") if obj['title_sort'] == nil
					index = find_hit(hits, obj)
					if index == -1
						hits.push(obj)
					else
						hits[index] = obj
					end
				end
			end
			count += 1
			CollexEngine.report_line("Processed: #{count}") if count % 500 == 0
		}
	end

	desc "Create all the RDF files for ECCO documents, using estc records and the spreadsheets and texts."
	task :create_rdf => :environment do
		start_time = Time.now
		CollexEngine.set_report_file("#{Rails.root}/log/ecco_error.log")	# just setting this first to delete it if it exists.
		CollexEngine.set_report_file("#{Rails.root}/log/ecco_progress.log")
		CollexEngine.report_line("Processing spreadsheets...")
		hits = []
		process_ecco_spreadsheets(hits)
		CollexEngine.report_line("Sorting...")
		hits.sort! { |a,b| a['uri'] <=> b['uri'] }
		CollexEngine.report_line("Processing fulltext...")
		process_ecco_fulltext(hits)
		RegenerateRdf.regenerate_all(hits, "#{RDF_PATH}/marc/ECCO", "ECCO", 500000)
		CollexEngine.report_line("Finished in #{(Time.now-start_time)/60} minutes.")
	end

	desc "Test that all ECCO objects have a 856 field (param: max_recs=XXX)"
	task :test_ecco_856 => :environment do
		if CAN_INDEX
			max_records = ENV['max_recs']

			puts "~~~~~~~~~~~ Scanning for 856 fields in estc..."
			start_time = Time.now
			require '#{Rails.root}/script/lib/estc_856_scanner.rb'
			Estc856Scanner.run("#{MARC_PATH}/estc", max_records)
			finish_line(start_time)
		end
	end
end