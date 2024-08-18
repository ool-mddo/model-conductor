# frozen_string_literal: true

require 'netomox'

module Netomox
  module Topology
    # patch for Network
    class Network
      # @param [String] nw_ref Supporting network name
      # @param [String] node_ref Supporting node name
      # @return [nil, Netomox::Topology::Node]
      def find_node_by_support(nw_ref, node_ref)
        @nodes.find do |node|
          node.supports.find do |support|
            support.ref_network == nw_ref && support.ref_node == node_ref
          end
        end
      end
    end

    # patch for prefix-set
    class MddoBgpPrefixSet
      # @return [Boolean]
      def empty?
        prefixes.nil? || prefixes.empty?
      end
    end
  end
end

module ModelConductor
  # candidate topology generator
  class CandidateTopologyGenerator
    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    def initialize(network, snapshot)
      @network = network
      @snapshot = snapshot
    end

    # rubocop:disable Metrics/MethodLength

    # @param [Integer] candidate_index candidate index
    # @return [nil, Netomox::Topology::Networks]
    def generate_candidate_topologies(candidate_index)
      # always reload
      base_topology = read_base_topology

      # TODO: src_asn and target node be given by usecase parameters
      #   & convert it bgp_proc node id (edge-tk01 -> 192.168.255.5)
      l3_node_name = 'edge-tk01'
      src_asn = 65_550

      result = pickup_prefix_set(base_topology, l3_node_name, src_asn)
      if result[:error]
        ModelConductor.logger.error result[:message]
        return nil
      end

      if result[:prefix_set].prefixes.at(candidate_index).nil?
        ModelConductor.logger.warn("Can't generate candidate pattern for candidate_#{candidate_index}")
        return nil
      end

      # update configs
      result[:prefix_set].prefixes.delete_at(candidate_index - 1)

      # return modified topology data as candidate_i
      base_topology
    end
    # rubocop:enable Metrics/MethodLength

    private

    # rubocop:disable Metrics/MethodLength

    # @param [Netomox::Topology::Networks] base_topology
    # @param [String] l3_node_name
    # @param [Integer] src_asn
    # @return [Hash]
    def pickup_prefix_set(base_topology, l3_node_name, src_asn)
      # pickup target network
      bgp_proc_nw = base_topology.find_network('bgp_proc')
      if bgp_proc_nw.nil?
        message = "network:bgp_proc is not found in #{base_topology.networks.map(&:name)}"
        return { error: true, message: }
      end

      # pickup target node (layer3 name -> bgp-proc node)
      bgp_proc_node = bgp_proc_nw.find_node_by_support('layer3', l3_node_name)
      if bgp_proc_node.nil?
        message = "bgp-proc node that supports layer3:#{l3_node_name} is not found in network:#{bgp_proc_nw.name}"
        return { error: true, message: }
      end

      prefix_set_name = "as#{src_asn}-advd-ipv4"
      prefix_set = find_prefix_set(bgp_proc_node, prefix_set_name)
      if prefix_set.nil? || prefix_set.empty?
        message = "prefix-set: #{prefix_set_name} is not found or empty in node:#{bgp_proc_node.name}"
        return { error: true, message: }
      end

      # found prefix_set to modify for candidate topology
      { error: false, message: 'ok', prefix_set: }
    end
    # rubocop:enable Metrics/MethodLength

    # @param [Netomox::Topology::Node] bgp_proc_node
    # @param [String] prefix_set_name
    # @return [nil, Netomox::Topology::MddoBgpPrefixSet]
    def find_prefix_set(bgp_proc_node, prefix_set_name)
      bgp_proc_node.attribute.prefix_sets.find do |pfx_set|
        pfx_set.name =~ /#{prefix_set_name}/
      end
    end

    # @return [Netomox::Topology::Networks] topology object
    def read_base_topology
      ModelConductor.rest_api.fetch_topology_object(@network, @snapshot)
    end
  end
end
