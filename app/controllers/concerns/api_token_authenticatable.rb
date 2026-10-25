# rbs_inline: enabled
# frozen_string_literal: true

# One static bearer token, RECEIPTS_API_TOKEN. Tailscale is the main gate, but
# kamal-proxy on optiplex also listens on the home LAN, where anything on the
# Wi-Fi can reach it. If the variable is unset, every request is refused.
module ApiTokenAuthenticatable
  extend ActiveSupport::Concern
  include ActionController::HttpAuthentication::Token::ControllerMethods

  included { before_action :authenticate_api_token! }

  private

  # @rbs return: void
  def authenticate_api_token!
    expected = ENV["RECEIPTS_API_TOKEN"].to_s
    authenticated = authenticate_with_http_token do |token, _options|
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
    end
    return if authenticated

    headers["WWW-Authenticate"] = %(Token realm="Application")
    render json: { errors: [ "Token rejected" ] }, status: :unauthorized
  end
end
