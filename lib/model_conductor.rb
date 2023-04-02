# frozen_string_literal: true

require 'logger'
require_relative 'api/mddo_rest_api_client'

# Model conductor module
module ModelConductor
  # module common logger
  @logger = Logger.new($stderr)
  @logger.progname = 'model-conductor'
  @logger.level = case ENV.fetch('MODEL_CONDUCTOR_LOG_LEVEL', 'info')
                  when /fatal/i
                    Logger::FATAL
                  when /error/i
                    Logger::ERROR
                  when /warn/i
                    Logger::WARN
                  when /debug/i
                    Logger::DEBUG
                  else
                    Logger::INFO # default
                  end

  # rest api client (backend interface)
  @rest_api = MddoRestApiClient.new(@logger)

  module_function

  # @return [Logger] Logger
  def logger
    @logger
  end

  # @return [MddoRestApiClient] REST API client
  def rest_api
    @rest_api
  end
end
