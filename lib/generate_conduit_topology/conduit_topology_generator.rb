# frozen_string_literal: true

module ModelConductor
  # Generate conduit (abstracted/simplified) topologies from original and blueprint topologies
  class ConduitTopologyGenerator
    # @param [Hash] original_topology Original topology data (RFC8345 JSON)
    # @param [Hash] blueprint_topology Blueprint topology data defining target abstraction
    def initialize(original_topology, blueprint_topology)
      @original_topology = original_topology
      @blueprint_topology = blueprint_topology
    end

    # @return [Array<Hash>] list of {index: Integer, topology: Hash}
    def generate
      # NOTE: conduit logic is not yet implemented (pass-through stub)
      # Returns one conduit per network defined in blueprint topology.
      # Internal logic will be replaced with actual conduit transformation later.
      (1..conduit_count).map do |i|
        { index: i, topology: @original_topology }
      end
    end

    private

    def conduit_count
      networks = @blueprint_topology.dig('ietf-network:networks', 'network') || []
      [networks.length, 1].max
    end
  end
end
