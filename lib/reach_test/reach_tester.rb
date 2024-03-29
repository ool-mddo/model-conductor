# frozen_string_literal: true

require_relative 'reach_pattern_handler'
require_relative 'bf_trace_results'

module ModelConductor
  # Reachability tester
  class ReachTester
    # @param [Hash] test_pattern_def Test pattern definition data
    def initialize(test_pattern_def)
      super()
      @logger = ModelConductor.logger
      @rest_api = ModelConductor.rest_api

      reach_ops = ReachPatternHandler.new(test_pattern_def)
      @patterns = reach_ops.expand_patterns.reject { |pt| pt[:cases].empty? }
    end

    # rubocop:disable Metrics/MethodLength

    # @param [String] network Network name to analyze (in batfish)
    # @param [Array<String>] snapshots List of snapshots to test
    # @return [Array<Hash>]
    def exec_all_traceroute_tests(network, snapshots)
      @logger.debug "[exec_all_traceroute_tests] snapshots=#{snapshots}"
      return [] if snapshots.nil?

      snapshots.map do |snapshot|
        {
          network:,
          snapshot:,
          description: fetch_snapshot_description(network, snapshot),
          patterns: @patterns.map do |pattern|
            {
              pattern: pattern[:pattern],
              cases: pattern[:cases].map { |c| exec_traceroute_test(c, network, snapshot) }
            }
          end
        }
      end
    end
    # rubocop:enable Metrics/MethodLength

    private

    # @param [String] network Network name to analyze (in batfish)
    # @param [String] snapshot Snapshot name in bf_network
    # @return [String] Description of the snapshot
    def fetch_snapshot_description(network, snapshot)
      snapshot_pattern = @rest_api.fetch_snapshot_patterns(network, snapshot)
      return 'Origin snapshot?' if snapshot_pattern.nil?
      # Origin (physical) snapshot: returns all logical snapshot patterns
      return 'Origin snapshot' if snapshot_pattern.is_a?(Array)
      # Logical snapshot: returns single snapshot pattern
      return snapshot_pattern[:description] if snapshot_pattern.key?(:description)

      '(Description not found)'
    end

    # @param [Hash] test_case Test case
    def test_case_to_str(test_case)
      "#{test_case[:src][:node]}[#{test_case[:src][:intf]}] -> #{test_case[:dst][:node]}[#{test_case[:dst][:intf]}]"
    end

    # @param [Hash] test_case Expanded test case
    # @param [String] network Network name to analyze (in batfish)
    # @param [String] snapshot Snapshot name in bf_network
    # @return [Hash]
    def exec_traceroute_test(test_case, network, snapshot)
      @logger.info "traceroute: #{network}/#{snapshot} #{test_case_to_str(test_case)}"
      src = test_case[:src]
      traceroute_result = @rest_api.fetch_traceroute(network, snapshot, src[:node], src[:intf],
                                                     test_case[:dst][:intf_ip])
      { case: test_case, traceroute: BFTracerouteResults.new(traceroute_result).to_data }
    end
  end
end
