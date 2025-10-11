# frozen_string_literal: true

require_relative 'netomox_patch'
require_relative 'name_converter'

module ModelConductor
  # base class for operation commander
  class OpsCommanderBase
    # @param [String] command Command name
    # @param [Hash] topology_data Topology data (original namespace)
    # @param [Hash] ns_convert_table Namespace convert table
    def initialize(command, topology_data, ns_convert_table)
      @command = command
      @name_converter = NameConverter.new(ns_convert_table)
      @original_topology = Netomox::Topology::Networks.new(topology_data)
      @orig_l3nw = @original_topology.find_network('layer3') # alias
    end

    def answer
      current_resource = current_resource_data
      operate_tobe = operate_tobe_data(current_resource)
      changed_topology = tobe_topology_data!(operate_tobe)

      # response data
      {
        'operation' => operation_data,
        'current_resource' => current_resource,
        'tobe_resource' => operate_tobe,
        'tobe_topology' => changed_topology,
        'tobe_ns_convert_table' => @name_converter.to_data
      }
    end

    private

    # @param [String] command Command name
    # @param [String] br_l3m Bridge name (model)
    # @param [String] tp_l3m Tp name (model)
    # @param [String] br_l1p Bridge name (principal)
    # @param [String] tp_l1p Tp name (principal)
    # @return [Hash]
    def build_worker_command(command, br_l3m, tp_l3m, br_l1p, tp_l1p)
      {
        '_cmd_in_model' => "ovs-vsctl #{command} #{br_l3m} #{tp_l3m}",
        '_cmd_in_worker' => "ovs-vsctl #{command} #{br_l1p} #{tp_l1p}",
        'operation' => command,
        'bridge_name' => br_l1p,
        'port_name' => tp_l1p
      }
    end

    # param [String] src_br Source bridge name
    # param [String] src_tp Source term-point name
    # param [String] dst_br Destination bridge name
    # @return [Array<Hash>]
    def commands_to_move_tp(src_br, src_tp, dst_br)
      # converted names
      src_br_l3m, src_tp_l3m, dst_br_l3m = @name_converter.convert_move_targets('l3_model', src_br, src_tp, dst_br)
      src_br_l1p, src_tp_l1p, dst_br_l1p = @name_converter.convert_move_targets('l1_principal', src_br, src_tp, dst_br)
      # update convert table
      @name_converter.move_tp_entry!(src_br, src_tp, dst_br)

      [
        build_worker_command('del-port', src_br_l3m, src_tp_l3m, src_br_l1p, src_tp_l1p),
        build_worker_command('add-port', dst_br_l3m, src_tp_l3m, dst_br_l1p, src_tp_l1p)
      ]
    end

    # @return [Hash]
    def operation_data
      raise NotImplementedError, 'not implemented: operation_data'
    end

    # @return [Hash]
    def current_resource_data
      raise NotImplementedError, 'not implemented: current_resource_data'
    end

    # @param [Hash] current_resources Current resource data
    # @return [Hash]
    def operate_tobe_data(current_resources)
      raise NotImplementedError, 'not implemented: operate_tobe'
    end

    # rubocop:disable Metrics/MethodLength

    # @param [Array<Array(Netomox::Topology::Link, Netomox::Topology::Link)>] remove_link_pairs Remove link pairs
    # @return [Hash] source_ref_path => { node: node, tp: tp } (destination node/tp to be "laundered")
    def remove_links_from_topology!(remove_link_pairs)
      move_nodes = {}
      remove_link_pairs.each do |remove_link_pair|
        remove_link_pair.each do |rm_link|
          # [node](source_tp)-----rm_link---->(dest_tp)[segment]
          # Memory destination node/tp before remove the link. It must be moved to other segment (bridge).
          # as keyword = source node tp because node-side-tp is not changed (kept).
          dst_node, dst_tp = @orig_l3nw.find_node_tp_by_edge(rm_link.destination)
          if dst_node&.segment_node?
            dst_node.delete_tp_by_name!(dst_tp.name)
            move_nodes[rm_link.source.ref_path] = { node: dst_node, tp: dst_tp }
          end
          @orig_l3nw.remove_link!(rm_link)
        end
      end
      move_nodes
    end
    # rubocop:enable Metrics/MethodLength

    # @param [Array<Array(Netomox::Topology::Link, Netomox::Topology::Link)>] append_link_pairs Append link pairs
    # @param [Hash] move_nodes Mode/term-point tables to be "laundered"
    # @return [void]
    def append_link_pairs_to_topology!(append_link_pairs, move_nodes)
      append_link_pairs.each do |append_link_pair|
        append_link_pair.each do |append_link|
          if move_nodes[append_link.source.ref_path]
            dst_node = @orig_l3nw.find_node_by_name(append_link.destination.node_ref)
            dst_node.laundering_tp!(move_nodes[append_link.source.ref_path][:tp])
          end
          @orig_l3nw.add_link!(append_link)
        end
      end
    end

    # @param [Hash] operate_tobe_data Operate tobe data
    # @return [Hash] RFC8345 topology data
    def tobe_topology_data!(operate_tobe_data)
      move_nodes = remove_links_from_topology!(operate_tobe_data['remove_links'])
      append_link_pairs_to_topology!(operate_tobe_data['append_links'], move_nodes)

      @original_topology.to_data
    end
  end
end
