Rails.application.routes.draw do
  post "/graphql", to: "graphql#execute"
  resources :credit_card_transactions, only: :index do
    collection do
      get 'debits'
      get 'debits_outstanding'
    end
  end
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
