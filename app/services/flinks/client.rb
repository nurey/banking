require "net/http"
require "json"

module Flinks
  class Client
    BASE_URL = "https://%{instance}-api.private.fin.ag/v3/%{customer_id}/BankingServices"

    def initialize(
      customer_id: Rails.application.credentials.dig(:flinks, :customer_id),
      auth_key: Rails.application.credentials.dig(:flinks, :auth_key),
      api_key: Rails.application.credentials.dig(:flinks, :api_key),
      instance: Rails.application.credentials.dig(:flinks, :instance) || "toolbox"
    )
      @base_url = BASE_URL % { instance: instance, customer_id: customer_id }
      @auth_key = auth_key
      @api_key = api_key
    end

    def generate_token
      response = post("GenerateAuthorizeToken", {}, headers: { "flinks-auth-key" => @auth_key })
      response["Token"]
    end

    def authorize(institution:, username:, password:)
      token = generate_token
      response = post("Authorize", {
        Institution: institution,
        Username: username,
        Password: password,
        MostRecentCached: true,
        Save: true
      }, headers: { "flinks-auth-key" => token })

      {
        request_id: response["RequestId"],
        login_id: response.dig("Login", "Id"),
        institution: response["Institution"]
      }
    end

    def authorize_with_login_id(login_id:)
      token = generate_token
      response = post("Authorize", {
        LoginId: login_id,
        MostRecentCached: true
      }, headers: { "flinks-auth-key" => token })

      {
        request_id: response["RequestId"],
        login_id: response.dig("Login", "Id"),
        institution: response["Institution"]
      }
    end

    def fetch_transactions(request_id:, days: "Days90")
      response = post("GetAccountsDetail", {
        RequestId: request_id,
        WithTransactions: true,
        DaysOfTransactions: days
      }, headers: { "x-api-key" => @api_key })

      accounts = response["Accounts"] || []
      accounts.flat_map do |account|
        (account["Transactions"] || []).map do |tx|
          {
            date: tx["Date"],
            description: tx["Description"],
            debit: tx["Debit"],
            credit: tx["Credit"],
            account_id: account["Id"],
            last_four_digits: account["LastFourDigits"]
          }
        end
      end
    end

    private

    def post(endpoint, body, headers:)
      uri = URI("#{@base_url}/#{endpoint}")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      headers.each { |k, v| request[k] = v }
      request.body = body.to_json unless body.empty?

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.request(request)
      end

      handle_response(response)
    end

    def handle_response(response)
      body = JSON.parse(response.body)

      case response.code.to_i
      when 200, 201
        body
      when 401, 403
        raise Flinks::AuthenticationError, body["Message"] || "Authentication failed"
      when 429
        raise Flinks::RateLimitError, body["Message"] || "Rate limited"
      else
        raise Flinks::ApiError, body["Message"] || "Flinks API error (#{response.code})"
      end
    end
  end
end
