require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = { record: ENV["VCR_RECORD"]&.to_sym || :none }
  config.filter_sensitive_data("<FLINKS_CUSTOMER_ID>") { Rails.application.credentials.dig(:flinks, :customer_id) }
  config.filter_sensitive_data("<FLINKS_AUTH_KEY>") { Rails.application.credentials.dig(:flinks, :auth_key) }
  config.filter_sensitive_data("<FLINKS_API_KEY>") { Rails.application.credentials.dig(:flinks, :api_key) }
  config.filter_sensitive_data("<FLINKS_USERNAME>") { Rails.application.credentials.dig(:flinks, :demo_username) }
  config.filter_sensitive_data("<FLINKS_PASSWORD>") { Rails.application.credentials.dig(:flinks, :demo_password) }

  config.before_record do |interaction|
    interaction.request.body&.gsub!(/"Username":"[^"]*"/, '"Username":"<FILTERED>"')
    interaction.request.body&.gsub!(/"Password":"[^"]*"/, '"Password":"<FILTERED>"')
    interaction.response.body&.gsub!(/"Username":"[^"]*"/, '"Username":"<FILTERED>"')
  end
end
