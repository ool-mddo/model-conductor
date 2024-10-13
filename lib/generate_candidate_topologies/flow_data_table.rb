# frozen_string_literal: true

module ModelConductor
  # Row of flow-data table
  class FlowDataTableRow
    # @!attribute [r] source
    #   @return [String] Source prefix
    # @!attribute [r] dest
    #   @return [String] Destination prefix
    # @!attribute [r] rate
    #   @return [Float] Traffic rate (Mbps)
    attr_reader :source, :dest, :rate

    # @param [String] source Source prefix
    # @param [String] dest Destination prefix
    # @param [String, Numeric] rate Traffic rate
    def initialize(source: '', dest: '', rate: -1)
      @source = source
      @dest = dest
      @rate = Float(rate)
    end

    # @return [String]
    def to_s
      "#{@source} -> #{@dest}, #{@rate}"
    end
  end

  # flow-data table
  class FlowDataTable
    # @param [Array<Hash>] flow_data Flow data
    def initialize(flow_data)
      @rows = flow_data.map { |flow| FlowDataTableRow.new(**flow) }
    end

    # @return [String]
    def to_s
      @rows.map(&:to_s)
    end

    # @param [Integer] combination_count Combination depth
    # @param [Netomox::Topology::MddoBgpPrefixSet] prefix_set
    # @param [Integer] expected_max_bandwidth Target rate (Mbps)
    # @return [Array<Hash>] Aggregated flows
    #   e.g.)
    # [
    #   {:prefixes=>["10.100.0.0/16", "10.120.0.0/17", "10.130.0.0/21"], :rate=>8017.11, :diff=>17.1},
    #   {:prefixes=>["10.100.0.0/16", "10.110.0.0/20", "10.130.0.0/21"], :rate=>8621.14, :diff=>621.13},
    #   ...
    # ]
    def aggregated_flows_by_prefix(combination_count, prefix_set, expected_max_bandwidth)
      prefix_table = rows_by_prefixes(prefix_set)
      prefix_combinations = enumerate_combinations(prefix_table, combination_count)
      aggregate_prefix_combinations(prefix_combinations, expected_max_bandwidth)
    end

    private

    # @param [Hash] prefix_table Prefix => [row] table
    # @param [Integer] combination_count Combination depth
    # @return [Array<Array<Hash>>]
    def enumerate_combinations(prefix_table, combination_count)
      # Hash to array, [p1={prefix:, rows:[...]}, p2, p3, ...]
      prefix_list = prefix_table.to_a.map { |prefix, rows| { prefix:, rows: } }

      # combinations
      #   [[p1], [p2], [p3], ..., [p1, p2], [p1, p3], [p2, p3], ...]
      prefix_combinations = []
      combination_count.times do |cc|
        prefix_list.combination(cc + 1) { |prefix_item| prefix_combinations.push(prefix_item) }
      end
      prefix_combinations
    end

    # rubocop:disable Metrics/AbcSize

    # @param [Array<Array<Hash>>] prefix_combinations
    # @param [Integer] expected_max_bandwidth Target rate (Mbps)
    # @return [Array<Hash>]
    def aggregate_prefix_combinations(prefix_combinations, expected_max_bandwidth)
      aggregates = prefix_combinations.map do |prefix_combination|
        # prefix_combination = [p1], ..., [p1, p2], ...
        rate = prefix_combination.map { |p| p[:rows].inject(0.0) { |total, r| total + r.rate } }
                                 .inject(0.0) { |total, r| total + r }.floor(2)
        {
          prefixes: prefix_combination.map { |p| p[:prefix] },
          rate:,
          diff: (rate - expected_max_bandwidth).floor(2)
        }
      end
      aggregates.sort_by { |aggregated_item| aggregated_item[:diff].abs }
    end
    # rubocop:enable Metrics/AbcSize

    # rubocop:disable Metrics/MethodLength

    # @param [Netomox::Topology::MddoBgpPrefixSet] prefix_set
    # @return [Hash] prefix => [row] table
    def rows_by_prefixes(prefix_set)
      prefix_table = {}

      @rows.each do |row|
        row_dest = IPAddr.new(row.dest)
        prefix_set.prefixes.map(&:prefix).each do |prefix_str|
          prefix = IPAddr.new(prefix_str)
          next unless prefix.include?(row_dest)

          # NOTE: operation is able to per prefix.
          #   if there are flow data that not matches prefix, the flows are not controllable with target prefix-set.
          prefix_table[prefix_str] = [] unless prefix_table.key?(prefix_str)
          prefix_table[prefix_str].push(row)
        end
      end
      prefix_table
    end
    # rubocop:enable Metrics/MethodLength
  end
end
