# frozen_string_literal: true

RSpec.shared_context 'with mocked rest_api' do
  let(:mock_rest_api) { instance_double(ModelConductor::MddoRestApiClient) }

  before do
    allow(ModelConductor).to receive(:rest_api).and_return(mock_rest_api)
  end
end
