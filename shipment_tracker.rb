require 'rubygems'
require 'nokogiri'
require 'open-uri'

class ShipmentTrackerPlugin < Plugin
	class ShipmentStatusRecord < Struct.new(:label, :status)
		def to_s
			if self.status
				"\00303#{label}\003: #{status.ircify}"
			else
				"\00303#{label}\003: No information available."
			end
		end
	end

	def initialize
		super
		@tracking_numbers = {
			#'Case' => '1ZX799390310081385',
			#'Everything else' => '1ZX799331231131463'
			#'Disks' => {:number => '1Z462E560321092067', :courier => 'ups'},
			#'Fans' => {:number => '1ZX799470329512449', :courier => 'ups'},
			#'Monitor' => {:number => '134619891746049', :courier => 'fedex'}
			# "Final Fantasy™ XIV COLLECTOR'S EDITION" => {:number => '1Z04462W1300903990', :courier => 'ups'}
			#"IB's dicks" => {:number => '1Z8FX6286801195292', :courier => 'ups'},
			#"WoW Anthology" => {:number => '1ZA7810W0398708948', :courier => 'ups'}
			#"Overpriced HID" => {:number => '1Z4F37F10399609311', :courier => 'ups'}
			#"魔法少女リリカルなのは　The MOVIE 1st＜初回限定版＞" => {:number => '424981299085', :courier => 'fedex'}
			#'Disk' => {:number => '1ZX799470342426740', :courier => 'ups'},
			#'WiMAX CPE' => {:number => '485264002054', :courier => 'fedex'},
			#'WiMAX CPE the 2nd' => {:number => '485264110765', :courier => 'fedex'},
			#'WiMAX CPE - ODU ' => {:number => '1Z3X3F271343232801', :courier => 'ups'},
			#'Plus Headphones' => {:number => '1Z0X118A1210790602', :courier => 'ups'},
			#'HD 280 Pro' => {:number => '1Z5993920144768026', :courier => 'ups'},
			#'Gentech CPE' => {:number => '1Z07R37W9096472131', :courier => :ups},
			'IBの6950' => {:number => 'KCV000120856', :courier => :newegg},
		}
	end # initialize 

	private
	def get_scraper_manager
		@bot.plugins[:shipmenttrackingutility].scrapers
	end

	def status_fetch(label)
		info = @tracking_numbers[label]
		ShipmentStatusRecord.new(label, get_scraper_manager.fetch(info[:courier], info[:number]))
	end # status_fetch

	public
	def status_all(m, params)
		@tracking_numbers.keys.each {|label|
			if not get_scraper_manager.has_courier?(@tracking_numbers[label][:courier])
				m.reply "#{label}: Sorry, that courier service is not supported. :("
			end
			ssr =  status_fetch(label)
			if ssr
				m.reply ssr
			else # status = nil
				m.reply "#{label}: Sorry, no information is available."
			end
		}
        rescue Exception => e
                m.reply e.class
                m.reply e
	end # status

	def status_unnamed(m, params)
		number = params[:number]
		courier = params[:courier].downcase

		if get_scraper_manager.has_courier?(courier)
			status = get_scraper_manager.fetch(courier, number)

			if status
				m.reply status
			else # status = nil
				m.reply "Sorry, no information is available."
			end # status
		else
			m.reply "Sorry, that courier service is not supported. :("
		end
	rescue Exception => e
		m.reply e.class
		m.reply e
	end # status_unnamed

	def status_named(m, params)
		label = params[:label]

		if @tracking_numbers.has_key?(label)
			if not get_scraper_manager.has_courier?(@tracking_numbers[label][:courier])
				m.reply "Sorry, that courier service is not supported. :("
				return
			end
			ssr = status_fetch(label)
			if ssr
				m.reply ssr
			else # status = nil
				m.reply "Sorry, no information is available."
			end
		else
			m.reply "Sorry, I don't know a shipment by that name"
		end
	rescue Exception => e
		m.reply e.class
		m.reply e
	end

	def cron_notify(m, params)
		status_fetch.each {|msg|
                        @bot.say '#', msg if msg.status.ircify != @registry[msg.label]
                        @registry[msg.label] = msg.status.ircify
                }
        end # cron_notify

	def help(plugin, topic="")
		"shipment [ \002Label\017 | \002TrackingNumber\017 \002CourierName\017 ]"
	end

end # ShipmentTrackerPlugin

plugin = ShipmentTrackerPlugin.new
plugin.default_auth('notify', false)

plugin.map 'shipment', :action => 'status_all'
plugin.map 'shipment :label', :action => 'status_named'
plugin.map 'shipment :number :courier', :action => 'status_unnamed'
#plugin.map 'shipment add ":label" :number :courier', :action => 'add_shipment'
plugin.map 'shipment cron_notify', :action => 'cron_notify', :auth_path => 'notify'

