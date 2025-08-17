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
        network, snapshot, command, command_args = %i[network snapshot command args].map { |key| params[key] }
        # NOTE: command_args and topology data must be original namespace data
        error!("snapshot:#{snapshot} is not original namespace", 500) unless snapshot =~ /original*/

        topology_data = rest_api.fetch_topology_data(network, snapshot)
        ns_convert_table = rest_api.fetch_ns_convert_table(network)
        commander = TopologyOpsCommander.new(command, command_args, topology_data, ns_convert_table)

        # response
        commander.answer
      end
    end
  end
end
