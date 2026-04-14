class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: :update

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      render json: { message: "Password has been reset." }, status: :ok
    else
      render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      render json: { error: "Password reset link is invalid or has expired." }, status: :unprocessable_entity
    end
end
