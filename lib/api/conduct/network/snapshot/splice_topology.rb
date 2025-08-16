# frozen_string_literal: true

require 'grape'
require 'lib/splice_topology/topology_splicer'
require 'lib/splice_topology/layer3_empty_resource_splicer'

module ModelConductor
  module ApiRoute
    # api splice_topology
    class SpliceTopology < Grape::API
      desc 'Post external bgp topology data and splice it to (internal) topology data'
      params do
        optional :ext_topology_data, type: Hash, desc: 'External topology data to splice'
        optional :l3_empty_resources, type: Hash, desc: 'Layer3 empty resources data to splice'
        optional :overwrite, type: Boolean, desc: 'Overwrite to topology data', default: true
        at_least_one_of :ext_topology_data, :l3_empty_resources
      end
      post 'splice_topology' do
        network, snapshot, overwrite = %i[network snapshot overwrite].map { |key| params[key] }
        spliced_topology = nil

        if params.key?(:ext_topology_data)
          ext_topology = params[:ext_topology_data]
          int_topology = rest_api.fetch_topology_data(network, snapshot)
          splicer = TopologySplicer.new(int_topology, ext_topology)
          splicer.splice!
          spliced_topology = splicer.to_data
        end

        if params.key?(:l3_empty_resources)
          l3e_topology = params[:l3_empty_resources]
          topology = spliced_topology || rest_api.fetch_topology_data(network, snapshot)
          splicer = Layer3EmptyResourceSplicer.new(topology, l3e_topology)
          splicer.splice!
          spliced_topology = splicer.to_data
        end

        # response (spliced topology data: RFC8345 Hash)
        overwrite ? rest_api.post_topology_data(network, snapshot, spliced_topology) : spliced_topology
      end
    end
  end
end
