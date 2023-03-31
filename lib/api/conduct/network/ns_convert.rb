# frozen_string_literal: true

require 'grape'

module ModelConductor
  module ApiRoute
    # api namespace convert
    class NsConvert < Grape::API
      helpers do
        # @param [String] network Network name
        # @param [String] snapshot Snapshot name
        # @param [String] comment Comment for error message
        # @return [void]
        def exist_snapshot!(network, snapshot, comment)
          snapshot_data = rest_api.fetch_topology_data(network, snapshot)
          error!("#{comment}:#{snapshot} in #{network} is not found", 404) if snapshot_data.nil?
        end

        # @param [String] network Network name
        # @return [void]
        def exist_ns_convert_table!(network)
          table = rest_api.fetch_ns_convert_table(network)
          error!("Namespace convert table of network:#{network} is not found", 404) if table.nil?
        end
      end

      desc 'Get converted topology and post it as other topology'
      params do
        requires :src_ss, type: String, desc: 'Source snapshot name'
        requires :dst_ss, type: String, desc: 'Destination snapshot name'
        optional :table_origin, type: String, desc: 'Origin snapshot name to create convert table'
      end
      post 'ns_convert/:src_ss/:dst_ss' do
        network, src_ss, dst_ss, origin_ss = %i[network src_ss dst_ss table_origin].map { |key| params[key] }

        # check source snapshot existence
        exist_snapshot!(network, src_ss, 'Source snapshot')

        if params.key?(:table_origin)
          # check source snapshot existence
          exist_snapshot!(network, origin_ss, 'Table origin snapshot')

          # force update (initialize) convert table when table_origin snapshot is specified
          logger.info "Initialize ns convert table of network:#{network} with snapshot:#{origin_ss}"
          rest_api.post_init_ns_convert_table(network, origin_ss)
        else
          # check namespace convert table existence
          exist_ns_convert_table!(network)
        end

        converted_topology_data = rest_api.fetch_converted_topology_data(network, src_ss)
        rest_api.post_topology_data(network, dst_ss, converted_topology_data)
        # response
        {}
      end
    end
  end
end
