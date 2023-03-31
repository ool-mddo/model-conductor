# frozen_string_literal: true

require 'grape'

module ModelConductor
  module ApiRoute
    # api namespace convert
    class NsConvert < Grape::API
      desc 'Get converted topology and post it as other topology'
      params do
        requires :src_ss, type: String, desc: 'Source snapshot name'
        requires :dst_ss, type: String, desc: 'Destination snapshot name'
        requires :table_origin, type: String, desc: 'Origin snapshot name to create convert table'
      end
      post 'ns_convert/:src_ss/:dst_ss' do
        network, src_ss, dst_ss, origin_ss = %i[network src_ss dst_ss table_origin].map { |key| params[key] }

        rest_api.init_ns_convert_table(network, origin_ss)
        converted_topology_data = rest_api.fetch_converted_topology_data(network, src_ss)
        rest_api.post_topology_data(network, dst_ss, converted_topology_data)
        # response
        {}
      end
    end
  end
end
