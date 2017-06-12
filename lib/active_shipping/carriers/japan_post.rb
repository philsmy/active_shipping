require 'curl'

module ActiveShipping
  class JapanPost < Carrier
    cattr_reader :name
    @@name = "Japan Post"

    LIVE_TRACKING_URL = 'http://tracking.post.japanpost.jp/services/sp/srv/search/?requestNo1=%s&search=Beginning&locale=en'
    DATE_PARSER_STR = "%b %d %H:%M %Z"

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
      # sleep 2;
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
            
      doc.css("div#smt-tracking dt")
      
      success = true
      
      status_description = doc.css('div#smt-tracking dt').last.text
      
      status = status_description.downcase.to_sym
      if status_description =~ /final delivery/i
        status = :delivered
        delivered = true
      end
      if status_description =~ /processing/i
        status = :in_transit
      end
      # if status_description =~ /item number isn't recognised/i
      #   status = :not_recognized
      #   success = false
      # end


      rows = doc.css("div#smt-tracking .tracking_form").children
      
      shipment_events = []
      
      rows.each_with_index do |activity, i|
        if activity.children.size == 1
          description = activity.text.squish
          detail = rows[i+2]
          
          time_str = detail.children[0].text.squish + " PST"
          actual_time = DateTime.strptime(time_str, DATE_PARSER_STR)
          p actual_time
          location = detail.children[5].text.squish

          p "#{description}, #{zoneless_time}, #{location}"
          # shipment_events << ShipmentEvent.new(description, zoneless_time, location)
        end

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