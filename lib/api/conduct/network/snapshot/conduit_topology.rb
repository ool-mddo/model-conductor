# frozen_string_literal: true

require 'lib/api/rest_api_base'
require 'lib/generate_conduit_topology/conduit_topology_generator'

module ModelConductor
  module ApiRoute
    # API to generate conduit topologies
    class ConduitTopology < RestApiBase
      namespace 'conduit_topology' do
        desc 'Generate and save conduit topologies'
        params do
          requires :usecase, type: String, desc: 'Usecase name'
          requires :blueprint_snapshot, type: String, desc: 'Blueprint snapshot name'
        end
        post do
          network, snapshot = %i[network snapshot].map { |key| params[key] }
          usecase, blueprint_snapshot = %i[usecase blueprint_snapshot].map { |key| params[key] }

          # Delete existing conduit snapshots before generating new ones
          existing = rest_api.fetch_snapshot_list(network, "#{snapshot}_conduit")
          existing&.each { |ss| rest_api.delete_snapshot(network, ss) }

          # Fetch blueprint topology
          blueprint_topology = rest_api.fetch_blueprint_topology_data(usecase, network, blueprint_snapshot)
          error!('blueprint topology not found', 404) if blueprint_topology.nil?

          # Fetch original topology
          original_topology = rest_api.fetch_topology_data(network, snapshot, upper_layer3: false)
          error!('original topology not found', 404) if original_topology.nil?

          # Generate conduit topologies
          generator = ConduitTopologyGenerator.new(original_topology, blueprint_topology)
          conduit_list = generator.generate

          # Save each conduit topology and return snapshot list
          conduit_list.map do |conduit|
            conduit_ss = "#{snapshot}_conduit#{conduit[:index]}"
            rest_api.post_topology_data(network, conduit_ss, conduit[:topology])
            { snapshot: conduit_ss }
          end
        end
      end
    end
  end
end
