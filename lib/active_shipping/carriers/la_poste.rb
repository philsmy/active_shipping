# https://www.gls-italy.com/?option=com_gls&view=track_e_trace&mode=search&numero_spedizione=M1036694014&tipo_codice=nazionale
require 'curl'

module ActiveShipping
  class LaPoste < Carrier
    cattr_reader :name
    @@name = "La Poste"
    
  end
end