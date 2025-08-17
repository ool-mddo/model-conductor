# frozen_string_literal: true

require 'netomox'

module Netomox
  module Topology
    # patches for Networks
    class Network
      # shutdown bridge name
      SHUTDOWN_BRIDGE_NAME = 'Seg_empty00'

      def find_link_by_destination(node_ref, tp_ref)
        destination_data = {
          'dest-node' => node_ref,
          'dest-tp' => tp_ref
        }
        destination_ref = TpRef.new(destination_data, 'layer3')
        @links.find { |link| link.destination == destination_ref }
      end

      # @param [Netomox::Topology::TpRef] endpoint Link endpoint (source or destination)
      # @return [Array<Netomox::Topology::Link>]
      def find_all_links_connect(endpoint)
        [
          find_link_by_source(endpoint.node_ref, endpoint.tp_ref),
          find_link_by_destination(endpoint.node_ref, endpoint.tp_ref)
        ].compact
      end

      # @param [String] flag Flag
      # @return [Array<Netomox::Topology::Node>]
      def find_all_node_by_flag(flag)
        @nodes.find_all do |node|
          node.attribute.flags.include?(flag)
        end
      end

      # @return [Array<Netomox::Topology::Node>]
      def find_all_empty_bridges
        empty_seg_nodes = find_all_node_by_flag('empty-segment')
        return [] if empty_seg_nodes.nil?

        # find empty-segment node that has no term-point (link) without shutdown-bridge
        empty_seg_nodes.find_all { |node| node.termination_points.empty? && node.name != SHUTDOWN_BRIDGE_NAME }
      end
    end
  end
end
