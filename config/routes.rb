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

    # X (Twitter) OAuth のリダイレクト先。X からのブラウザ遷移は管理画面の JWT を
    # 持てないため admin 名前空間の認証対象外 (別コントローラー)。パスは X Developer
    # Portal の Callback URI および myblog-dispatch の X_OAUTH_REDIRECT_URI と完全一致させる。
    get 'admin/x/callback', to: 'x_callbacks#show'

    namespace :admin do
      post 'x/connect', to: 'x_connections#create'
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
