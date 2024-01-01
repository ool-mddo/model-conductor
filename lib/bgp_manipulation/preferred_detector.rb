# frozen_string_literal: true

module Netomox
  module Topology
    # patch for Netomox::Topology::Network
    class Network
      # @return [void]
      def clear_all_tp_flag(target_flag)
        @nodes.each do |node|
          node.termination_points.each do |tp|
            tp.attribute.flags.reject! { |f| f == target_flag }
          end
        end
      end

      # @param [String] network_ref Supporting network
      # @param [String] node_ref Supporting node
      # @param [String] tp_ref Supporting term-point
      # @return [nil, Netomox::Topology::Node] nil if not found
      def find_node_has_intf_with_support(network_ref, node_ref, tp_ref)
        @nodes.find do |node|
          node.find_intf_with_support(network_ref, node_ref, tp_ref)
        end
      end
    end

    # patch for Netomox::Topology::Node
    class Node
      # @param [String] network_ref Supporting network
      # @param [String] node_ref Supporting node
      # @param [String] tp_ref Supporting term-point
      # @return [nil, Netomox::Topology::TermPoint] nil if not found
      def find_intf_with_support(network_ref, node_ref, tp_ref)
        @termination_points.find do |tp|
          target_sup_data = {
            'network-ref' => network_ref,
            'node-ref' => node_ref,
            'tp-ref' => tp_ref
          }
          target_sup = Netomox::Topology::SupportingTerminationPoint.new(target_sup_data)
          tp.supports.any? { |sup| sup == target_sup }
        end
      end
    end
  end
end

module ModelConductor
  # Detect preferred node of external-AS
  class PreferredDetector
    # AS border-router flag
    NODE_ASBR_FLAG = 'ext-bgp-speaker'
    # Preferred flag for tp (peer)
    TP_PREFERRED_FLAG = 'ext-bgp-speaker-preferred'

    # @param [Netomox::Topology::Networks] topology Topology object
    def initialize(topology)
      @networks = topology
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity

    # @param [String] layer_name Target layer name (== 'bgp_proc')
    # @param [Integer] ext_asn External ASN
    # @param [String] l3_node L3 node name (internal, peering to ext_asn)
    # @param [String] l3_intf L3 interface name (internal, peering to ext_asn)
    # @return [Hash] Error or Patched topology data
    #   Error data : { error: <http error status code>, message: <string> }
    def detect_preferred_peer(layer_name, ext_asn, l3_node, l3_intf)
      layer = @networks.find_network(layer_name)
      message = "Layer:#{layer_name} is not found in topology"
      return { error: 500, message: } if layer.nil?

      layer.clear_all_tp_flag(TP_PREFERRED_FLAG)

      bgp_proc_node = layer.find_node_has_intf_with_support('layer3', l3_node, l3_intf)
      message = "Layer:#{layer_name}, Node not found that supports layer3/#{l3_node}"
      return { error: 500, message: } if bgp_proc_node.nil?

      # TODO: in bgp_proc, there are many (>1) peers (tps) supports L3 interface?
      bgp_proc_intf = bgp_proc_node.find_intf_with_support('layer3', l3_node, l3_intf)

      # TODO: in bgp_proc, there are many (>1) peers (links)?
      bgp_proc_link = layer.find_link_by_source(bgp_proc_node.name, bgp_proc_intf.name)
      message = "Layer:#{layer_name}, Link not found that source:#{bgp_proc_node.name}[#{bgp_proc_intf.name}]"
      return { error: 500, message: } if bgp_proc_link.nil?

      preferred_node_name = bgp_proc_link.destination.node_ref
      preferred_node = layer.find_node_by_name(preferred_node_name)
      if preferred_node.nil? || !preferred_node.attribute.flags.include?(NODE_ASBR_FLAG)
        message = "layer:#{layer_name}, Ext-bgp-speaker is not found: #{preferred_node_name}"
        return { error: 500, message: }
      end

      preferred_intf_name = bgp_proc_link.destination.tp_ref
      preferred_intf = preferred_node.find_tp_by_name(preferred_intf_name)
      if preferred_intf.nil? || preferred_intf.attribute.local_as != ext_asn
        message = "layer:#{layer_name}, ext-bgp-speaker ASN check failed, mismatch ASN:#{ext_asn}"
        return { error: 500, message: }
      end

      preferred_intf.attribute.flags.push(TP_PREFERRED_FLAG)

      @networks.to_data
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
  end
end
