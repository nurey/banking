Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  post "/graphql", to: "graphql#execute"

  namespace :api do
    resources :receipts, only: %i[index show create update], param: :capture_id do
      get "images/:page", to: "receipt_images#show", as: :image, on: :member, constraints: { page: /\d+/ }
      get "thumbnail", to: "receipt_images#thumbnail", on: :member
    end
  end
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
