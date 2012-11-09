require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'json' # fuck fedex in the ass

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
				latest_row = doc.search('div[@id=collapse3]').first

				if latest_row
					latest_row = latest_row.next_sibling.next_sibling.next_sibling.next_sibling.next_sibling.next_sibling.search('tr')[1]

					status = ShipmentStatus.new(
						:number => number,
						:location => latest_row.children[0].children.first.content.ircify_html,
						:time => latest_row.children[2].content.ircify_html << " " << latest_row.children[4].content.ircify_html,
						:activity => latest_row.children[6].content.ircify_html,
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
						break # fuck the rest of this page
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

			def self.fetch(number)
				doc = Nokogiri::HTML(open("http://www.newegg.com/Info/TrackOrder.aspx?TrackingNumber=#{number}"))
				latest_row = doc.search('table[@class="trackDetailUPSSum"]/tr')[1]

				if latest_row
					status = ShipmentStatus.new(
						:number => number,
						:location => latest_row.search('./td').size == 4 ? \
							latest_row.search('./td')[2].inner_text.strip : nil,
						:time => latest_row.search('./td')[0].inner_text.strip,
						:activity => latest_row.search('./td')[1].inner_text.strip,
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
				doc = Nokogiri::HTML(open("http://trkcnfrm1.smi.usps.com/PTSInternetWeb/InterLabelInquiry.do?origTrackNum=#{number}"))
				latest_row = doc.search('//table[@summary="This table formats the detailed results."]/tr')[1]
				if latest_row
					status = ShipmentStatus.new(
						:number => number,
						:location => nil,
						:time => nil,
						:activity => latest_row.inner_text.strip(),
						:carrier => PRIMARY_NAME
					)
				else
					nil
				end
			end	
		end
	end

	class ShipmentScreenScraperManager
		def initialize()
			@by_name = Hash.new
			@loaded_modules = Array.new
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
		@scrapers.register(Scrapers::USPS)
	end
	attr_accessor :scrapers

	def help(plugin, topic="")
		"This plugin is a utility plugin which is only meant to be used by other plugins."
	end
end

ShipmentTrackingUtilityPlugin.new
