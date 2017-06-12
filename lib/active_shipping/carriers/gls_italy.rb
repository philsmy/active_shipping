# https://www.gls-italy.com/?option=com_gls&view=track_e_trace&mode=search&numero_spedizione=M1036694014&tipo_codice=nazionale
require 'curl'

module ActiveShipping
  class GlsItaly < Carrier
    cattr_reader :name
    @@name = "GLS Italy"
    
    LIVE_TRACKING_URL = 'https://www.gls-italy.com/?option=com_gls&view=track_e_trace&mode=search&numero_spedizione=%s&tipo_codice=nazionale'
    DATE_PARSER_STR = "%d/%m/%y %H:%M %Z"

    # Retrieves tracking information for a previous shipment
    #
    # @note Override with whatever you need to get a shipping label
    #
    # @param tracking_number [String] The unique identifier of the shipment to track.
    # @param options [Hash] none at the moment
    # @return [ActiveShipping::TrackingResponse] The response from the carrier. This
    #   response should a list of shipment tracking events if successful.
    def find_tracking_info(tracking_number, options = {})
      options = @options.merge(options)
      parse_tracking_response(tracking_number, options)
    end

    def parse_tracking_response(tracking_number, options = {})
      sleep 2;
      scheduled_delivery_date, actual_delivery_date = nil
      delivered = false
      
      easy = Curl::Easy.new(LIVE_TRACKING_URL % tracking_number)
      easy.timeout = options[:timeout].present? ? options[:timeout] : 20
      easy.follow_location = true
      easy.max_redirects = 3 
      easy.proxy_url = options[:proxy_url] if options[:proxy_url].present?
      easy.proxy_port = options[:proxy_port] if options[:proxy_port].present?
      if options[:proxy_tunnel].present? && options[:proxy_tunnel]
        easy.proxy_tunnel = true
        easy.proxy_type = options[:proxy_type]
      end
      easy.perform
      
      doc = Nokogiri::HTML(easy.body_str)
      
      easy.close
      
      rows = doc.css("table#esitoSpedizioneRS tr:not(:first-of-type)")
      
      error = doc.css(".errorTxt").text
      
      shipment_events = []
      
      rows.each do |activity|
        description = activity.css("td")[2].text.squish
        time_str = "#{activity.css("td")[0].text}"
        zone = "CET"
        zoneless_time = ActiveSupport::TimeZone[zone].parse(time_str).to_datetime
        location = activity.css("td")[1].text.squish
        notes = activity.css("td")[3].text.squish
        p "#{description}, #{zoneless_time}, #{location}"
        shipment_events << ShipmentEvent.new(description, zoneless_time, location, notes, nil)
      end

      success = true
      
      if shipment_events.any?
        status_description = shipment_events.first.name
        
        status = :in_transit
        if status_description =~ /CONSEGNATA/i
          status = :delivered
        end
        if status_description =~ /Arrivata in sede destinataria/i
          status = :delivered
        end
        if status_description =~ /item number isn't recognised/i
          status = :not_recognized
          success = false
        end

        if status == :delivered
          actual_delivery_date = shipment_events.first.time
          delivered = true
        end
      
        shipment_events = shipment_events.sort_by(&:time)
      
        ActiveShipping::TrackingResponse.new(success, status_description, {success: success},
                             :carrier => @@name,
                             :status => status,
                             :status_description => status_description,
                             :scheduled_delivery_date => scheduled_delivery_date,
                             :actual_delivery_date => actual_delivery_date,
                             :shipment_events => shipment_events,
                             :delivered => delivered,
                             :tracking_number => tracking_number)
      else
        success = false
      end
      
    end
  end
end