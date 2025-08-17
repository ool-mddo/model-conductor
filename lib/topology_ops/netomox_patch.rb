# frozen_string_literal: true

require 'netomox'

module Netomox
  module Topology
    # shutdown bridge name
    SHUTDOWN_BRIDGE_NAME = 'Seg_empty00'

    # patches for Networks
    class Network
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

      # @param [Netomox::Topology::Link] link Link
      # @return [Boolean] true if link is shutdown-bridge link
      def is_empty_bridge_link?(link)
        link.source.node_ref == SHUTDOWN_BRIDGE_NAME || link.destination.node_ref == SHUTDOWN_BRIDGE_NAME
      end
    end

    # patches for link
    class Link
      # another constructor
      # @param [Netomox::Topology::TpRef] source Source node/tp
      # @param [Netomox::Topology::TpRef] destination Destination node/tp
      # @param [String] layer Layer name
      # @return [Netomox::Topology::Link]
      def self.from_tpref(source, destination, layer)
        data = {
          'link-id' => "#{source.node_ref},#{source.tp_ref},#{destination.node_ref},#{destination.tp_ref}",
          'source' => source.to_data('source'),
          'destination' => destination.to_data('dest'),
        }
        new(data, layer)
      end

      # @param [String] node_ref Node name
      # @return [Netomox::Topology::TpRef, nil] nil if not found
      def find_endpoint_by_node(node_ref)
        return @source if @source.node_ref == node_ref
        return @destination if @destination.node_ref == node_ref
        nil
      end

      # @return [Netomox::Topology::TpRef, nil] nil if not found
      def find_shutdown_endpoint
        find_endpoint_by_node(SHUTDOWN_BRIDGE_NAME)
      end

      # @param [Netomox::Topology::TpRef] endpoint Link endpoint
      # @return [Netomox::Topology::TpRef, nil] counterpart (facing) endpoint, nil if not found
      def find_counterpart_endpoint(endpoint)
        return @source unless @source == endpoint
        return @destination unless @destination == endpoint
        nil
      end
    end

    # patches for TpRef
    class TpRef
      # another constructor
      # @param [String] node Node name
      # @param [String] term_point Term-point name
      # @param [String] layer Layer name
      # @return [Netomox::Topology::TpRef]
      def self.from_name(node, term_point, layer)
        data = {
          'source-node' => node,
          'source-tp' => term_point,
        }
        new(data, layer)
      end
    end
  end
end
