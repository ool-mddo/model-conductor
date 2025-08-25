# frozen_string_literal: true

require 'netomox'

module Netomox
  module Topology
    # Node flag for L3 preallocated segment-node
    FLAG_PREALLOCATED_SEGMENT = 'preallocated-segment'
    # shutdown bridge name
    SB_NAME = 'Seg_empty00'

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

      # @param [TpRef] endpoint Link endpoint (source or destination)
      # @return [Array<Link>]
      def find_all_links_connect(endpoint)
        [
          find_link_by_source(endpoint.node_ref, endpoint.tp_ref),
          find_link_by_destination(endpoint.node_ref, endpoint.tp_ref)
        ].compact
      end

      # @param [String] node_type Node type
      # @return [Array<Node>]
      def find_all_nodes_by_type(node_type)
        @nodes.find_all do |node|
          node.attribute.node_type == node_type
        end
      end

      # @param [String] flag Flag
      # @return [Array<Node>]
      def find_all_node_by_flag(flag)
        @nodes.find_all do |node|
          node.attribute.flags.include?(flag)
        end
      end

      # @return [Array<Node>]
      def find_all_empty_bridges
        prealloc_seg_node = find_all_node_by_flag(FLAG_PREALLOCATED_SEGMENT)
        return [] if prealloc_seg_node.nil?

        # find preallocated-segment-node that has no term-point (link) without shutdown-bridge
        prealloc_seg_node.find_all { |node| node.termination_points.empty? && node.name != SB_NAME }
      end

      # @param [Link] link Link
      # @return [Boolean] true if link is shutdown-bridge link
      def empty_bridge_link?(link)
        link.source.node_ref == SB_NAME || link.destination.node_ref == SB_NAME
      end
    end

    # patches for link
    class Link
      # another constructor
      # @param [TpRef] source Source node/tp
      # @param [TpRef] destination Destination node/tp
      # @param [String] layer Layer name
      # @return [Link]
      def self.from_tpref(source, destination, layer)
        data = {
          'link-id' => "#{source.node_ref},#{source.tp_ref},#{destination.node_ref},#{destination.tp_ref}",
          'source' => source.to_data('source'),
          'destination' => destination.to_data('dest')
        }
        new(data, layer)
      end

      # @param [Hash] arg_link Link data in command argument
      # @return [Link]
      def self.from_arg_link(arg_link)
        source = TpRef.from_name(arg_link['source']['node'], arg_link['source']['tp'], 'layer3')
        destination = TpRef.from_name(arg_link['destination']['node'], arg_link['destination']['tp'], 'layer3')
        from_tpref(source, destination, 'layer3')
      end

      # @param [String] node_ref Node name
      # @return [TpRef, nil] nil if not found
      def find_endpoint_by_node(node_ref)
        return @source if @source.node_ref == node_ref
        return @destination if @destination.node_ref == node_ref

        nil
      end

      # @return [TpRef, nil] nil if not found
      def find_shutdown_endpoint
        find_endpoint_by_node(SB_NAME)
      end

      # @param [TpRef] endpoint Link endpoint
      # @return [TpRef, nil] counterpart (facing) endpoint, nil if not found
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
      # @return [TpRef]
      def self.from_name(node, term_point, layer)
        data = {
          'source-node' => node,
          'source-tp' => term_point
        }
        new(data, layer)
      end
    end
  end
end
