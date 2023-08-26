# frozen_string_literal: true

require 'grape'
require 'lib/reach_test/reach_tester'
require 'lib/reach_test/reach_result_converter'

module ModelConductor
  module ApiRoute
    # api L3 reachability test
    class Reachability < Grape::API
      desc 'Test L3 reachability with test-pattern for multiple snapshot in a network'
      params do
        # rubocop:disable Style/RedundantArrayConstructor
        requires :snapshots, type: Array[String], desc: 'List of snapshot to test'
        requires :test_pattern, type: Hash, desc: 'Reachability test pattern definitions'
        # rubocop:enable Style/RedundantArrayConstructor
      end
      post 'reachability' do
        network, snapshots, test_pattern = %i[network snapshots test_pattern].map { |key| params[key] }
        tester = ReachTester.new(test_pattern)
        reach_results = tester.exec_all_traceroute_tests(network, snapshots)
        converter = ReachResultConverter.new(reach_results)

        # response
        {
          reach_results:,
          reach_results_summary: converter.summary,
          reach_results_summary_table: converter.full_table
        }
      end
    end
  end
end
