# frozen_string_literal: true

FactoryBot.define do
  factory :admin do
    email { 'test@email.com' }
    password { 'password12345' }
    password_confirmation { 'password12345' }
  end
end
