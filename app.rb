# frozen_string_literal: true

require 'fileutils'
require 'grape'
require 'json'
require_relative 'lib/topology_generator'

# model-conductor REST API definition
class TopologyConductorRestApi < Grape::API
  format :json

  helpers do
    def logger
      TopologyConductorRestApi.logger
    end
  end

  namespace 'model-conductor' do
    desc 'Post (generate and register) topology data from configs'
    params do
      requires :model_info, type: Array, desc: 'List of model-info'
      optional :phy_ss_only, type: Boolean, desc: 'Physical snapshot only'
      optional :off_node, type: String, desc: 'Node name to down'
      optional :off_intf_re, type: String, desc: 'Interface name to down (regexp)'
    end
    # receive model_info
    post 'generate-topology' do
      logger.debug "[model-conductor/generate-topology] params: #{params}"
      # scenario
      topology_generator = ModelConductor::TopologyGenerator.new(logger)
      snapshot_dict = topology_generator.generate_snapshot_dict(params['model_info'], params)
      netoviz_index_data = topology_generator.convert_query_to_topology(snapshot_dict)
      topology_generator.save_netoviz_index(netoviz_index_data)
      {
        method: 'POST',
        path: '/model-conductor/generate-topology',
        snapshot_dict:
      }
    end
  end
end
