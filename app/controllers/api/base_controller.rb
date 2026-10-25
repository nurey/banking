# rbs_inline: enabled
# frozen_string_literal: true

module Api
  class BaseController < ActionController::API
    include ApiTokenAuthenticatable

    rescue_from ActiveRecord::RecordNotFound do
      render_errors "Not found", status: :not_found
    end

    private

    # @rbs errors: String | Array[String]
    # @rbs status: Symbol
    # @rbs return: void
    def render_errors(errors, status:)
      render json: { errors: Array(errors) }, status:
    end

    # Receipts are only ever found by the device's capture_id. A value that
    # isn't a UUID (a numeric id, say) casts to NULL and matches nothing.
    #
    # @rbs return: Receipt
    def find_receipt
      Receipt.find_by!(capture_id: params[:capture_id])
    end
  end
end
