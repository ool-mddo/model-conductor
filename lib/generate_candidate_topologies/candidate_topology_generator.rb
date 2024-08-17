# frozen_string_literal: true

module ModelConductor
  # candidate topology generator
  class CandidateTopologyGenerator
    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    def initialize(network, snapshot)
      @network = network
      @snapshot = snapshot
    end

    # @param [Integer] candidate_index candidate index
    # @return [Netomox::Topology::Networks]
    def generate_candidate_topologies(candidate_index)
      # always reload
      base_topology = read_base_topology

      target_network = base_topology.find_network('bgp_proc')
      # TODO: target node be given by usecase parameters
      #   & convert it bgp_proc node id (edge-tk01 -> 192.168.255.5)
      l3_node_name = 'edge-tk01'
      bgp_proc_node_name = '192.168.255.5'
      target_node = target_network.find_node_by_name(bgp_proc_node_name)
      node_info = "layer3:#{l3_node_name}/bgp_proc:#{bgp_proc_node_name}"
      if target_node.nil?
        ModelConductor.logger.error "node:#{node_info} not found in base_topology in network:#{target_network.name}"
        return base_topology
      end

      # TODO: ASN be given by usecase parameters
      target_asn = 65_550
      target_prefix_set = target_node.attribute.prefix_sets.find do |pfx_set|
        pfx_set.name =~ /as#{target_asn}-advd-ipv4/
      end

      if target_prefix_set.nil? || target_prefix_set.prefixes.nil? || target_prefix_set.prefixes.empty?
        ModelConductor.logger.error "node:#{node_info} prefix-set is empty?"
        return base_topology
      end

      if target_prefix_set.prefixes.at(candidate_index).nil?
        ModelConductor.logger.warn("Can't generate candidate pattern over candidate_#{candidate_index}")
        return base_topology
      end

      # update configs
      target_prefix_set.prefixes = target_prefix_set.prefixes.dup
      target_prefix_set.prefixes.delete_at(candidate_index - 1)

      base_topology
    end

    private

    # @return [Netomox::Topology::Networks] topology object
    def read_base_topology
      ModelConductor.rest_api.fetch_topology_object(@network, @snapshot)
    end
  end
end
