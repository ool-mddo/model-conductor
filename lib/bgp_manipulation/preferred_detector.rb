# frozen_string_literal: true

module ModelConductor
  # Detect preferred node of external-AS
  class PreferredDetector
    # alias: layer node key
    LAYER_NODE_KEY = 'node'
    # alias: layer link key
    LAYER_LINK_KEY = 'ietf-network-topology:link'
    # alias: node tp key
    NODE_TP_KEY = 'ietf-network-topology:termination-point'
    # alias: node support key
    NODE_SUPPORT_KEY = 'supporting-node'
    # alias: node attr key
    NODE_ATTR_KEY = 'mddo-topology:bgp-proc-node-attributes'
    # alias: tp support key
    TP_SUPPORT_KEY = 'supporting-termination-point'
    # alias: tp attr key
    TP_ATTR_KEY = 'mddo-topology:bgp-proc-termination-point-attributes'
    # Preferred flag for tp (peer)
    TP_PREFERRED_FLAG = 'ext-bgp-speaker-preferred'

    # @param [Hash] topology_data RFC8345 topology data (all layers)
    def initialize(topology_data)
      @topology = topology_data
      @networks = topology_data['ietf-network:networks']['network'] # alias
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength

    # @param [String] layer_name Target layer name (== 'bgp_proc')
    # @param [Integer] ext_asn External ASN
    # @param [String] l3_node L3 node name (internal, peering to ext_asn)
    # @param [String] l3_intf L3 interface name (internal, peering to ext_asn)
    # @return [Hash] Error or Patched topology data
    #   Error data : { error: <http error status code>, message: <string> }
    def detect_preferred_peer(layer_name, ext_asn, l3_node, l3_intf)
      layer = @networks.find { |nw| nw['network-id'] == layer_name }
      message = "Layer:#{layer_name} is not found in topology"
      return { error: 500, message: } if layer.nil?

      clear_all_preferred_flag(layer)

      bgp_proc_node = find_node_with_support(layer, 'layer3', l3_node, l3_intf)
      message = "Layer:#{layer_name}, Node not found that supports layer3/#{l3_node}"
      return { error: 500, message: } if bgp_proc_node.nil?

      # TODO: in bgp_proc, there are many (>1) peers (tps) supports L3 interface?
      bgp_proc_intf = find_intf_with_support(bgp_proc_node, 'layer3', l3_node, l3_intf)

      # TODO: in bgp_proc, there are many (>1) peers (links)?
      bgp_proc_link = find_link_with_source(layer, bgp_proc_node['node-id'], bgp_proc_intf['tp-id'])
      message = "Layer:#{layer_name}, Link not found that source:#{bgp_proc_node['node-id']}[#{bgp_proc_intf['tp-id']}]"
      return { error: 500, message: } if bgp_proc_link.nil?

      preferred_node_name = bgp_proc_link['destination']['dest-node']
      preferred_node = find_preferred_node(layer, preferred_node_name)
      message = "layer:#{layer_name}, Ext-bgp-speaker is not found: #{preferred_node_name}"
      return { error: 500, message: } if preferred_node.nil?

      preferred_intf_name = bgp_proc_link['destination']['dest-tp']
      preferred_intf = find_preferred_intf(preferred_node, preferred_intf_name, ext_asn)
      message = "layer:#{layer_name}, ext-bgp-speaker ASN check failed, mismatch ASN:#{ext_asn}"
      return { error: 500, message: } if preferred_intf.nil?

      preferred_intf[TP_ATTR_KEY]['flag'].push(TP_PREFERRED_FLAG)

      @topology
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    # @param [Hash] layer Layer data (RFC8345)
    # @return [void]
    def clear_all_preferred_flag(layer)
      layer[LAYER_NODE_KEY].each do |node|
        node[NODE_TP_KEY].each do |tp|
          tp[TP_ATTR_KEY]['flag'].reject! { |flag| flag == TP_PREFERRED_FLAG }
        end
      end
    end

    # @param [Hash] node Node data (RFC8345)
    # @param [String] preferred_intf Interface name to be preferred
    # @param [Integer] ext_asn External ASN
    # @return [nil,Hash] Interface data (RFC8345) if found
    def find_preferred_intf(node, preferred_intf, ext_asn)
      node[NODE_TP_KEY].find do |tp|
        tp['tp-id'] == preferred_intf && tp[TP_ATTR_KEY]['local-as'] == ext_asn
      end
    end

    # @param [Hash] layer Layer data (RFC8345)
    # @param [String] preferred_node Node name to be preferred
    # @return [nil,Hash] Node data (RFC8345) if found
    def find_preferred_node(layer, preferred_node)
      layer[LAYER_NODE_KEY].find do |node|
        node['node-id'] == preferred_node && node[NODE_ATTR_KEY]['flag'].include?('ext-bgp-speaker')
      end
    end

    # @param [Hash] layer Layer data (RFC8345)
    # @param [String] src_node Node name of link source
    # @param [String] src_intf Interface name of link source
    # @return [nil,Hash] Link data (RFC8345) if found
    def find_link_with_source(layer, src_node, src_intf)
      layer[LAYER_LINK_KEY].find do |link|
        link_src = link['source']
        link_src['source-node'] == src_node && link_src['source-tp'] == src_intf
      end
    end

    # @param [Hash] layer Layer data (RFC8345)
    # @param [String] sup_nw Support-network name of the node
    # @param [String] sup_node Support-node name of the node
    # @param [String] sup_intf Support-tp name of the node
    # @return [nil, Hash] Interface data (RFC8345) if found
    def find_node_with_support(layer, sup_nw, sup_node, sup_intf)
      layer[LAYER_NODE_KEY].find do |node|
        bgp_proc_intf = find_intf_with_support(node, sup_nw, sup_node, sup_intf)
        # NOTE: bgp_proc node has single support tp
        node_sup = node[NODE_SUPPORT_KEY][0]
        bgp_proc_intf && node_sup['network-ref'] == sup_nw && node_sup['node-ref'] == sup_node
      end
    end

    # @param [Hash] node Node data (RFC8345)
    # @param [String] sup_nw Support-network name of the node
    # @param [String] sup_node Support-node name of the node
    # @param [String] sup_intf Support-tp name of the node
    # @return [nil, Hash] Interface data (RFC8345) if found
    def find_intf_with_support(node, sup_nw, sup_node, sup_intf)
      # TODO: in bgp_proc, there are many (>1) peers (tps) supports L3 interface?
      node[NODE_TP_KEY].find do |tp|
        # NOTE: bgp_proc tp has single support tp
        tp_sup = tp[TP_SUPPORT_KEY][0]
        tp_sup['network-ref'] == sup_nw && tp_sup['node-ref'] == sup_node && tp_sup['tp-ref'] == sup_intf
      end
    end
  end
end
