require 'curl'

module ActiveShipping
  class RoyalMail < Carrier
    cattr_reader :name
    @@name = "Royal Mail"

    LIVE_TRACKING_URL = 'https://www.royalmail.com/business/track-your-item?trackNumber=%s&op='

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
    
    def parse_tracking_response(tracking_number, options)
      sleep 2;
      scheduled_delivery_date, actual_delivery_date = nil
      delivered = false
      doc = Nokogiri::HTML(Curl::Easy.perform(LIVE_TRACKING_URL % tracking_number){|easy| easy.timeout=10}.body_str)
            
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
        zoneless_time = Time.parse(time_str)
        location = activity.css("td")[3].text
        p "#{description}, #{zoneless_time}, #{location}"
        shipment_events << ShipmentEvent.new(description, zoneless_time, location, nil, nil)
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