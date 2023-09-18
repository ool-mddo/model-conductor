# frozen_string_literal: true

require 'grape'
require 'lib/generate_topology/topology_generator'
require_relative 'topology/layer'

module ModelConductor
  module ApiRoute
    # api topology
    class Topology < Grape::API
      namespace 'topology' do
        desc 'Post (generate and register) topology data from configs'
        params do
          requires :label, type: String, desc: 'Label of the network/snapshot'
          optional :phy_ss_only, type: Boolean, desc: 'Physical snapshot only', default: false
          optional :use_parallel, type: Boolean, desc: 'Use parallel', default: false
          optional :off_node, type: String, desc: 'Node name to down'
          optional :off_intf_re, type: String, desc: 'Interface name to down (regexp)'
        end
        post do
          network, snapshot, label, use_parallel = %i[network snapshot label use_parallel].map { |key| params[key] }
          # scenario
          topology_generator = TopologyGenerator.new
          snapshot_dict = topology_generator.generate_snapshot_dict(network, snapshot, label, params)
          topology_generator.convert_config_to_query(snapshot_dict)
          topology_generator.convert_query_to_topology(snapshot_dict, use_parallel:)

          # response
          snapshot_dict
        end

        # mount resources
        mount ApiRoute::Layer
      end
    end
  end
end
