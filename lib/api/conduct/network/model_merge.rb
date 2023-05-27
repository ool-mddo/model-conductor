# frozen_string_literal: true

require 'grape'

module ModelConductor
  module ApiRoute
    # namespace /model_merge
    class ModelMerge < Grape::API
      params do
        requires :src_ss, type: String, desc: 'Source snapshot name (as-is)'
        requires :dst_ss, type: String, desc: 'Destination snapshot name (to-be)'
      end
      resource 'model_merge/:src_ss/:dst_ss' do
        desc 'Get configs by model based diff'
        get do
          network, src_ss, dst_ss = %i[network src_ss dst_ss].map { |key| params[key] }
          begin
            # response
            rest_api.fetch_config_delta(network, src_ss, dst_ss)
          rescue StandardError => e
            error!("Model-merge failed: #{e}", 500)
          end
        end
      end
    end
  end
end
