# frozen_string_literal: true

module ModelConductor
  # Patch bgp-policy data to bgp-proc node
  class ModelPatcher
    # alias: node attribute key
    NODE_ATTR_KEY = 'mddo-topology:bgp-proc-node-attributes'
    # alias: node tp key
    NODE_TP_KEY = 'ietf-network-topology:termination-point'
    # alias: tp attr key
    TP_ATTR_KEY = 'mddo-topology:bgp-proc-termination-point-attributes'

    # @param [Hash] topology_data RFC8345 topology data (all layers)
    def initialize(topology_data)
      @topology = topology_data
      @networks = topology_data['ietf-network:networks']['network'] # alias
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

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

        # patch for term-points
        if node_patch.key?(NODE_TP_KEY)
          tp_patch_result = patch_term_points(target_node, node_patch[NODE_TP_KEY])
          return tp_patch_result if tp_patch_result[:error] >= 500
        end

        # no patch (for node)
        next unless node_patch.key?(NODE_ATTR_KEY)

        # Patch node
        # NOTE: replace(overwrite) each policy
        node_patch[NODE_ATTR_KEY].each_key do |patch_attr_key|
          unless target_node[NODE_ATTR_KEY].key?(patch_attr_key)
            logger.error "Attr key mismatch:#{patch_attr_key}: #{target_node['node-id']}"
            next
          end

          target_node[NODE_ATTR_KEY][patch_attr_key] = node_patch[NODE_ATTR_KEY][patch_attr_key]
        end
      end

      @topology
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    private

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength

    # @param [Hash] target_node Node to patch (RFC8345 hash)
    # @param [Array<Hash>] tp_patches Patch data (RFC8345-LIKE hash)
    # @return [Hash] error (no error if nil)
    def patch_term_points(target_node, tp_patches)
      tp_patches.each do |tp_patch|
        target_tp = target_node[NODE_TP_KEY].find { |tp| tp['tp-id'] == tp_patch['tp-id'] }
        message = "TP:#{tp_patch['tp-id']} in Node:#{tp_patch['node-id']} is not found"
        return { error: 500, message: } if target_tp.nil?

        # no patch (for term-point)
        next unless tp_patch.key?(TP_ATTR_KEY)

        # Patch term-point
        # NOTE: replace(overwrite) each policy
        tp_patch[TP_ATTR_KEY].each_key do |patch_attr_key|
          unless target_tp[TP_ATTR_KEY].key?(patch_attr_key)
            logger.error "Attr key mismatch:#{patch_attr_key}: #{target_node['node-id']}[#{target_tp['tp-id']}]"
            next
          end

          target_tp[TP_ATTR_KEY][patch_attr_key] = tp_patch[TP_ATTR_KEY][patch_attr_key]
        end
      end
      { error: 0, message: 'finish tp patch' }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
