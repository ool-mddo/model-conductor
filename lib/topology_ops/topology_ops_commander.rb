# frozen_string_literal: true

require_relative 'link_ops_commander'
require_relative 'shut_ops_commander'

module ModelConductor
  # command generator for manual topology operation
  class TopologyOpsCommander
    # @param [String] command Command name
    # @param [Hash] command_args Command arguments (original_namespace)
    # @param [Hash] topology_data Topology data (original namespace)
    # @param [Hash] ns_convert_table Namespace convert table
    # @raise [StandardError] unknown command
    def initialize(command, command_args, topology_data, ns_convert_table)
      @commander = if command == 'connect_link'
                     LinkOpsCommander.new(command, command_args, topology_data, ns_convert_table)
                   elsif command == 'shutdown_intf'
                     ShutOpsCommander.new(command, command_args, topology_data, ns_convert_table)
                   else
                     raise StandardError, "unknown command: #{command}"
                   end
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @return [Hash] response data
    def answer(network, snapshot)
      answer = @commander.answer
      seasoning_commands(answer, network, snapshot)
    end

    private

    # @param [Hash] answer
    # @param [String] network network name
    # @param [String] snapshot snapshot name
    # @return [Hash]
    def seasoning_commands(answer, network, snapshot)
      warn "# seasoning_commands, command_list = #{answer['tobe_resource']['command_list']}"
      answer['tobe_resource']['command_list'].each do |cmd_pair|
        warn "# cmd_pair = #{cmd_pair}"
        cmd_pair.each do |cmd|
          cmd['network'] = network
          cmd['snapshot'] = snapshot
        end
      end
      answer
    end
  end
end
