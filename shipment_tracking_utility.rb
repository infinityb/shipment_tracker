require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'json'

class ShipmentTrackingUtilityPlugin < Plugin
	class ShipmentStatus
		@number = nil
		@location = nil
		@time = nil
		@activity = nil
		@carrier = nil

		attr_reader :number, :location, :time, :activity, :carrier

		def initialize(data)
			@number = data[:number]
			@location = data[:location]
			@time = data[:time]
			@activity = data[:activity]
			@carrier = data[:carrier]
		end # initialize

		def ircify
			"#{activity}#{" @ #{time}" if time}#{" - #{location}" if location}"
		end
	end # ShipmentStatus

	module Scrapers
		module UPS
			NAME_KEYS = [:ups]
			PRIMARY_NAME = 'UPS'

			def self.fetch(number)
				doc = Nokogiri::HTML(open("http://wwwapps.ups.com/WebTracking/processInputRequest?sort_by=status&tracknums_displayed=1&TypeOfInquiryNumber=T&loc=en_US&InquiryNumber1=#{number}&track.x=0&track.y=0"))
				table = doc.search('table[@class=dataTable]').first
				latest_row = table.search('tr')[1]

				if latest_row
					cells = latest_row.search('td')
					status = ShipmentStatus.new(
						:number => number,
						:location => cells[0].content.ircify_html,
						:time => (cells[1].content + " " + cells[2].content).ircify_html,
						:activity => cells[3].content.ircify_html,
						:carrier => PRIMARY_NAME
					)
				else
					nil
				end
			end # fetch UPS
		end

		module FedEx
			NAME_KEYS = [:fedex]
			PRIMARY_NAME = 'FedEx'

			def self.fetch(number)
				doc = open("http://www.fedex.com/Tracking?language=english&cntry_code=us&tracknumbers=#{number}")

				data = ''
				doc.each_line do |line|
					if line =~ /^var detailInfoObject/
						data = line
						break # ignore the rest of this page
					end
				end
				data = data.sub(/var detailInfoObject = /, '').sub(/;\n$/, '')

				if data == ''
					return nil
				end
				# keys = ["scanDate", "GMTOffset", "showReturnToShipper", "scanStatus", "scanLocation", "scanTime", "scanComments"]
				data = JSON.parse(data)
				latest_row = data['scans'].first

				if latest_row
					status = ShipmentStatus.new(
						:number => number,
						:location => latest_row['scanLocation'],
						:time => latest_row['scanDate'] << ' ' << latest_row['scanTime'],
						:activity => latest_row['scanStatus'],
						:carrier => PRIMARY_NAME
					)
				else
					nil
				end
			end # fetch fedex

		end
		module Purolator
			NAME_KEYS = [:purolator]
			PRIMARY_NAME = 'Purolator'

			def self.fetch(number)
				doc = Nokogiri::HTML(open("https://eshiponline.purolator.com/SHIPONLINE/Public/Track/TrackingDetails.aspx?pin=#{number}"))
				latest_row = doc.search('//div[@id="detailTable"]/table/tbody/tr').first

				if latest_row
					latest_row = latest_row.search('./td')

					status = ShipmentStatus.new(
						:number => number,
						:location => nil,
						:time => (latest_row[0].inner_text + ' ' + latest_row[1].inner_text).gsub("\n", ' ').gsub(/\s+/, ' '),
						:activity => latest_row[2].inner_text.gsub("\n", ' ').gsub(/\s+/, ' '),
						:carrier => PRIMARY_NAME
					)
				else
					nil
				end
			end
		end
		module Newegg
			NAME_KEYS = [:newegg]
			PRIMARY_NAME = 'newegg'
			def self._get_json_obj(doc)
				javascript_tags = doc.search('script[@type="text/javascript"]').
					find_all {|x| x.to_s.include?('detailInfoObject') }
				if javascript_tags.empty?
					return nil
				end
				split_data = javascript_tags[0].text.strip.
					split(";\r\n")[0].split("=", 2)
				if split_data.size != 2
					return nil
				end
				return JSON.parse(split_data[1].strip)
			end
			def self.fetch(number)
				doc = Nokogiri::HTML(open("http://www.newegg.com/Info/TrackOrder.aspx?TrackingNumber=#{number}"))
				latest_row = doc.search('table[@class="trackDetailUPSSum"]/tr')[1]

				json_data = _get_json_obj(doc)
				if json_data and json_data.include?('scans') and !json_data['scans'].empty?
					latestScan = json_data['scans'][0]
					ShipmentStatus.new(
						:number => number,
						:location => latestScan['scanLocation'],
						:time => ("%s %s %s" % [
							  latestScan['scanDate'],
							  latestScan['scanTime'],
							  latestScan['GMTOffset']
						]),
						:activity => latestScan['scanStatus'],
						:carrier => PRIMARY_NAME
					)
				elsif latest_row
					datetime, location, activity = latest_row.search('td').map(&:text)
					ShipmentStatus.new(
						:number => number,
						:location => location,
						:time => datetime,
						:activity => activity,
						:carrier => PRIMARY_NAME
					)
				end
			end
		end
		module PackageTrackr
			NAME_KEYS = [:packagetrackr]
			PRIMARY_NAME = 'packagetrackr'

			def self.fetch(number)
				doc = Nokogiri::HTML(open("http://www.packagetrackr.com/track/#{number}"))
				latest_row = doc.search('#track-info-progress tr')[0]

				if latest_row
					details = latest_row.children[0].inner_text.strip.split(/\n/)
					status = ShipmentStatus.new(
						:number => number,
						:location => details[0],
						:time => details[1],
						:activity => details[2],
						:carrier => PRIMARY_NAME
					)
				else
					nil
				end
			end
		end
		module USPS
			NAME_KEYS = [:usps]
			PRIMARY_NAME = 'USPS'

			def self.fetch(number)
				doc = Nokogiri::HTML(open("https://tools.usps.com/go/TrackConfirmAction_input?origTrackNum=#{number}"))
				ShipmentStatus.new(
					:number => number, 
					:location => doc.css('.shaded .location')[0].text.strip,
					:time =>  doc.css('.shaded .date-time')[0].text.strip,
					:activity => doc.css('.shaded .status')[0].text.strip,
					:carrier => PRIMARY_NAME
				)
			end
		end
	end

	class ShipmentScreenScraperManager
		def initialize()
			@by_name = Hash.new
			@loaded_modules = Array.new
		end

		def loaded_modules
			@loaded_modules.dup
		end

		def register(scraper_module)
			for name in scraper_module::NAME_KEYS
				if @by_name.has_key?(name.to_sym)
					raise RuntimeException, "already registered."
				end
				@by_name[name.to_sym] = scraper_module
			end
			@loaded_modules << scraper_module
		end

		def [](name)
			@by_name[name.to_sym]
		end

		def has_courier?(name)
			@by_name.has_key?(name.to_sym)
		end

		def fetch(courier, number)
			self[courier.to_sym].fetch(number)
		end
	end

	def initialize()
		super
		@scrapers = ShipmentScreenScraperManager.new()
		@scrapers.register(Scrapers::UPS)
		@scrapers.register(Scrapers::FedEx)
		@scrapers.register(Scrapers::Purolator)
		@scrapers.register(Scrapers::Newegg)
		@scrapers.register(Scrapers::PackageTrackr)
		@scrapers.register(Scrapers::USPS)
	end
	attr_accessor :scrapers

	def help(plugin, topic="")
		"This plugin is a utility plugin which is only meant to be used by other plugins."
	end
end

ShipmentTrackingUtilityPlugin.new
