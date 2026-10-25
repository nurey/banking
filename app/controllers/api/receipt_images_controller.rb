# rbs_inline: enabled
# frozen_string_literal: true

module Api
  # Page images and thumbnails, behind the API token. Active Storage's own
  # routes are off (config.active_storage.draw_routes = false).
  class ReceiptImagesController < BaseController
    # @rbs return: void
    def show
      # The route only matches digits, so a negative OFFSET can't reach Postgres.
      page = Integer(params[:page], 10)
      image = find_receipt.images.order(:id).offset(page).first!
      send_data image.download, type: image.content_type, disposition: "inline"
    end

    # @rbs return: void
    def thumbnail
      thumbnail = find_receipt.thumbnail
      raise ActiveRecord::RecordNotFound unless thumbnail.attached?

      expires_in 365.days, public: false, immutable: true # a thumbnail never changes
      send_data thumbnail.download, type: thumbnail.content_type, disposition: "inline"
    end
  end
end
