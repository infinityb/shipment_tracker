require 'rubygems'
require 'nokogiri'
require 'open-uri'

class ShipmentTrackerPlugin < Plugin
	class ShipmentStatusRecord < Struct.new(:label, :status)
		def to_s
			if self.status
				"\00303#{label}\003: #{status.ircify.gsub("\n", " ")}"
			else
				"\00303#{label}\003: No information available."
			end
		end
	end

	def initialize
		super
		labels = @registry['labels']
		if labels.nil?
			@registry['labels'] = []
		end
	end # initialize

	private

	def mangle_label_name(label)
		return "label::%s" % label
	end

	def get_scraper_manager
		@bot.plugins[:shipmenttrackingutility].scrapers
	end

	def status_fetch(label)
		info = @registry[mangle_label_name(label)]
		return ShipmentStatusRecord.new(label, get_scraper_manager.fetch(info[:courier], info[:number]))
	end # status_fetch

	public
	def status_all(m, params)
		announce_labels = @registry['labels'].find_all {|label|
			th = @registry[mangle_label_name(label)]
			if th.nil?
				@registry['labels'] = @registry['labels'].find_all {|x| label != x }
				false
			else
				!th.has_key?(:channels) or th[:channels].include?(m.channel.to_s)
			end
		}
		if 0 == announce_labels.size
			m.reply "No known items"
		end

		announce_labels.each {|label|
			data = @registry[mangle_label_name(label)]
			if not get_scraper_manager.has_courier?(data[:courier])
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

		if @registry[mangle_label_name(label)].nil?
			m.reply "Sorry, I don't know a shipment by that name"
		else
			trinfo = @registry[mangle_label_name(label)]
			if not get_scraper_manager.has_courier?(trinfo[:courier])
				m.reply "Sorry, that courier service is not supported. :("
				return
			end
			status = status_fetch(label)
			if status
				m.reply status
			else # status = nil
				m.reply "Sorry, no information is available."
			end # status
		end
	rescue Exception => e
		m.reply e.class
		m.reply e
		if m.channel == '#lolinano'
			m.reply e.backtrace
		end
	end

	def cron_notify(m, params)
		@tracking_numbers.keys.each {|label|
			channel_names = @tracking_numbers[label].has_key?(:channels) and @tracking_numbers[label][:channels]
			owner = @tracking_numbers[label].has_key?(:owner) and @tracking_numbers[label][:owner]

			msg = status_fetch(label)
			next if msg.status.ircify == @registry[msg.label]

			if channel_names
				for channel_name in channel_names
					channel = @bot.channels.find {|ch| ch.name == channel_name }
					if owner and channel.users.find {|u| u.nick == owner }
						@bot.say channel, [owner, @bot.config['core.nick_postfix'], msg].join
					else
						@bot.say channel, msg
					end
				end
			else
				@bot.say '#', msg
			end
			@registry[msg.label] = msg.status.ircify
		}
	end # cron_notify

	def show_labels(m, params)
		m.reply "Available labels: " + @registry['labels'].\
			find_all {|k| @registry[mangle_label_name(k)] }.\
			map {|k| "\0033#{k}\017" }.join(', ')
	end

	def show_couriers(m, params)
		m.reply get_scraper_manager.loaded_modules.map {|x| "\002#{x::PRIMARY_NAME}\017" }.join(', ')
	end

	def help(plugin, topic="")
		"shipment [ list | add \002Label\017 \002TrackingNumber\017 \002CourierName\017 | del \002Label\017 | \002Label\017 | \002TrackingNumber\017 \002CourierName\017 ]"
	end

	def add_shipment(m, params)
		begin
			if not params[:label].is_a?(String)
				m.reply "error: wtf label"
				return
			end
			if not get_scraper_manager.has_courier?(params[:courier])
				m.reply "No courier by the name of " + params[:courier]
				return
			end
			metalabel = mangle_label_name(params[:label])
			if !@registry[metalabel].nil?
				m.reply "label already exists."
				return
			end
			@registry[metalabel] = {
				:number => params[:number],
				:courier => params[:courier].downcase.to_sym
			}
			@registry['labels'] = @registry['labels'] + [params[:label]]
			status = status_fetch(params[:label])
			if status
				m.reply "Added; %s" % [status]
			else # status = nil
				m.reply "Added; No information is available yet."
			end # status
		rescue Exception => e
			m.reply "I dun goofed. %s, %s" % [e.class, e]
		end 
	end

	def del_shipment(m, params)
		begin
			if not params[:label].is_a?(String)
				m.reply "error: wtf label"
				return
			end
			metalabel = mangle_label_name(params[:label])
			@registry.delete(metalabel)
			@registry['labels'] = @registry['labels'].find_all {|label| label != params[:label] }
			m.okay
		rescue Exception => e
			m.reply "I dun goofed. %s, %s" % [e.class, e]
		end
	end

end # ShipmentTrackerPlugin

plugin = ShipmentTrackerPlugin.new
plugin.default_auth('notify', false)

plugin.map 'shipment', :action => 'status_all'
plugin.map 'shipment list', :action => 'show_labels'
plugin.map 'shipment list couriers', :action => 'show_couriers'

plugin.map 'shipment cron_notify', :action => 'cron_notify', :auth_path => 'notify'

plugin.map 'shipment del :label', :action => 'del_shipment'
plugin.map 'shipment rm :label', :action => 'del_shipment'
plugin.map 'shipment add :label :number :courier', :action => 'add_shipment'

plugin.map 'shipment :label', :action => 'status_named'
plugin.map 'shipment :number :courier', :action => 'status_unnamed'
