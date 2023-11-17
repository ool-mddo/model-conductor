# frozen_string_literal: true

module ModelConductor
  # Patch bgp-policy data to bgp-proc node
  class ModelPatcher
    # alias: node attribute key
    NODE_ATTR_KEY = 'mddo-topology:bgp-proc-node-attributes'

    # @param [Hash] topology_data RFC8345 topology data (all layers)
    def initialize(topology_data)
      @topology = topology_data
      @networks = topology_data['ietf-network:networks']['network'] # alias
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

    # @param [String] layer_name Target layer name to patch (== 'bgp_proc')
    # @param [Array] node_patches Patch data to node (RFC83450-based diff data)
    # @return [Hash] Error or Patched topology data
    #   Error data : { error: <http error status code>, message: <string> }
    def patch_nodes(layer_name, node_patches)
      layer = @networks.find { |nw| nw['network-id'] == layer_name }
      message = "Layer:#{layer_name} is not found in topology"
      return { error: 500, message: } if layer.nil?

      node_patches.each do |node_patch|
        target_node = layer['node'].find { |node| node['node-id'] == node_patch['node-id'] }
        message = "Node:#{node_patch['node-id']} is not found in #{layer_name}"
        return { error: 500, message: } if target_node.nil?

        # NOTE: concatenate policies
        %w[policy prefix-set as-path-set community-set].each do |policy_attr_key|
          next unless node_patch[NODE_ATTR_KEY].key?(policy_attr_key)

          target_node[NODE_ATTR_KEY][policy_attr_key] = node_patch[NODE_ATTR_KEY][policy_attr_key]
        end
      end

      @topology
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
  end
end
