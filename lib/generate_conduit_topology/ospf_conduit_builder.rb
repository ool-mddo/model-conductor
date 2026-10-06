# frozen_string_literal: true

module ModelConductor
  # Builds a conduit OSPF area topology network from the original ospf network plus the
  # node_mapping and tp_mapping produced by Layer3ConduitBuilder.
  #
  # Rules:
  #   - Non-segment nodes: grouped by conduit_node_name; only external TPs (in tp_mapping) kept
  #   - Segment nodes: rebuilt with conduit TP names; dropped if fewer than 2 TPs survive
  #   - supporting-termination-point updated to reference conduit layer3 node/TP names
  class OspfConduitBuilder # rubocop:disable Metrics/ClassLength
    TP_KEY = 'ietf-network-topology:termination-point'
    LINK_KEY = 'ietf-network-topology:link'
    SUPPORTING_TP_KEY = 'supporting-termination-point'
    SUPPORTING_NODE_KEY = 'supporting-node'
    OSPF_NW_ATTR = 'mddo-topology:ospf-area-network-attributes'
    OSPF_NODE_ATTR = 'mddo-topology:ospf-area-node-attributes'
    OSPF_TP_ATTR = 'mddo-topology:ospf-area-termination-point-attributes'

    # @param original_ospf [Hash] one ospf_area network data from original topology
    # @param node_mapping [Hash] { original_node_name => conduit_node_name }
    # @param tp_mapping [Hash] { [original_node_name, original_tp_name] => [conduit_node_name, conduit_tp_name] }
    # @param router_ids [Hash] { original_node_name => ospf router-id } over all ospf areas
    def initialize(original_ospf, node_mapping, tp_mapping, router_ids = {})
      @original_ospf = original_ospf
      @node_mapping = node_mapping
      @tp_mapping = tp_mapping
      @router_ids = router_ids
      @orig_nodes = original_ospf['node'] || []
      @orig_links = original_ospf[LINK_KEY] || []
    end

    # @return [Hash] conduit ospf network data
    def build
      conduit_nodes = build_conduit_non_segment_nodes
      seg_info = compute_conduit_segment_info
      conduit_seg_nodes = build_conduit_segment_nodes(seg_info)
      conduit_links = build_conduit_links(seg_info)

      network_header.merge('node' => conduit_nodes + conduit_seg_nodes, LINK_KEY => conduit_links).compact
    end

    private

    # network-level data (type, supporting network, attributes) inherited from the original ospf network
    def network_header
      {
        'network-id' => @original_ospf['network-id'],
        'network-types' => @original_ospf['network-types'],
        'supporting-network' => @original_ospf['supporting-network']&.map(&:dup),
        OSPF_NW_ATTR => @original_ospf[OSPF_NW_ATTR]&.dup
      }
    end

    # Group original non-segment nodes by conduit name, build one conduit node per group
    def build_conduit_non_segment_nodes
      group_nodes_by_conduit.map { |conduit_name, orig_nodes| build_conduit_non_seg_node(conduit_name, orig_nodes) }
    end

    def group_nodes_by_conduit
      @orig_nodes.each_with_object({}) do |orig_node, groups|
        name = orig_node['node-id']
        next if segment_name?(name)

        # nodes not defined in the blueprint are omitted
        conduit_name = @node_mapping[name]
        next if conduit_name.nil?

        groups[conduit_name] ||= []
        groups[conduit_name] << orig_node
      end
    end

    def build_conduit_non_seg_node(conduit_name, orig_nodes)
      conduit_tps = orig_nodes.flat_map { |orig_node| build_conduit_non_seg_tps(orig_node, conduit_name) }
      representative = orig_nodes.first
      node = {
        'node-id' => conduit_name,
        TP_KEY => conduit_tps,
        SUPPORTING_NODE_KEY => [{ 'network-ref' => 'layer3', 'node-ref' => conduit_name }],
        OSPF_NODE_ATTR => build_conduit_node_attr(representative, conduit_name)
      }
      node['flag'] = representative['flag'].dup if representative['flag']
      node
    end

    # A conduit node has one router-id in every area: the one of the group's representative original node.
    def build_conduit_node_attr(representative, conduit_name)
      attr = (representative[OSPF_NODE_ATTR] || {}).dup
      router_id = conduit_router_id(conduit_name)
      attr['router-id'] = router_id if router_id
      attr
    end

    # @return [String, nil] router-id of the first (representative) original node of the conduit node
    def conduit_router_id(conduit_name)
      orig_name, = @node_mapping.find { |orig, conduit| conduit == conduit_name && @router_ids.key?(orig) }
      orig_name && @router_ids[orig_name]
    end

    # @return [Hash] { original router-id => conduit router-id }
    def router_id_translation
      @router_id_translation ||= @node_mapping.each_with_object({}) do |(orig_name, conduit_name), table|
        orig_rid = @router_ids[orig_name]
        conduit_rid = conduit_router_id(conduit_name)
        table[orig_rid] = conduit_rid if orig_rid && conduit_rid
      end
    end

    # Follow router-id of merged nodes in neighbor entries
    def convert_tp_attr(tp_attr)
      attr = (tp_attr || {}).dup
      return attr unless attr['neighbor']

      attr['neighbor'] = attr['neighbor'].map do |nbr|
        nbr.merge('router-id' => router_id_translation.fetch(nbr['router-id'], nbr['router-id']))
      end
      attr
    end

    def build_conduit_non_seg_tps(orig_node, conduit_name)
      (orig_node[TP_KEY] || []).filter_map do |tp|
        orig_tp_id = tp['tp-id']
        _conduit_node, conduit_tp = @tp_mapping[[orig_node['node-id'], orig_tp_id]]
        next unless conduit_tp

        {
          'tp-id' => conduit_tp,
          SUPPORTING_TP_KEY => [{ 'network-ref' => 'layer3', 'node-ref' => conduit_name, 'tp-ref' => conduit_tp }],
          OSPF_TP_ATTR => convert_tp_attr(tp[OSPF_TP_ATTR])
        }
      end
    end

    # Compute conduit Segment info once: used by both build_conduit_segment_nodes and build_conduit_links.
    # @return [Hash] {
    #   surviving_names: Set<String>,
    #   tp_map: Hash { "seg_name/old_tp_id" => new_tp_id },
    #   nodes: Array<Hash>
    # }
    def compute_conduit_segment_info
      acc = { surviving_names: Set.new, tp_map: {}, nodes: [], seen_signatures: Set.new }
      @orig_nodes.each do |orig_node|
        name = orig_node['node-id']
        next unless segment_name?(name)

        process_segment_node(name, orig_node, acc)
      end
      acc.slice(:surviving_names, :tp_map, :nodes)
    end

    def process_segment_node(name, orig_node, acc)
      conduit_tps = resolve_segment_conduit_tps(orig_node)
      return if conduit_tps.size < 2

      sig = conduit_tps.map { |_, _, cn| cn }.uniq.sort.freeze
      return unless acc[:seen_signatures].add?(sig)

      register_surviving_segment(name, conduit_tps, orig_node, acc)
    end

    def register_surviving_segment(name, conduit_tps, orig_node, acc)
      acc[:surviving_names] << name
      conduit_tps.each { |(orig_tp, new_tp_id)| acc[:tp_map]["#{name}/#{orig_tp['tp-id']}"] = new_tp_id }
      acc[:nodes] << build_conduit_seg_node(name, conduit_tps, orig_node)
    end

    def resolve_segment_conduit_tps(orig_node)
      (orig_node[TP_KEY] || []).filter_map do |tp|
        parsed = parse_seg_tp(tp['tp-id'])
        next unless parsed

        orig_node_name, orig_tp_name = parsed
        conduit_node, conduit_tp = @tp_mapping[[orig_node_name, orig_tp_name]]
        next unless conduit_tp

        new_tp_id = "#{conduit_node}_#{conduit_tp}"
        [tp, new_tp_id, conduit_node]
      end
    end

    def build_conduit_seg_node(name, conduit_tps, orig_node)
      {
        'node-id' => name,
        TP_KEY => conduit_tps.map { |(orig_tp, new_tp_id)| build_conduit_seg_tp(name, orig_tp, new_tp_id) },
        SUPPORTING_NODE_KEY => [{ 'network-ref' => 'layer3', 'node-ref' => name }],
        OSPF_NODE_ATTR => (orig_node[OSPF_NODE_ATTR] || {}).dup
      }
    end

    def build_conduit_seg_tp(name, orig_tp, new_tp_id)
      {
        'tp-id' => new_tp_id,
        SUPPORTING_TP_KEY => [{ 'network-ref' => 'layer3', 'node-ref' => name, 'tp-ref' => new_tp_id }],
        OSPF_TP_ATTR => (orig_tp[OSPF_TP_ATTR] || {}).dup
      }
    end

    def build_conduit_segment_nodes(seg_info)
      seg_info[:nodes]
    end

    def build_conduit_links(seg_info)
      surviving = seg_info[:surviving_names]
      tp_map = seg_info[:tp_map]
      @orig_links.filter_map { |link| convert_conduit_link(link, surviving, tp_map) }
    end

    def convert_conduit_link(link, surviving, tp_map)
      src_ep = [link['source']['source-node'], link['source']['source-tp']]
      dst_ep = [link['destination']['dest-node'], link['destination']['dest-tp']]
      if segment_name?(src_ep[0])
        convert_seg_src_link(src_ep, dst_ep, surviving, tp_map)
      elsif segment_name?(dst_ep[0])
        convert_seg_dst_link(src_ep, dst_ep, surviving, tp_map)
      end
    end

    def convert_seg_src_link(src_ep, dst_ep, surviving, tp_map)
      src_node, src_tp = src_ep
      dst_node, dst_tp = dst_ep
      return unless surviving.include?(src_node)

      new_src_tp = tp_map["#{src_node}/#{src_tp}"]
      return unless new_src_tp

      conduit_dst, conduit_dst_tp = @tp_mapping[[dst_node, dst_tp]]
      return unless conduit_dst_tp

      make_link(src_node, new_src_tp, conduit_dst, conduit_dst_tp)
    end

    def convert_seg_dst_link(src_ep, dst_ep, surviving, tp_map)
      src_node, src_tp = src_ep
      dst_node, dst_tp = dst_ep
      return unless surviving.include?(dst_node)

      new_dst_tp = tp_map["#{dst_node}/#{dst_tp}"]
      return unless new_dst_tp

      conduit_src, conduit_src_tp = @tp_mapping[[src_node, src_tp]]
      return unless conduit_src_tp

      make_link(conduit_src, conduit_src_tp, dst_node, new_dst_tp)
    end

    def make_link(src_node, src_tp, dst_node, dst_tp)
      {
        'link-id' => "#{src_node},#{src_tp},#{dst_node},#{dst_tp}",
        'source' => { 'source-node' => src_node, 'source-tp' => src_tp },
        'destination' => { 'dest-node' => dst_node, 'dest-tp' => dst_tp }
      }
    end

    # Parse a Seg TP name "{orig_node}_{orig_tp}" by reverse-lookup in tp_mapping.
    # @return [Array(String, String), nil] [orig_node_name, orig_tp_name]
    def parse_seg_tp(seg_tp_id)
      @tp_mapping.each_key do |(orig_node, orig_tp)|
        return [orig_node, orig_tp] if seg_tp_id == "#{orig_node}_#{orig_tp}"
      end
      nil
    end

    def segment_name?(name)
      name.start_with?('Seg_')
    end
  end
end
