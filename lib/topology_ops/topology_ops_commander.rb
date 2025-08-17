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
      @original_topology = Netomox::Topology::Networks.new(topology_data)
    end

    # @return [Hash] response data
    def answer
      orig_l3nw = @original_topology.find_network('layer3')

      operation = {
        'command' => @command,
        'original_link' => @arg_link
      }

      current_resource = {
        'links' => [
          orig_l3nw.find_all_links_connect(@arg_link.source.to_tpref), # link0
          orig_l3nw.find_all_links_connect(@arg_link.destination.to_tpref) # link1
        ],
        'empty_bridges' => orig_l3nw.find_all_empty_bridges
      }

      {
        'operation' => operation,
        'current_resource' => current_resource,
        'tobe_resource' => operate_tobe(orig_l3nw, operation, current_resource)
      }
    end

    private

    # @param [Array<Netomox::Topology::Link>] link_pair Link pair (current)
    # @param [Netomox::Topology::Node] empty_bridge Empty bridge
    # @return [Hash]
    def move_shutdown_bridge_link(link_pair, empty_bridge)
      # alias: pair = [a->b, b->a], only use first entry
      link0 = link_pair[0]
      # answers
      # cli_commands = [] # TBA
      remove_links = []
      append_links = []

      shut_ep = link0.find_shutdown_endpoint
      keep_ep = link0.find_counterpart_endpoint(shut_ep)
      new_ep = Netomox::Topology::TpRef.from_name(empty_bridge.name, shut_ep.tp_ref, 'layer3')

      remove_links.push(link_pair)
      append_links.push(Netomox::Topology::Link.from_tpref(keep_ep, new_ep, 'layer3'))
      append_links.push(Netomox::Topology::Link.from_tpref(new_ep, keep_ep, 'layer3'))

      {
        'remove_links' => remove_links,
        'append_links' => append_links,
        'command_list' => ['TBA'] # TBA
      }
    end

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
    # @param [Hash] operation Operation data
    # @param [Hash] current_resource Current resource data
    # @return [Hash]
    def operate_tobe(layer3_nw, operation, current_resource)
      # alias
      link0 = current_resource['links'][0] # pair of 00, 01: a->b, b->a pair
      link00 = link0[0]
      link1 = current_resource['links'][1] # pair of 10, 11: c->d, d->c pair
      link10 = link1[0]

      if layer3_nw.is_empty_bridge_link?(link00) || layer3_nw.is_empty_bridge_link?(link10)
        # pattern [1][2]
        tobe_empty_bridges = current_resource['empty_bridges'].dup # keep current list
        ebr = tobe_empty_bridges.shift
        raise StandardError, "Empty bridge:#{ebr.name} is not found in layer3 network" if ebr.nil?

        ans = []
        ans.push(move_shutdown_bridge_link(link0, ebr)) if layer3_nw.is_empty_bridge_link?(link00)
        ans.push(move_shutdown_bridge_link(link1, ebr)) if layer3_nw.is_empty_bridge_link?(link10)
        merge_operations(ans, tobe_empty_bridges)
      else
        # pattern [3]
        warn `Cannot handle pattern [3], Ignored (currently)`
        {}
      end
    end
  end
end
