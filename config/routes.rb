Rails.application.routes.draw do
  resources :credit_card_transactions, only: :index do
    collection do
      get 'debits'
    end
  end
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
end
