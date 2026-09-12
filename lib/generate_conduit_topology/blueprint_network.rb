# frozen_string_literal: true

module ModelConductor
  # Group of original layer3 nodes collapsed into one conduit node.
  # For :firewall type groups, all original nodes are preserved separately.
  # For :router type groups, all original nodes are collapsed into one representative.
  NodeGroup = Struct.new(:conduit_name, :original_node_names, keyword_init: true)

  # Parses one blueprint network and resolves node supports to original layer3 node names.
  # Handles transitive resolution: zoom1 → zoom0 → layer3.
  class BlueprintNetwork
    LAYER3_NETWORK_ID = 'layer3'

    attr_reader :name

    # @param network_data [Hash] one network object from blueprint topology JSON
    # @param all_blueprint_networks [Array<Hash>] all networks in blueprint (for transitive resolution)
    def initialize(network_data, all_blueprint_networks)
      @name = network_data['network-id']
      @raw_nodes = network_data['node'] || []
      @blueprint_by_name = all_blueprint_networks.to_h { |nw| [nw['network-id'], nw] }
    end

    # @return [Array<NodeGroup>]
    def node_groups
      @node_groups ||= @raw_nodes.map do |node_data|
        layer3_names = resolve_to_layer3(node_data['supports'] || [])
        NodeGroup.new(conduit_name: node_data['node-id'], original_node_names: layer3_names)
      end
    end

    private

    # Recursively resolve supports until we reach layer3 node names.
    # @param supports [Array<Hash>] list of {network-ref, node-ref} entries
    # @return [Array<String>] layer3 node names (de-duplicated)
    # @raise [RuntimeError] if any support reference cannot be resolved
    def resolve_to_layer3(supports)
      supports.flat_map do |s|
        ref_nw = s['network-ref']
        ref_node = s['node-ref']

        if ref_nw.nil? || ref_nw == LAYER3_NETWORK_ID
          [ref_node]
        else
          intermediate_nw = @blueprint_by_name[ref_nw]
          raise "Cannot resolve support: blueprint network '#{ref_nw}' not found" if intermediate_nw.nil?

          intermediate_node = (intermediate_nw['node'] || []).find { |n| n['node-id'] == ref_node }
          raise "Cannot resolve support: node '#{ref_node}' not found in blueprint network '#{ref_nw}'" if intermediate_node.nil?

          resolve_to_layer3(intermediate_node['supports'] || [])
        end
      end.uniq
    end
  end
end
