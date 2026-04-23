Rails.application.routes.draw do
  resource :session, only: %i[show create destroy]
  resource :registration, only: :create
  resources :passwords, param: :token
  get 'up' => 'rails/health#show', as: :rails_health_check

  post '/graphql', to: 'graphql#execute'
  resources :credit_card_transactions, only: :index do
    collection do
      get 'debits'
      get 'debits_outstanding'
      get 'debits_with_credits'
    end
  end
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
