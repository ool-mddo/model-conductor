# frozen_string_literal: true

require 'grape'
require 'lib/api/rest_api_base'
require 'lib/topology_ops/topology_ops_commander'

module ModelConductor
  module ApiRoute
    # api topology_ops
    class TopologyOps < RestApiBase
      helpers do
        # @param [String] orig_ss_name Original snapshot name
        # @return [String] Converted (emulated) snapshot name
        def convert_orig_ss_name(orig_ss_name)
          orig_ss_name.sub('original', 'emulated')
        end

        # @param [String] network Network name
        # @return [String] Current original prealloc-snapshot name
        def current_orig_pa_ss_name(network)
          # detect target prealloc-snapshot
          prealloc_snapshots = rest_api.fetch_snapshot_list(network, 'original_asis_preallocated')
          error!('original_asis_prealloc snapshot not found', 400) if prealloc_snapshots.empty?
          prealloc_snapshots.sort_by { |s| s[/\d+$/].to_i }.max
        end

        # @param [String] network Network name
        # @return [String] Next original prealloc-snapshot name
        def next_orig_pa_ss_name(network)
          # detect target prealloc-snapshot
          curr_orig_pa_ss_name = current_orig_pa_ss_name(network)
          curr_orig_pa_ss_name.sub(/\d+$/) { |m| m.to_i + 1 }
        end
      end

      desc 'Get target preallocated snapshot names'
      get 'topology_ops_targets' do
        network = params[:network]
        {
          'current' => current_orig_pa_ss_name(network),
          'next' => next_orig_pa_ss_name(network)
        }
      end

      desc 'Post topology operation commands'
      params do
        requires :command, type: String, desc: 'Topology operation command'
        requires :args, type: Hash, desc: 'Topology operation arguments'
        optional :dry_run, type: Boolean, desc: 'Dry run', default: false
      end
      post 'topology_ops' do
        network, command, command_args, dry_run = %i[network command args dry_run].map { |key| params[key] }

        # current original_asis_preallocated(N) snapshot
        curr_orig_pa_ss_name = current_orig_pa_ss_name(network)
        curr_orig_pa_ss_data = rest_api.fetch_topology_data(network, curr_orig_pa_ss_name)

        # exec operation
        ns_convert_table = rest_api.fetch_ns_convert_table(network)
        commander = TopologyOpsCommander.new(command, command_args, curr_orig_pa_ss_data, ns_convert_table)
        answer_data = commander.answer(network, curr_orig_pa_ss_name)

        unless dry_run
          # save next, original_asis_preallocated(N+1) snapshot
          next_orig_pa_ss_name = next_orig_pa_ss_name(network)
          rest_api.post_topology_data(network, next_orig_pa_ss_name, answer_data['tobe_topology'])

          # update next, namespace convert table
          rest_api.post_update_ns_convert_table(network, answer_data['tobe_ns_convert_table'])

          # overwrite diff between original preallocN and prealloc(N+1)
          next_orig_pa_ss_data_diff = rest_api.fetch_topology_diff(network, curr_orig_pa_ss_name, next_orig_pa_ss_name)
          rest_api.post_topology_data(network, next_orig_pa_ss_name, next_orig_pa_ss_data_diff)

          # update netoviz index
          rest_api.update_netoviz_index(network, curr_orig_pa_ss_name, next_orig_pa_ss_name)
        end

        # response
        answer_data.delete('tobe_topology')
        answer_data.delete('tobe_ns_convert_table')
        answer_data
      end
    end
  end
end
