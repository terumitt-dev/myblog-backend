# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.11'

# Rails 8
gem 'rails', '~> 8.0'

# Asset pipeline
gem 'sprockets-rails', '~> 3.4' # Rails 8 対応版で最新

# DB
gem 'pg', '~> 1.5'

# Webサーバー
gem 'puma', '~> 7.2' # Rails 8 で推奨される 6 系最新

# JavaScript & Hotwire
gem 'importmap-rails', '~> 1.2'
gem 'stimulus-rails', '~> 1.2'
gem 'turbo-rails', '~> 1.4'

# JSON builder
gem 'jbuilder', '~> 2.14' # 最新安定版

# 認証系
gem 'devise', '~> 5.0' # 最新安定版 4.9.4
gem 'devise-i18n', '~> 1.11'
gem 'devise-jwt', '~> 0.11'
gem 'jwt', '~> 3.2'

# CORS対応
gem 'rack-cors', '~> 2.0'

# レートリミット（パスワードリセット等の総当たり攻撃対策）
gem 'rack-attack', '~> 6.7'

# 永続的な ActiveJob キュー（パスワードリセットメール等の deliver_later に使用）
# Postgres ベースで Redis 不要、Puma plugin で in-process 実行可能（worker 別 Pod 不要）
gem 'solid_queue', '~> 1.0'

# 永続的な Rails.cache 実装（Rack::Attack のレート制限カウンタ共有用）
# Postgres ベースで Redis 不要。複数 Puma worker / 複数 Pod 構成でも
# カウンタを共有することで、password_reset/global などの全体スロットリングが
# プロセスをまたいで正しく機能する。
gem 'solid_cache', '~> 1.0'

# 画像ストレージ（Active Storage + S3）
gem 'aws-sdk-s3', require: false
gem 'image_processing', '~> 1.2'

# Windows 専用
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

# Boot & logger
gem 'bootsnap', '~> 1.16', require: false
gem 'logger', '~> 1.7'

group :development, :test do
  gem 'debug', platforms: %i[mri mingw x64_mingw]
  gem 'rspec-rails', '~> 6.0'
  gem 'rubocop', require: false
  gem 'rubocop-capybara', require: false
  gem 'rubocop-factory_bot', require: false
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'rubocop-rspec_rails', require: false
end

group :development do
  gem 'web-console', '~> 4.2'
  # gem "rack-mini-profiler", '~> 3.2'
  # gem "spring", '~> 3.2'
end

group :test do
  gem 'capybara', '~> 3.39'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'selenium-webdriver', '~> 4.44'
end
