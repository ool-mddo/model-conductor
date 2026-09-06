# frozen_string_literal: true

module ModelConductor
  # Patch firewall policy data to layer3 node
  class FirewallPolicyPatcher
    # @param [Hash] topology_data RFC8345 topology data (all layers)
    def initialize(topology_data)
      @topology = topology_data
      @networks = topology_data['ietf-network:networks']['network'] # alias
    end

    # @param [String] layer_name Target layer name to patch (== 'bgp_proc')
    # @param [Array] node_patches Patch data to node (RFC83450-based diff data)
    # @return [Hash] Error or Patched topology data
    #   Error data : { error: <http error status code>, message: <string> }
    def patch_nodes(layer_name, node_patches)
      warn "not implemented yet. layer_name=#{layer_name}"
      warn node_patches
      @topology
    end
  end
end
