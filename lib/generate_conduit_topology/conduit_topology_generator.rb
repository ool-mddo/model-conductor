# frozen_string_literal: true

require_relative 'blueprint_network'
require_relative 'layer3_conduit_builder'
require_relative 'ospf_conduit_builder'

module ModelConductor
  # Orchestrates conduit (土管化) topology generation.
  # For each blueprint network, builds one complete conduit topology snapshot containing
  # conduit layer3 and conduit ospf_area networks derived from the original topology.
  class ConduitTopologyGenerator
    OSPF_AREA_PATTERN = /\Aospf_area/

    # @param original_topology [Hash] original topology data (RFC8345 JSON, not symbolized)
    # @param blueprint_topology [Hash] blueprint topology data (not symbolized)
    def initialize(original_topology, blueprint_topology)
      @original_topology = original_topology
      @blueprint_topology = blueprint_topology
    end

    # @return [Array<Hash>] list of {index: Integer, topology: Hash}
    def generate
      all_blueprint_nws = @blueprint_topology.dig('ietf-network:networks', 'network') || []
      all_blueprint_nws.each_with_index.map do |bp_nw_data, idx|
        blueprint_nw = BlueprintNetwork.new(bp_nw_data, all_blueprint_nws)
        { index: idx + 1, topology: build_conduit_topology(blueprint_nw) }
      end
    end

    private

    def original_networks
      @original_topology.dig('ietf-network:networks', 'network') || []
    end

    def find_original_network(network_id)
      original_networks.find { |nw| nw['network-id'] == network_id }
    end

    # Build one complete conduit topology for a given blueprint network
    def build_conduit_topology(blueprint_nw)
      orig_layer3 = find_original_network('layer3')
      raise 'Original layer3 network not found' if orig_layer3.nil?

      conduit_layer3, node_mapping, tp_mapping = Layer3ConduitBuilder.new(orig_layer3, blueprint_nw).build
      conduit_ospf_networks = build_conduit_ospf_networks(node_mapping, tp_mapping)
      sorted_ospf = sort_ospf_networks(conduit_ospf_networks)
      { 'ietf-network:networks' => { 'network' => sorted_ospf + [conduit_layer3] } }
    end

    def build_conduit_ospf_networks(node_mapping, tp_mapping)
      ospf_networks = original_networks.select { |nw| nw['network-id'].match?(OSPF_AREA_PATTERN) }
      router_ids = original_router_ids(ospf_networks)
      ospf_networks.map { |orig_ospf| OspfConduitBuilder.new(orig_ospf, node_mapping, tp_mapping, router_ids).build }
    end

    # @return [Hash] { original_node_name => ospf router-id } (ospf_proc nodes in all ospf areas)
    def original_router_ids(ospf_networks)
      ospf_networks.flat_map { |nw| nw['node'] || [] }.each_with_object({}) do |node, ids|
        router_id = node.dig('mddo-topology:ospf-area-node-attributes', 'router-id')
        ids[node['node-id']] ||= router_id unless router_id.nil? || router_id.empty?
      end
    end

    # Order: ospf area ascending (ospf0, ospf10, ...) then layer3, same as the original topology.
    # NOTE: playbook templates may depend on the first ospf area (backbone) listing all routers.
    def sort_ospf_networks(conduit_ospf_networks)
      conduit_ospf_networks.sort_by { |nw| nw['network-id'][/\d+/].to_i }
    end
  end
end
