# frozen_string_literal: true

require 'grape'
require 'lib/topology_ops/topology_ops_commander'

module ModelConductor
  module ApiRoute
    # api topology_ops
    class TopologyOps < Grape::API
      desc 'Post topology operation commands'
      params do
        requires :command, type: String, desc: 'Topology operation command'
        requires :args, type: Hash, desc: 'Topology operation arguments'
      end
      post 'topology_ops' do
        network, command, command_args = %i[network command args].map { |key| params[key] }
        # detect target prealloc-snapshot
        prealloc_snapshots = rest_api.fetch_snapshot_list(network, 'original_asis_preallocated')
        error!('original_asis_prealloc snapshot not found', 400) if prealloc_snapshots.empty?

        target_prealloc_ss = prealloc_snapshots.sort_by { |s| s[/\d+$/].to_i }.max
        warn "# target prealloc snapshot: #{target_prealloc_ss}"

        topology_data = rest_api.fetch_topology_data(network, target_prealloc_ss)
        ns_convert_table = rest_api.fetch_ns_convert_table(network)
        commander = TopologyOpsCommander.new(command, command_args, topology_data, ns_convert_table)

        # response
        commander.answer
      end
    end
  end
end
