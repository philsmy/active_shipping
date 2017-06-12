# http://track.kuronekoyamato.co.jp/english/tracking
# timeid=GocanH5IIY7LLE5X37xNJ59onTNw8AoV
# number00=1
# sch=&#160;&#160;&#160;&#160;Track&#160;&#160;&#160;&#160;
# number01=443695344411
# number02
# number03
# number04
# number05
# number06
# number07
# number08
# number09
# number10


require 'curl'

module ActiveShipping
  class Yamato < Carrier
    cattr_reader :name
    @@name = "Yamato"

    LIVE_TRACKING_URL = 'http://track.kuronekoyamato.co.jp/english/tracking'
    DATE_PARSER_STR = "%m/%d %H:%M %Z"
    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.11; rv:53.0) Gecko/20100101 Firefox/53.0"

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
      
      easy = Curl::Easy.new(LIVE_TRACKING_URL))
      easy.headers["User-Agent"] = USER_AGENT
      easy.headers["Referer"] = "http://track.kuronekoyamato.co.jp/english/tracking"
      easy.timeout = options[:timeout].present? ? options[:timeout] : 20
      easy.proxy_url = options[:proxy_url] if options[:proxy_url].present?
      easy.proxy_port = options[:proxy_port] if options[:proxy_port].present?
      if options[:proxy_tunnel].present? && options[:proxy_tunnel]
        easy.proxy_tunnel = true
        easy.proxy_type = options[:proxy_type]
      end
      # easy.perform
      easy.http_post(Curl::PostField.content("timeid","GocanH5IIY7LLE5X37xNJ59onTNw8AoV"),
                                    Curl::PostField.content("sch", "&#160;&#160;&#160;&#160;Track&#160;&#160;&#160;&#160;"),
                                     Curl::PostField.content('number00', '1'),
                                     Curl::PostField.content('number01', tracking_number))
      
      doc = Nokogiri::HTML(easy.body_str)
      
      easy.close

      success = true
      
      status_description = doc.css('table.meisai tr:last td')[1].text.squish
      
      status = status_description.downcase.to_sym
      if status_description =~ /delivered/i
        status = :delivered
        delivered = true
      end
      if status_description =~ /transit/i
        status = :in_transit
      end
      # if status_description =~ /item number isn't recognised/i
      #   status = :not_recognized
      #   success = false
      # end


      rows = doc.css("table.meisai tr:not(:first-child)")
      
      shipment_events = []
      
      rows.each_with_index do |activity, i|
        description = activity.css("td")[1].text.squish
        detail = rows[i+2]
        
        time_str = "#{activity.css("td")[2].text.squish} #{activity.css("td")[3].text.squish} JST"
        actual_time = DateTime.strptime(time_str, DATE_PARSER_STR)
        # p actual_time
        location = ""

        p "#{description}, #{actual_time}, #{location}"
        # shipment_events << ShipmentEvent.new(description, actual_time, location)
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