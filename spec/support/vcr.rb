require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = { record: ENV["VCR_RECORD"]&.to_sym || :none }
  config.filter_sensitive_data("<FLINKS_CUSTOMER_ID>") { Rails.application.credentials.dig(:flinks, :customer_id) }
  config.filter_sensitive_data("<FLINKS_API_SECRET>") { Rails.application.credentials.dig(:flinks, :api_secret) }
end
