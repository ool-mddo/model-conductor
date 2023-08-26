# frozen_string_literal: true

require 'grape'
require 'lib/splice_topology/topology_splicer'

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
        network, snapshot, overwrite = %i[network snapshot overwrite].map { |key| params[key] }

        ext_topology = params[:ext_topology_data]
        int_topology = rest_api.fetch_topology_data(network, snapshot)
        splicer = TopologySplicer.new(int_topology, ext_topology)
        splicer.splice!
        spliced_topology = splicer.to_data

        # response (spliced topology data: RFC8345 Hash)
        overwrite ? rest_api.post_topology_data(network, snapshot, spliced_topology) : spliced_topology
      end
    end
  end
end
