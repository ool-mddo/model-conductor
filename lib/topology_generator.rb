# frozen_string_literal: true

require_relative 'operation_base'

module ModelConductor
  # generate topology
  class TopologyGenerator < OperationBase
    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize

    # @param [String] model_info_list list of model-info (List of physical snapshot info: origin data)
    # @param [Hash] options Options
    # @return [Hash] logical/physical snapshot info
    #
    # snapshot_dict = {
    #   <network name> => [
    #     { physical: model_info, logical: [snapshot_pattern, ...] },
    #     ...
    #   ]
    # }
    # one physical snapshot <=> multiple logical (linkdown) snapshots
    def generate_snapshot_dict(model_info_list, options)
      @logger.info 'Generate logical snapshots: link-down patterns'
      snapshot_dict = {}

      # model_info: physical snapshot info...origination points
      # snapshot_patterns: logical snapshot info
      # NOTICE: model_info_list is not 'symbolize names'
      model_info_list.each do |model_info|
        network = model_info['network']
        snapshot = model_info['snapshot']

        # set physical snapshot info of the network
        @logger.debug "Add physical snapshot info of #{snapshot} to #{network}"
        snapshot_dict[network] = [] unless snapshot_dict.keys.include?(network)
        snapshot_pair = { physical: model_info, logical: [] }
        snapshot_dict[network].push(snapshot_pair)

        # requested logical snapshot? (linkdown topology simulation)
        only_physical_ss = option_phy_ss_only?(options)
        @logger.debug "Physical snapshot only? #{only_physical_ss}"
        next if only_physical_ss

        # set logical snapshot info of the network
        @logger.debug "Add logical snapshot info of #{snapshot} to #{network}"
        snapshot_patterns = generate_snapshot_patterns(network, snapshot, options)
        snapshot_dict[network][-1][:logical] = snapshot_patterns
      end

      @logger.debug "snapshot_dict: #{snapshot_dict}"
      snapshot_dict
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    # rubocop:disable Metrics/MethodLength

    # @param [Hash] snapshot_dict Physical and logical snapshot info for each network
    # @return [Array<Hash>] netoviz index data
    def convert_query_to_topology(snapshot_dict)
      @logger.debug '[convert_query_to_topology]'
      netoviz_index_data = []
      snapshot_dict.each_pair do |network, snapshot_pairs|
        # snapshot_pairs = [{ physical: model_info, logical: [snapshot_pattern,...] }]
        snapshot_types = snapshot_pairs.map do |snapshot_pair|
          [{ type: :physical, data: snapshot_pair[:physical] }]
            .concat(snapshot_pair[:logical].map { |snapshot_pattern| { type: :logical, data: snapshot_pattern }})
        end
        snapshot_types.flatten.each do |snapshot_type|
          process_snapshot_data(network, snapshot_type[:type], snapshot_type[:data])
          datum = netoviz_index_datum(network, snapshot_type[:type], snapshot_type[:data])
          netoviz_index_data.push(datum)
        end
      end
      netoviz_index_data
    end
    # rubocop:enable Metrics/MethodLength

    # @param [Array<Hash>] netoviz_index_data Netoviz index data
    # @return [void]
    def save_netoviz_index(netoviz_index_data)
      @logger.info 'Push (register) netoviz index'
      @logger.debug "netoviz_index_data: #{netoviz_index_data}"
      url = '/topologies/index'
      @rest_api.post(url, { index_data: netoviz_index_data })
    end

    private

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

    # rubocop:disable Metrics/MethodLength

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @param [Hash] options Options
    # @return [Array<Hash>] snapshot-patterns
    def generate_snapshot_patterns(network, snapshot, options)
      @logger.info "[#{network}/#{snapshot}] Generate logical snapshot"
      # TODO: if physical_ss_only=True, removed in configs/network/snapshot/snapshot_patterns.json
      post_opt = {}
      if options.key?('off_node')
        post_opt[:node] = options['off_node']
        post_opt[:interface_regexp] = options['off_intf_re'] if options.key?('off_intf_re')
      end
      url = "/configs/#{network}/#{snapshot}/snapshot_patterns"
      # response: snapshot_pattern
      response = @rest_api.post(url, post_opt)

      snapshot_patterns = parse_json_str(response.body)
      # when a target snapshot specified
      snapshot_patterns.filter! { |sp| sp[:target_snapshot_name] == options['snapshot'] } if options.key?('snapshot')
      snapshot_patterns
    end
    # rubocop:enable Metrics/MethodLength

    # rubocop:disable Metrics/MethodLength

    # @param [String] network Network name
    # @param [Symbol] snapshot_type Snapshot type (:physical or :logical)
    # @param [Hash] snapshot_data Snapshot metadata (model_info or snapshot_pattern elements)
    # @return [void]
    def process_snapshot_data(network, snapshot_type, snapshot_data)
      snapshot_key = snapshot_type == :physical ? 'snapshot' : :target_snapshot_name
      snapshot = snapshot_data[snapshot_key]
      target_key = "#{network}/#{snapshot}"

      @logger.info "[#{target_key}] Query configurations each snapshot and save it to file"
      url = "/queries/#{network}/#{snapshot}"
      @rest_api.post(url)

      @logger.info "[#{target_key}] Generate topology file from query results"
      write_url = "/topologies/#{network}/#{snapshot}"
      @rest_api.post(write_url)

      return unless logical_snapshot?(snapshot_data)

      @logger.info "[#{target_key}] Generate diff data and write back"
      src_snapshot = snapshot_data[:orig_snapshot_name]
      diff_url = "/topologies/#{network}/snapshot_diff/#{src_snapshot}/#{snapshot}"
      diff_response = @rest_api.fetch(diff_url)
      diff_topology_data = parse_json_str(diff_response.body)
      @rest_api.post(write_url, { topology_data: diff_topology_data[:topology_data] })
    end
    # rubocop:enable Metrics/MethodLength
  end
end
