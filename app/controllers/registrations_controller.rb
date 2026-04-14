class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: :create

  def create
    user = User.new(params.permit(:email_address, :password))
    if user.save
      start_new_session_for user
      render json: { user: user_json(user) }, status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    render json: { errors: [ "Email address has already been taken" ] }, status: :unprocessable_entity
  end

  private

  def user_json(user)
    { id: user.id, email_address: user.email_address }
  end
end
