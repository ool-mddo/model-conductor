# frozen_string_literal: true

module ModelConductor
  # Patch firewall policy data to layer3 node
  class FirewallPolicyPatcher
    # alias: node attribute key
    NODE_ATTR_KEY = 'mddo-topology:l3-node-attributes'

    # @param [Hash] topology_data RFC8345 topology data (all layers)
    def initialize(topology_data)
      @topology = topology_data
      @networks = topology_data['ietf-network:networks']['network'] # alias
    end

    # @param [String] layer_name Target layer name to patch
    # @param [Array] node_patches Patch data to node (RFC8345-based diff data)
    # @return [Hash] Error or Patched topology data
    #   Error data : { error: <http error status code>, message: <string> }
    def patch_nodes(layer_name, node_patches)
      layer = @networks.find { |nw| nw['network-id'] == layer_name }
      if layer.nil?
        message = "Layer:#{layer_name} is not found in topology"
        ModelConductor.logger.error message
        return { error: 500, message: }
      end

      node_patches.each { |node_patch| apply_node_patch(layer, layer_name, node_patch) }
      @topology
    end

    private

    # @param [Hash] layer Layer data
    # @param [String] layer_name Layer name (for error message)
    # @param [Hash] node_patch Patch data for a single node
    def apply_node_patch(layer, layer_name, node_patch)
      target_node = layer['node'].find { |node| node['node-id'] == node_patch['node-id'] }
      if target_node.nil?
        ModelConductor.logger.error "Node:#{node_patch['node-id']} is not found in #{layer_name}"
        return
      end

      apply_node_attrs(target_node, node_patch)
      apply_node_flags(target_node, node_patch)
    end

    # @param [Hash] target_node Target node data
    # @param [Hash] node_patch Patch data
    def apply_node_attrs(target_node, node_patch)
      node_patch[NODE_ATTR_KEY].each_key do |patch_attr_key|
        if target_node[NODE_ATTR_KEY].key?(patch_attr_key)
          ModelConductor.logger.warn "Attr key overwrite:#{patch_attr_key}: #{target_node['node-id']}"
        end
        target_node[NODE_ATTR_KEY][patch_attr_key] = node_patch[NODE_ATTR_KEY][patch_attr_key]
      end
    end

    # @param [Hash] target_node Target node data
    # @param [Hash] node_patch Patch data
    def apply_node_flags(target_node, node_patch)
      target_node['flag'] ||= []
      target_node['flag'] |= node_patch['flag']
    end
  end
end
