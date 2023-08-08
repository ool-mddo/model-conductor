# frozen_string_literal: true

require 'grape'

module ModelConductor
  module ApiRoute
    # api splice_topology
    class SpliceTopology < Grape::API
      desc 'Post external bgp topology data and splice it to (internal) topology data'
      params do
        requires :ext_topology_data, type: Hash, desc: 'External topology data to splice'
        optional :overwrite, type: Boolean, desc: 'Overwrite to topology data', default: true
      end
      post 'splice_topology' do
        keys = %i[network snapshot ext_topology_data overwrite]
        network, snapshot, ext_topology_data, overwrite = keys.map { |key| params[key] }

        # splice external topology data into (internal = generated from configs) topology data
        spliced_topology_data = rest_api.post_splice_topology(network, snapshot, ext_topology_data)
        # overwrite it to topology data
        spliced_topology_data = rest_api.post_topology_data(network, snapshot, spliced_topology_data) if overwrite

        # response
        spliced_topology_data
      end
    end
  end
end
