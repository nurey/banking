module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :verify_origin
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      if cookies.signed[:session_id]
        Session.find_by(id: cookies.signed[:session_id], created_at: 30.days.ago..)
      end
    end

    def request_authentication
      head :unauthorized
    end

    def verify_origin
      return if request.get? || request.head? || request.options?

      allowed = ENV["CORS_ORIGINS"] || "http://localhost:3001"
      origin = request.headers["Origin"]

      head :forbidden unless origin.present? && origin == allowed
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = {
          value: session.id,
          expires: 30.days.from_now,
          httponly: true,
          secure: Rails.env.production?,
          same_site: Rails.env.production? ? :none : :lax
        }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
