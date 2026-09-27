# frozen_string_literal: true

Rails.application.routes.draw do
  # K8s liveness/readiness probe用ヘルスチェック
  get 'up' => 'rails/health#show', as: :rails_health_check

  # SECRET 保護のない Devise デフォルトの /admins/password 経路を無効化することで、
  # 下の `/api/auth/password` (PASSWORD_RESET_SECRET 必須) を迂回できないようにする
  devise_for :admins, skip: [:sessions, :registrations, :passwords]

  namespace :api do
    namespace :auth do
      post 'sign_up', to: 'registrations#create'
      post 'sign_in', to: 'sessions#create'
      delete 'sign_out', to: 'sessions#destroy'
      get 'current_user', to: 'current_users#show'
      # パスワードリセット（SECRET保護）
      post 'password', to: 'passwords#create'
      patch 'password', to: 'passwords#update'
    end

    resources :blogs, only: %i[index show] do
      resources :comments, only: %i[index create]
    end

    namespace :admin do
      resources :blogs do
        collection do
          post :import_mt
        end
        member do
          post :tweet
        end
      end
      resources :images, only: [:create]
    end
  end
end
