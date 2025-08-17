# frozen_string_literal: true

require 'netomox'
require_relative 'arg_link'
require_relative 'name_converter'
require_relative 'netomox_patch'

module ModelConductor
  # command generator for manual topology operation
  class TopologyOpsCommander
    # @param [String] command Command name
    # @param [Hash] command_args Command arguments (original_namespace)
    # @param [Hash] topology_data Topology data (original namespace)
    # @param [Hash] ns_convert_table Namespace convert table
    def initialize(command, command_args, topology_data, ns_convert_table)
      @command = command
      @arg_link = ArgLink.from_link(command_args['link'])
      @name_converter = NameConverter.new(ns_convert_table)

      original_topology = Netomox::Topology::Networks.new(topology_data)
      @orig_l3nw = original_topology.find_network('layer3')
    end

    # rubocop:disable Metrics/MethodLength

    # @return [Hash] response data
    def answer
      operation = {
        'command' => @command,
        'original_link' => @arg_link
      }
      current_resource = {
        'links' => [
          @orig_l3nw.find_all_links_connect(@arg_link.source.to_tpref), # link0
          @orig_l3nw.find_all_links_connect(@arg_link.destination.to_tpref) # link1
        ],
        'empty_bridges' => @orig_l3nw.find_all_empty_bridges
      }
      # response data
      {
        'operation' => operation,
        'current_resource' => current_resource,
        'tobe_resource' => operate_tobe(current_resource)
      }
    end
    # rubocop:enable Metrics/MethodLength

    private

    # rubocop:disable Metrics/MethodLength

    # @param [Netomox::Topology::TpRef] shut_ep Shutdown endpoint (current)
    # @param [Netomox::Topology::Node] empty_bridge Empty bridge (tobe)
    # @return [Array<String>] command list
    def emulated_ns_ops(shut_ep, empty_bridge)
      # convert table entry (emulated namespace info)
      conv_shut_br = @name_converter.convert_node_name(shut_ep.node_ref)
      conv_shut_tp = @name_converter.convert_tp_name(shut_ep.node_ref, shut_ep.tp_ref)
      conv_ebr = @name_converter.convert_node_name(empty_bridge.name)
      # converted names
      shut_br_l1p, shut_tp_l1p, ebr_l1p = [conv_shut_br, conv_shut_tp, conv_ebr].map { |h| h['l1_principal'] }
      shut_br_l3m, shut_tp_l3m, ebr_l3m = [conv_shut_br, conv_shut_tp, conv_ebr].map { |h| h['l3_model'] }

      [
        "# ovs-vsctl del-port #{shut_br_l3m} #{shut_tp_l3m}",
        "ovs-vsctl del-port #{shut_br_l1p} #{shut_tp_l1p}",
        "# ovs-vsctl add-port #{ebr_l3m} #{shut_tp_l3m}",
        "ovs-vsctl add-port #{ebr_l1p} #{shut_tp_l1p}"
      ]
    end
    # rubocop:enable Metrics/MethodLength

    # rubocop:disable Metrics/MethodLength

    # @param [Array<Netomox::Topology::Link>] link_pair Link pair (current)
    # @param [Netomox::Topology::Node] empty_bridge Empty bridge
    # @return [Hash]
    def move_shutdown_bridge_link(link_pair, empty_bridge)
      # alias: pair = [a->b, b->a], only use first entry
      link0 = link_pair[0]
      # answers
      remove_links = []
      append_links = []

      shut_ep = link0.find_shutdown_endpoint
      keep_ep = link0.find_counterpart_endpoint(shut_ep)
      new_ep = Netomox::Topology::TpRef.from_name(empty_bridge.name, shut_ep.tp_ref, 'layer3')

      cli_commands = emulated_ns_ops(shut_ep, empty_bridge)

      remove_links.push(link_pair)
      append_links.push(Netomox::Topology::Link.from_tpref(keep_ep, new_ep, 'layer3'))
      append_links.push(Netomox::Topology::Link.from_tpref(new_ep, keep_ep, 'layer3'))

      {
        'remove_links' => remove_links,
        'append_links' => append_links,
        'command_list' => cli_commands
      }
    end
    # rubocop:enable Metrics/MethodLength

    # @param [Array<Hash>] ops_answers Operation answer list
    # @param [Array<Netomox::Topology::Node>] empty_bridges Empty bridge list (tobe/after)
    # @return [Hash]
    def merge_operations(ops_answers, empty_bridges)
      {
        'remove_links' => ops_answers.map { |op| op['remove_links'] }.flatten(1),
        'append_links' => ops_answers.map { |op| op['append_links'] },
        'command_list' => ops_answers.map { |op| op['command_list'] },
        'empty_bridge' => empty_bridges
      }
    end

    # @param [Netomox::Topology::Network] layer3_nw Layer3 network
    # @param [Array<Netomox::Topology::Link>] links Link list
    # @return [Netomox::Topology::Node]
    # @raise [StandardError]
    def find_bridge_node_from(layer3_nw, links)
      links.each do |link|
        shut_ep = link.find_shutdown_endpoint
        next unless shut_ep.nil? # if found shutdown endpoint, nothing to do

        # pattern[2] connected normal segment node
        seg_nodes = layer3_nw.find_all_nodes_by_type('segment')
        [link.source, link.destination].each do |ep|
          target_seg_node = seg_nodes.find { |node| node.name == ep.node_ref }
          return target_seg_node unless target_seg_node.nil?
        end
      end
      raise StandardError, 'pattern[2] target bridge not found'
    end

    # @param [Netomox::Topology::Link] link00 Link0
    # @param [Netomox::Topology::Link] link10 Link1
    # @param [Array<Netomox::Topology::Node>] tobe_empty_bridges Empty bridge list (tobe/after)
    # @return [Netomox::Topology::Node]
    # @raise [StandardError]
    def select_target_bridge(link00, link10, tobe_empty_bridges)
      if @orig_l3nw.empty_bridge_link?(link00) && @orig_l3nw.empty_bridge_link?(link10)
        # pattern [1] both link0 and 1 are connected to shutdown bridge
        tobe_empty_bridges.shift
      else
        # pattern [2] one of link0 or 1 is connected to shutdown bridge
        find_bridge_node_from(@orig_l3nw, [link00, link10])
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength

    # @param [Hash] current_resource Current resource data
    # @return [Hash]
    # @raise [StandardError] operation pattern error
    def operate_tobe(current_resource)
      # alias
      link0 = current_resource['links'][0] # pair of 00, 01: a->b, b->a pair
      link00 = link0[0]
      link1 = current_resource['links'][1] # pair of 10, 11: c->d, d->c pair
      link10 = link1[0]

      unless @orig_l3nw.empty_bridge_link?(link00) || @orig_l3nw.empty_bridge_link?(link10)
        raise StandardError, "pattern[3], these endpoints are not connected shutdown-bridge: #{link00}, #{link10}"
      end

      # pattern [1][2] one or both link connected to shutdown bridge
      tobe_empty_bridges = current_resource['empty_bridges'].dup # keep current list

      target_bridge = select_target_bridge(link00, link10, tobe_empty_bridges)
      raise StandardError, 'pattern[1][2] target bridge not found' if target_bridge.nil?

      ans = []
      ans.push(move_shutdown_bridge_link(link0, target_bridge)) if @orig_l3nw.empty_bridge_link?(link00)
      ans.push(move_shutdown_bridge_link(link1, target_bridge)) if @orig_l3nw.empty_bridge_link?(link10)
      merge_operations(ans, tobe_empty_bridges)

      # pattern [3], ignore currently
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
