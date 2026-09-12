# frozen_string_literal: true

require 'set'

module ModelConductor
  # Builds a conduit OSPF area topology network from the original ospf network plus the
  # node_mapping and tp_mapping produced by Layer3ConduitBuilder.
  #
  # Rules:
  #   - Non-segment nodes: grouped by conduit_node_name; only external TPs (in tp_mapping) kept
  #   - Segment nodes: rebuilt with conduit TP names; dropped if fewer than 2 TPs survive
  #   - supporting-termination-point updated to reference conduit layer3 node/TP names
  class OspfConduitBuilder
    TP_KEY = 'ietf-network-topology:termination-point'
    LINK_KEY = 'ietf-network-topology:link'
    SUPPORTING_TP_KEY = 'supporting-termination-point'
    SUPPORTING_NODE_KEY = 'supporting-node'
    OSPF_NODE_ATTR = 'mddo-topology:ospf-area-node-attributes'
    OSPF_TP_ATTR = 'mddo-topology:ospf-area-termination-point-attributes'

    # @param original_ospf [Hash] one ospf_area network data from original topology
    # @param node_mapping [Hash] { original_node_name => conduit_node_name }
    # @param tp_mapping [Hash] { [original_node_name, original_tp_name] => [conduit_node_name, conduit_tp_name] }
    def initialize(original_ospf, node_mapping, tp_mapping)
      @original_ospf = original_ospf
      @node_mapping = node_mapping
      @tp_mapping = tp_mapping
      @orig_nodes = original_ospf['node'] || []
      @orig_links = original_ospf[LINK_KEY] || []
    end

    # @return [Hash] conduit ospf network data
    def build
      conduit_nodes = build_conduit_non_segment_nodes
      seg_info = compute_conduit_segment_info
      conduit_seg_nodes = build_conduit_segment_nodes(seg_info)
      conduit_links = build_conduit_links(seg_info)

      {
        'network-id' => @original_ospf['network-id'],
        'network-types' => @original_ospf['network-types'],
        'node' => conduit_nodes + conduit_seg_nodes,
        LINK_KEY => conduit_links
      }.compact
    end

    private

    # Group original non-segment nodes by conduit name, build one conduit node per group
    def build_conduit_non_segment_nodes
      groups = {}
      @orig_nodes.each do |orig_node|
        name = orig_node['node-id']
        next if segment_name?(name)

        conduit_name = @node_mapping[name]
        raise "OSPF node '#{name}' not found in node_mapping" if conduit_name.nil?

        groups[conduit_name] ||= []
        groups[conduit_name] << orig_node
      end

      groups.map do |conduit_name, orig_nodes|
        conduit_tps = orig_nodes.flat_map do |orig_node|
          (orig_node[TP_KEY] || []).filter_map do |tp|
            orig_tp_id = tp['tp-id']
            _conduit_node, conduit_tp = @tp_mapping[[orig_node['node-id'], orig_tp_id]]
            next unless conduit_tp

            {
              'tp-id' => conduit_tp,
              SUPPORTING_TP_KEY => [{ 'network-ref' => 'layer3', 'node-ref' => conduit_name, 'tp-ref' => conduit_tp }],
              OSPF_TP_ATTR => (tp[OSPF_TP_ATTR] || {}).dup
            }
          end
        end

        representative = orig_nodes.first
        node = {
          'node-id' => conduit_name,
          TP_KEY => conduit_tps,
          SUPPORTING_NODE_KEY => [{ 'network-ref' => 'layer3', 'node-ref' => conduit_name }],
          OSPF_NODE_ATTR => (representative[OSPF_NODE_ATTR] || {}).dup
        }
        node['flag'] = representative['flag'].dup if representative['flag']
        node
      end
    end

    # Compute conduit Segment info once: used by both build_conduit_segment_nodes and build_conduit_links.
    # @return [Hash] {
    #   surviving_names: Set<String>,
    #   tp_map: Hash { "seg_name/old_tp_id" => new_tp_id },
    #   nodes: Array<Hash>
    # }
    def compute_conduit_segment_info
      surviving_names = Set.new
      tp_map = {}
      nodes = []
      seen_signatures = Set.new

      @orig_nodes.each do |orig_node|
        name = orig_node['node-id']
        next unless segment_name?(name)

        conduit_tps = (orig_node[TP_KEY] || []).filter_map do |tp|
          parsed = parse_seg_tp(tp['tp-id'])
          next unless parsed

          orig_node_name, orig_tp_name = parsed
          conduit_node, conduit_tp = @tp_mapping[[orig_node_name, orig_tp_name]]
          next unless conduit_tp

          new_tp_id = "#{conduit_node}_#{conduit_tp}"
          [tp, new_tp_id, conduit_node]
        end

        next if conduit_tps.size < 2

        # Deduplicate: skip if another segment already covers the same conduit endpoint pair
        sig = conduit_tps.map { |_, _, cn| cn }.uniq.sort.freeze
        next unless seen_signatures.add?(sig)

        surviving_names << name
        conduit_tps.each do |(orig_tp, new_tp_id)|
          tp_map["#{name}/#{orig_tp['tp-id']}"] = new_tp_id
        end

        nodes << {
          'node-id' => name,
          TP_KEY => conduit_tps.map do |(orig_tp, new_tp_id)|
            {
              'tp-id' => new_tp_id,
              SUPPORTING_TP_KEY => [{ 'network-ref' => 'layer3', 'node-ref' => name, 'tp-ref' => new_tp_id }],
              OSPF_TP_ATTR => (orig_tp[OSPF_TP_ATTR] || {}).dup
            }
          end,
          SUPPORTING_NODE_KEY => [{ 'network-ref' => 'layer3', 'node-ref' => name }],
          OSPF_NODE_ATTR => (orig_node[OSPF_NODE_ATTR] || {}).dup
        }
      end

      { surviving_names:, tp_map:, nodes: }
    end

    def build_conduit_segment_nodes(seg_info)
      seg_info[:nodes]
    end

    def build_conduit_links(seg_info)
      surviving = seg_info[:surviving_names]
      tp_map = seg_info[:tp_map]
      links = []

      @orig_links.each do |link|
        src_node = link['source']['source-node']
        src_tp = link['source']['source-tp']
        dst_node = link['destination']['dest-node']
        dst_tp = link['destination']['dest-tp']

        if segment_name?(src_node)
          next unless surviving.include?(src_node)

          new_src_tp = tp_map["#{src_node}/#{src_tp}"]
          next unless new_src_tp

          conduit_dst, conduit_dst_tp = @tp_mapping[[dst_node, dst_tp]]
          next unless conduit_dst_tp

          links << make_link(src_node, new_src_tp, conduit_dst, conduit_dst_tp)
        elsif segment_name?(dst_node)
          next unless surviving.include?(dst_node)

          new_dst_tp = tp_map["#{dst_node}/#{dst_tp}"]
          next unless new_dst_tp

          conduit_src, conduit_src_tp = @tp_mapping[[src_node, src_tp]]
          next unless conduit_src_tp

          links << make_link(conduit_src, conduit_src_tp, dst_node, new_dst_tp)
        end
      end
      links
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
