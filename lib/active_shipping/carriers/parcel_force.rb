module ActiveShipping
  class ParcelForce < Carrier
    cattr_reader :name
    @@name = "ParcelForce"

    LIVE_TRACKING_URL = 'http://tracking.parcelforce.net/pod/SNP_POD_det.php?AISIE_SEARCH=0&CAR=068&CARCODEDIVA=&CAR_FILTRE=&CLIENT=Pfw&COUNTRYCODE=GB&DWKEYNUM=913509208&DoResearch=false&FORMTARGET=SNP_mod&FROM=IN&HOME_DISPLAY=complete&IMAGE_COURANTE=1&INDEX_FOCUS=&LOGIN=253a56592b2f5c3d4210253a56592b2f5c3d427e273b54&MMITYPE=2&NAME=szShippingNumber%253DConsignment%2Bor%2Bparcel%2Bnumber%253A%253B&NOBACKBTN=0&NOCRITARYZONE=0&NOEXTRACTION=1&NOIMGBTN=0&NORIGHTBOX=1&ORDER=dtGuaranteedDeliveryDate&PAGE=SNP_POD_pos.php&PN_S=0&PN_T=1&PN_T_ALL=1&SENS=ASC&SORT_SUB=0&TICKET=7566080f607605710461&TYPERECH=0&URLCONF=0&szBarcodePage_s=&szCodeTournee=&szRequestType=&szShippingNumber='

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
      scheduled_delivery_date, actual_delivery_date = nil
      delivered = false
      doc = Nokogiri::HTML(open("#{LIVE_TRACKING_URL}#{tracking_number}"))
      
      doc.css("table.SNP_POD_det tr")
      
      success = true
      
      row = rows.reject {|r| (r.text =~ /status/i) != 1 }.first
      
      status_description = row.css(".SNP_POD_det_Dat").text
      
      status = status_description.downcase.to_sym
      if status_description =~ /out.*delivery/i
        status = :out_for_delivery
      end
      if status_description =~ /item number isn't recognised/i
        status = :not_recognized
        success = false
      end


      rows = doc.css(".tnt-tracking-history tbody tr")
      
      shipment_events = []
      
      rows.each do |activity|
        description = status_description
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