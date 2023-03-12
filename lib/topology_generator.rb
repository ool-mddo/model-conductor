# frozen_string_literal: true

require 'parallel'
require_relative 'operation_base'

module ModelConductor
  # rubocop:disable Metrics/ClassLength

  # generate topology
  class TopologyGenerator < OperationBase
    # @param [String] model_info_list list of model-info (List of physical snapshot info: origin data)
    def delete_all_data_dir(model_info_list)
      model_info_list.map { |model_info| model_info['network'] }
                     .uniq
                     .each { |network| delete_query_and_topology(network) }
    end

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize

    # @param [String] model_info_list list of model-info (List of physical snapshot info: origin data)
    # @param [Hash] options Options
    # @return [Hash] logical/physical snapshot info
    #
    # snapshot_dict = {
    #   <network name> => [
    #     { physical: model_info, logical: [snapshot_pattern, ...] }, # for a physical snapshot
    #     ...                                                         # it is able to own multiple physical snapshot
    #   ]
    # }
    # one physical snapshot <=> multiple logical (linkdown) snapshots
    def generate_snapshot_dict(model_info_list, options)
      api_key = '[generate_snapshot_dict]'
      @logger.info "#{api_key} start"

      snapshot_dict = {}

      # model_info: physical snapshot info...origination points
      # snapshot_patterns: logical snapshot info
      # NOTICE: model_info_list is not 'symbolize names'
      model_info_list.each do |model_info|
        network = model_info['network']
        snapshot = model_info['snapshot']

        # set physical snapshot info of the network
        @logger.debug "#{api_key} Add physical snapshot info of #{snapshot} to #{network}"
        snapshot_dict[network] = [] unless snapshot_dict.keys.include?(network)
        snapshot_pair = { physical: model_info, logical: [] }
        snapshot_dict[network].push(snapshot_pair)

        # requested logical snapshot? (linkdown topology simulation)
        only_physical_ss = option_phy_ss_only?(options)
        @logger.debug "#{api_key} Physical snapshot only? #{only_physical_ss}"
        if only_physical_ss
          delete_snapshot_patterns(network, snapshot)
          next
        end

        # set logical snapshot info of the network
        @logger.debug "#{api_key} Add logical snapshot info of #{snapshot} to #{network}"
        snapshot_patterns = generate_snapshot_patterns(network, snapshot, options)
        snapshot_dict[network][-1][:logical] = snapshot_patterns
      end
      snapshot_dict
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    # @param [Hash] snapshot_dict Physical and logical snapshot info for each network
    # @return [void]
    def convert_config_to_query(snapshot_dict)
      api_key = '[convert_config_to_query]'
      @logger.info "#{api_key} start"

      each_snapshot_type(snapshot_dict) do |network, snapshot_type|
        query_batfish(network, snapshot_type[:type], snapshot_type[:data])
      end
    end

    # @param [Hash] snapshot_dict Physical and logical snapshot info for each network
    # @param [Boolean] use_parallel Use parallel
    # @return [void]
    def convert_query_to_topology(snapshot_dict, use_parallel: false)
      api_key = '[convert_query_to_topology]'
      @logger.info "#{api_key} start (parallel=#{use_parallel})"

      each_snapshot_type(snapshot_dict, use_parallel:) do |network, snapshot_type|
        process_snapshot_data(network, snapshot_type[:type], snapshot_type[:data])
      end
    end

    # @param [Hash] snapshot_dict Physical and logical snapshot info for each network
    # @return [void]
    def save_netoviz_index(snapshot_dict)
      api_key = '[save_netoviz_index]'
      @logger.info "#{api_key} start"

      netoviz_index_data = []
      each_snapshot_type(snapshot_dict) do |network, snapshot_type|
        datum = netoviz_index_datum(network, snapshot_type[:type], snapshot_type[:data])
        netoviz_index_data.push(datum)
      end
      @rest_api.post_topologies_index(netoviz_index_data)
    end

    private

    # @param [Hash] snapshot_dict Physical and logical snapshot info for each network
    # @param [Boolean] use_parallel Use parallel
    # @return [void]
    # @yield [network, snapshot_type] for each snapshot type
    # @yieldparam [String] network network name
    # @yieldparam [Hash] snapshot type
    # @yieldreturn [void]
    def each_snapshot_type(snapshot_dict, use_parallel: false)
      snapshot_dict_to_types_dict(snapshot_dict).each_pair do |network, snapshot_types|
        if use_parallel
          Parallel.each(snapshot_types) { |snapshot_type| yield(network, snapshot_type) }
        else
          snapshot_types.each { |snapshot_type| yield(network, snapshot_type) }
        end
      end
    end

    # @param [String] network Network name
    # @return [void]
    def delete_query_and_topology(network)
      @rest_api.delete("/queries/#{network}")
      @rest_api.delete("/topologies/#{network}")
    end

    # @param [Hash] options Options
    # @return [Boolean] True if requested physical snapshot only
    def option_phy_ss_only?(options)
      options.key?('phy_ss_only') && options['phy_ss_only']
    end

    # @param [Hash] snapshot_data Snapshot metadata (model_info or snapshot_pattern elements)
    # @return [Boolean] True if the snapshot is logical one
    def logical_snapshot?(snapshot_data)
      snapshot_data.key?(:lost_edges)
    end

    # @param [Hash] snapshot_dict Physical and logical snapshot info for each network
    # @return [Hash] snapshot_types_dict
    def snapshot_dict_to_types_dict(snapshot_dict)
      # snapshot_dict = {
      #   <network>: [                                                    # snapshot_pairs
      #     { physical: model_info, logical: [ snapshot_pattern, ...] },  # physical/logical pair
      #     ...
      #   ]
      # }
      # snapshot_pairs = [
      #   { physical: model_info, logical: [snapshot_pattern, ...] }
      #   ...
      # ]
      snapshot_types = snapshot_dict.map do |network, snapshot_pairs|
        types = snapshot_pairs.map do |snapshot_pair|
          # snapshot_pair = { physical: model_info, logical: [ snapshot_pattern, ...] }
          [{ type: :physical, data: snapshot_pair[:physical] }]
            .concat(snapshot_pair[:logical].map { |snapshot_pattern| { type: :logical, data: snapshot_pattern } })
        end
        [network, types.flatten] # key, value
      end
      # snapshot_types_dict = {
      #   <network>: [ {type: physical}, {type: logical} ...]
      # }
      snapshot_types.to_h
    end

    # @param [String] network Network name
    # @param [Symbol] snapshot_type Snapshot type (:physical or :logical)
    # @param [Hash] snapshot_data Snapshot metadata (model_info or snapshot_pattern elements)
    # @return [Hash] Netoviz index (element)
    def netoviz_index_datum(network, snapshot_type, snapshot_data)
      # file name is FIXED (topology.json)
      datum = { 'network' => network, 'file' => 'topology.json' }
      if snapshot_type == :physical
        datum['snapshot'] = snapshot_data['snapshot']
        datum['label'] = snapshot_data['label']
      else
        datum['snapshot'] = snapshot_data[:target_snapshot_name]
        datum['label'] = snapshot_data[:description]
      end
      datum
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # return [void]
    def delete_snapshot_patterns(network, snapshot)
      @rest_api.delete("/configs/#{network}/#{snapshot}/snapshot_patterns")
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @param [Hash] options Options
    # @return [Array<Hash>] snapshot-patterns
    def generate_snapshot_patterns(network, snapshot, options)
      @logger.info "[#{network}/#{snapshot}] Generate logical snapshot"

      post_opt = {}
      if options.key?('off_node')
        post_opt[:node] = options['off_node']
        post_opt[:interface_regexp] = options['off_intf_re'] if options.key?('off_intf_re')
      end

      snapshot_patterns = @rest_api.post_snapshot_patterns(network, snapshot, post_opt)
      # when a target snapshot specified
      snapshot_patterns.filter! { |sp| sp[:target_snapshot_name] == options['snapshot'] } if options.key?('snapshot')
      snapshot_patterns
    end

    # @param [Symbol] snapshot_type Snapshot type (:physical or :logical)
    # @param [Hash] snapshot_data Snapshot metadata (model_info or snapshot_pattern elements)
    # @return [String] snapshot name
    def snapshot_name_by_type(snapshot_type, snapshot_data)
      snapshot_key = snapshot_type == :physical ? 'snapshot' : :target_snapshot_name
      snapshot_data[snapshot_key]
    end

    # @param [String] network Network name
    # @param [Symbol] snapshot_type Snapshot type (:physical or :logical)
    # @param [Hash] snapshot_data Snapshot metadata (model_info or snapshot_pattern elements)
    # @return [void]
    def query_batfish(network, snapshot_type, snapshot_data)
      snapshot = snapshot_name_by_type(snapshot_type, snapshot_data)
      target_key = "[query_batfish] #{network}/#{snapshot}:"

      @logger.info "#{target_key} Query configurations for each snapshot"
      @rest_api.post_batfish_query(network, snapshot)
    end

    # @param [String] network Network name
    # @param [Symbol] snapshot_type Snapshot type (:physical or :logical)
    # @param [Hash] snapshot_data Snapshot metadata (model_info or snapshot_pattern elements)
    # @return [void]
    def process_snapshot_data(network, snapshot_type, snapshot_data)
      snapshot = snapshot_name_by_type(snapshot_type, snapshot_data)
      target_key = "[process_snapshot_data] #{network}/#{snapshot}:"

      @logger.info "#{target_key} Generate topology file from query results"
      @rest_api.post_topology_data(network, snapshot)

      return unless logical_snapshot?(snapshot_data)

      @logger.info "#{target_key} Generate diff data and write back"
      src_snapshot = snapshot_data[:orig_snapshot_name]
      diff_topology_data = @rest_api.fetch_topology_diff(network, src_snapshot, snapshot)
      @rest_api.post_topology_data(network, snapshot, { topology_data: diff_topology_data })
    end
  end
  # rubocop:enable Metrics/ClassLength
end
