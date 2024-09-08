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
  end
end

module ModelConductor
  # candidate topology generator
  class CandidateTopologyGenerator
    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @param [Hash] usecase_data
    def initialize(network, snapshot, usecase_data)
      @network = network
      @snapshot = snapshot
      @usecase = usecase_data
    end

    # @param [Integer] candidate_index candidate index
    # @return [nil, Netomox::Topology::Networks]
    def generate_candidate_topologies(candidate_index)
      unless @usecase[:name] == 'pni_te'
        ModelConductor.logger.error "Unsupported usecase: #{@usecase[:name]}"
        return nil
      end

      generate_candidate_for_pni_te(candidate_index)
    end

    private

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize

    # @param [Integer] candidate_index candidate index
    # @return [nil, Netomox::Topology::Networks]
    def generate_candidate_for_pni_te(candidate_index)
      # always reload
      base_topology = read_base_topology
      # usecase params
      l3_node_name = @usecase[:params][:source_as][:preferred_peer][:node]
      src_asn = @usecase[:params][:source_as][:asn]

      result = pickup_prefix_set(base_topology, l3_node_name, src_asn)
      if result[:error]
        ModelConductor.logger.error result[:message]
        return nil
      end

      # data check before update configs
      if result[:prefix_set].prefixes.at(candidate_index).nil?
        ModelConductor.logger.warn("Can't generate candidate for candidate_#{candidate_index}")
        return nil
      end

      # update configs
      result[:prefix_set].prefixes.delete_at(candidate_index - 1)

      # return modified topology data as candidate_i
      base_topology
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

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
      if prefix_set.nil?
        message = "prefix-set: #{prefix_set_name} is not found in node:#{bgp_proc_node.name}"
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
