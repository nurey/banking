class SessionsController < ApplicationController
  allow_unauthenticated_access only: :create
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { render json: { error: "Try again later." }, status: :too_many_requests }

  def show
    render json: { user: user_json(Current.user) }
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      render json: { user: user_json(user) }, status: :created
    else
      render json: { error: "Invalid email address or password." }, status: :unauthorized
    end
  end

  def destroy
    terminate_session
    render json: { message: "Logged out." }, status: :ok
  end

  private

  def user_json(user)
    { id: user.id, email_address: user.email_address }
  end
end
