# frozen_string_literal: true

require_relative 'ops_commander_base'

module ModelConductor
  # shutdown_intf command generator for manual topology operation
  class ShutOpsCommander < OpsCommanderBase
    # @param [String] command Command name
    # @param [Hash] command_args Command arguments (original_namespace)
    # @param [Hash] topology_data Topology data (original namespace)
    # @param [Hash] ns_convert_table Namespace convert table
    def initialize(command, command_args, topology_data, ns_convert_table)
      super(command, topology_data, ns_convert_table)
      ep = command_args['interface'] # alias
      # = Netomox::Topology::TermPoint.from_name(ep['node'], ep['tp'], 'layer3')
      @node_ep, @seg_ep = normalize_link_endpoint(ep['node'], ep['tp'])
    end

    private

    # @return [Hash]
    def operation_data
      {
        'command' => @command,
        'target' => Netomox::Topology::Link.from_tpref(@node_ep, @seg_ep, 'layer3')
      }
    end

    # @return [Hash]
    def current_resource_data
      {
        'links' => [
          @orig_l3nw.find_all_links_connect(@node_ep)
        ],
        'empty_bridges' => @orig_l3nw.find_all_empty_bridges
      }
    end

    # @param [String] node Node name
    # param [String] term_point Term-point name
    # @return [Array(Netomox::Topology::TpRef, Netomox::Topology::TpRef)] a pair of Term-point (node-ep, seg-ep)
    # @raise [StandardError]
    def normalize_link_endpoint(node, term_point)
      link = @orig_l3nw.find_link_by_source(node, term_point)
      raise StandardError, "link not found: #{node}, #{term_point}" if link.nil?

      src_node = @orig_l3nw.find_node_by_name(link.source.node_ref)

      if src_node.attribute.node_type == 'node'
        [link.source, link.destination]
      else
        [link.destination, link.source]
      end
    end

    # @param [Netomox::Topology::TpRef] tpref1 Term-point 1
    # @param [Netomox::Topology::TpRef] tpref2 Term-point 2
    # @param [String] layer Layer
    # @return [Array<Netomox::Topology::Link>]
    def link_pair_from_tprefs(tpref1, tpref2, layer)
      [
        Netomox::Topology::Link.from_tpref(tpref1, tpref2, layer),
        Netomox::Topology::Link.from_tpref(tpref2, tpref1, layer)
      ]
    end

    # @param [Array<Netomox::Topology::Link>] link_pair Link pair (current)
    # @return [Hash]
    def move_bridge_link_to_shutdown(link_pair)
      append_ep = Netomox::Topology::TpRef.from_name(Netomox::Topology::SB_NAME, @seg_ep.tp_ref, 'layer3')

      {
        'remove_links' => [link_pair],
        'append_links' => [link_pair_from_tprefs(@node_ep, append_ep, 'layer3')],
        'command_list' => [commands_to_move_tp(@seg_ep.node_ref, @seg_ep.tp_ref, append_ep.node_ref)]
      }
    end

    # rubocop:disable Metrics/MethodLength

    # @param [Hash] current_resources Current resource data
    # @return [Hash]
    # @raise [StandardError] operation pattern error
    def operate_tobe_data(current_resources)
      # if segment-ep is shutdown-bridge ep: nothing to do
      if @seg_ep.node_ref == Netomox::Topology::SB_NAME
        return {
          'remove_links' => [],
          'append_links' => [],
          'command_list' => [],
          'empty_bridge' => current_resources['empty_bridges']
        }
      end

      ans = move_bridge_link_to_shutdown(current_resources['links'][0])
      ans['empty_bridge'] = current_resources['empty_bridges']
      ans
    end
    # rubocop:enable Metrics/MethodLength
  end
end
