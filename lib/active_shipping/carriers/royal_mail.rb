require 'curl'

module ActiveShipping
  class RoyalMail < Carrier
    cattr_reader :name
    @@name = "Royal Mail"

    LIVE_TRACKING_URL = 'https://www.royalmail.com/business/track-your-item?trackNumber=%s&op='
    DATE_PARSER_STR = "%d/%m/%y %H:%M %Z"
    DATE_PARSER_STR_2 = "%d-%b-%Y %H:%M %Z"

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
      easy.proxy_url = options[:proxy_url] if options[:proxy_url].present?
      easy.proxy_port = options[:proxy_port] if options[:proxy_port].present?
      if options[:proxy_tunnel].present? && options[:proxy_tunnel]
        easy.proxy_tunnel = true
        easy.proxy_type = options[:proxy_type]
      end
      easy.perform
      
      doc = Nokogiri::HTML(easy.body_str)
      
      easy.close
            
      doc.css(".tnt-tracking-history tr")
      
      success = true
      
      status_description = doc.css('dd.tnt-item-status').text
      
      status = status_description.downcase.to_sym
      if status_description =~ /ready.*delivery/i
        status = :out_for_delivery
      end
      if status_description =~ /item number isn't recognised/i
        status = :not_recognized
        success = false
      end


      rows = doc.css(".tnt-tracking-history tbody tr")
      
      shipment_events = []
      
      rows.each do |activity|
        description = activity.css("td")[2].text
        time_str = "#{activity.css("td")[0].text} #{activity.css("td")[1].text} GMT"
        case activity.css("td")[0].text.length
        when 8
          zoneless_time = DateTime.strptime(time_str, DATE_PARSER_STR)
        when 11
          zoneless_time = DateTime.strptime(time_str, DATE_PARSER_STR_2)
        end
        location = activity.css("td")[3].text
        p "#{description}, #{zoneless_time}, #{location}"
        shipment_events << ShipmentEvent.new(description, zoneless_time, location)
      end

      shipment_events = shipment_events.sort_by(&:time)
      
      if status == :delivered
        actual_delivery_date = shipment_events.last.time
      end
      
      TrackingResponse.new(success, status_description, {success: success},
                           :carrier => @@name,
                           :status => status,
                           :status_description => status_description,
                           :scheduled_delivery_date => scheduled_delivery_date,
                           :actual_delivery_date => actual_delivery_date,
                           :shipment_events => shipment_events,
                           :delivered => delivered,
                           :tracking_number => tracking_number)
      
    end
  end
end