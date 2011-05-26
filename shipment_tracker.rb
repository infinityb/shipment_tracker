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
			'sup3r_k00l_k0mput3r' => {:number => '1ZX799330351143662', :courier => :ups},
			'plus-vidya' => {:number => '9405510200793822795785', :courier => :usps }
		}
	end # initialize 

	private
	def get_scraper_manager
		@bot.plugins[:shipmenttrackingutility].scrapers
	end

	def status_fetch(label)
		info = @tracking_numbers[label]
		return ShipmentStatusRecord.new(label, get_scraper_manager.fetch(info[:courier], info[:number]))
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
				m.reply status.ircify
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
			status = status_fetch(label)
			if status
				m.reply status
			else # status = nil
				m.reply "Sorry, no information is available."
			end # status
		else
			m.reply "Sorry, I don't know a shipment by that name"
		end
	rescue Exception => e
		m.reply e.class
		m.reply e
	end

	def cron_notify(m, params)
		@tracking_numbers.keys.each {|label|
			msg = status_fetch(label)
			next if msg.status.ircify == @registry[msg.label]

			@bot.say '#', msg
			if @tracking_numbers[label].has_key?(:owner)
				@bot.say @tracking_numbers[label][:owner], msg
			end
			@registry[msg.label] = msg.status.ircify
		}
	end # cron_notify

	def show_labels(m, params)
		m.reply "Available labels: " + @tracking_numbers.keys.map {|k| "\0033#{k}\017" }.join(', ')
	end

	def help(plugin, topic="")
		"shipment [ list | \002Label\017 | \002TrackingNumber\017 \002CourierName\017 ]"
	end

end # ShipmentTrackerPlugin

plugin = ShipmentTrackerPlugin.new
plugin.default_auth('notify', false)

plugin.map 'shipment', :action => 'status_all'
plugin.map 'shipment list', :action => 'show_labels'
plugin.map 'shipment cron_notify', :action => 'cron_notify', :auth_path => 'notify'
plugin.map 'shipment :label', :action => 'status_named'
plugin.map 'shipment :number :courier', :action => 'status_unnamed'
#plugin.map 'shipment add ":label" :number :courier', :action => 'add_shipment'

