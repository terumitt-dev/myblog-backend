# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += %i[
  passw email secret token _key crypt salt certificate otp ssn cvv cvc
]

# X 連携 (OAuth) の callback で渡る認可 code / state。Rails は "Started GET ...?code=..."
# と "Parameters: {...}" を標準でログに出すため、ここで明示的にマスクする
# (code / state は一般的な語で部分一致だと無関係なキーまで隠すため、完全一致にしている)。
Rails.application.config.filter_parameters << /\A(?:code|state)\z/
