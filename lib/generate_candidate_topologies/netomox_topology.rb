# frozen_string_literal: true

require 'netomox'

# patch for CandidateTopologyGenerator
module Netomox
  module Topology
    # patch for Networks (topology)
    class Networks
      # rubocop:disable Metrics/MethodLength

      # @param [String] l3_node_name
      # @param [String] prefix_set_name
      # @return [Hash]
      def pickup_prefix_set(l3_node_name, prefix_set_name)
        # pickup target network
        bgp_proc_nw = find_network('bgp_proc')
        if bgp_proc_nw.nil?
          message = "network:bgp_proc is not found in #{@networks.map(&:name)}"
          return { error: true, message: }
        end

        # pickup target node (layer3 name -> bgp-proc node)
        bgp_proc_node = bgp_proc_nw.find_node_by_support('layer3', l3_node_name)
        if bgp_proc_node.nil?
          message = "bgp-proc node that supports layer3:#{l3_node_name} is not found in network:#{bgp_proc_nw.name}"
          return { error: true, message: }
        end

        prefix_set = bgp_proc_node.find_prefix_set(prefix_set_name)
        if prefix_set.nil?
          message = "prefix-set: #{prefix_set_name} is not found in node:#{bgp_proc_node.name}"
          return { error: true, message: }
        end

        # found prefix_set to modify for candidate topology
        { error: false, message: 'ok', prefix_set: }
      end
      # rubocop:enable Metrics/MethodLength
    end

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

    # patch for Node
    class Node
      # @param [String] prefix_set_name
      # @return [nil, Netomox::Topology::MddoBgpPrefixSet]
      def find_prefix_set(prefix_set_name)
        @attribute.prefix_sets.find do |prefix_set|
          prefix_set.name =~ /#{prefix_set_name}/
        end
      end
    end
  end
end
