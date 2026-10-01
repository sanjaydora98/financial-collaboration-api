Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  post "auth/register", to: "authentication#register"
  post "auth/login", to: "authentication#login"
  post "auth/cable_ticket", to: "authentication#cable_ticket"
  get "auth/me", to: "authentication#me"
  delete "auth/logout", to: "authentication#logout"

  resources :teams, only: %i[index create show] do
    collection do
      post :join
    end
    post :bootstrap_admin, on: :member
    resources :memberships, controller: "team_memberships", only: %i[index create update destroy]
    resources :expenses, only: %i[index create show update destroy]
    post "expenses/:id/submit", to: "expenses#submit", as: :submit_expense
    post "expenses/:expense_id/approval", to: "expenses#approval", as: :review_expense
    post "expenses/:expense_id/reimbursement", to: "expenses#create_reimbursement", as: :create_expense_reimbursement
    resources :imports, only: %i[index create show] do
      resources :imported_transactions, only: %i[index show] do
        post :accept, on: :member
        post :reject, on: :member
      end
    end
    post "imported_transactions/bulk_review", to: "imported_transactions#bulk_review", as: :bulk_review_imported_transactions
  end

  # Defines the root path route ("/")
  # root "posts#index"
end
