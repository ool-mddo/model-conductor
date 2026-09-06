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

    # @param [String] layer_name Target layer name to patch (== 'bgp_proc')
    # @param [Array] node_patches Patch data to node (RFC83450-based diff data)
    # @return [Hash] Error or Patched topology data
    #   Error data : { error: <http error status code>, message: <string> }
    def patch_nodes(layer_name, node_patches)
      layer = @networks.find { |nw| nw['network-id'] == layer_name }
      if layer.nil?
        message = "Layer:#{layer_name} is not found in topology"
        ModelConductor.logger.error message
        return { error: 500, message: }
      end

      node_patches.each do |node_patch|
        target_node = layer['node'].find { |node| node['node-id'] == node_patch['node-id'] }
        if target_node.nil?
          message = "Node:#{node_patch['node-id']} is not found in #{layer_name}"
          ModelConductor.logger.error message
        end

        # patch node
        #   node_patch ~ {
        #     [ { "node-id": node-name, "flag": ["firewall"], "l3-node-attributes": { "firewall": {...}} }, ...]
        #   }

        # merge "l3-node-attributes" and "firewall"
        node_patch[NODE_ATTR_KEY].each_key do |patch_attr_key|
          if target_node[NODE_ATTR_KEY].key?(patch_attr_key)
            message = "Attr key overwrite:#{patch_attr_key}: #{target_node['node-id']}"
            ModelConductor.logger.warn message
          end
          target_node[NODE_ATTR_KEY][patch_attr_key] = node_patch[NODE_ATTR_KEY][patch_attr_key]
        end
        # merge "flag"
        target_node['flag'] = [] if target_node['flag'].nil?
        target_node['flag'] = target_node['flag'] | node_patch['flag']
      end

      @topology
    end
  end
end
