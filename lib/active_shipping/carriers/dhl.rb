require 'curl'

module ActiveShipping
  class Dhl < Carrier
    cattr_reader :name
    @@name = "Dhl"

    LIVE_TRACKING_URL = 'http://webtrack.dhlglobalmail.com/?trackingnumber=%s'

    def find_tracking_info(tracking_number, options = {})
      options = @options.merge(options)
      parse_tracking_response(tracking_number, options)
    end

    def parse_tracking_response(tracking_number, options)
      scheduled_delivery_date, actual_delivery_date = nil
      delivered = false
      doc = Nokogiri::HTML(Curl::Easy.perform(LIVE_TRACKING_URL % tracking_number).body_str)

      shipment_events = []

      if !doc.css("div.alert-danger").empty?
        success = false
        status = :not_recognized
      else
        latest_datetime_str = doc.css("div.card .status-info p").children.first.text.strip.gsub(",", "").gsub("PT", "PST")
        DateTime.strptime(latest_datetime_str, "%a %B %d %Y at %l:%M %p %Z")
        status_description = doc.css("div.card h2").text.strip
        status = status_description.downcase.to_sym
        success = true

        status_description = doc.css("div.card em").text.strip
      

        rows = doc.css("ol.timeline li")
        timeline_date = nil

        rows.each do |row|
          case row["class"]
          when /timeline-date/
            timeline_date = Date.parse(row.text.strip)
            p timeline_date
          when /timeline-event/
            event_time_str = row.css(".timeline-time").text.strip.gsub("PT", "PST")
            date_time = DateTime.strptime("#{timeline_date.to_s} #{event_time_str}", "%F %l:%M%p %Z")
            location = row.css(".timeline-location")[0].text.strip rescue ''
            event_status = row.css(".timeline-description").text.strip
          
            p "#{timeline_date} #{event_time_str}: #{event_status}"

            shipment_events << ActiveShipping::ShipmentEvent.new(event_status, date_time, location, nil, nil)
          end
        end

        if status == :delivered
          actual_delivery_date = shipment_events.last.time
        end
      end
      
      
      ActiveShipping::TrackingResponse.new(success, status_description, {success: success},
                           :carrier => "Dhl",
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