# frozen_string_literal: true

class Comment < ApplicationRecord
  # 未認証で誰でも投稿できるため、サーバー側で長さの上限を持つ
  # (フロントの入力制限は API を直接叩けば回避できる)。
  USER_NAME_MAX_LENGTH = 50
  COMMENT_MAX_LENGTH = 2000

  belongs_to :blog
  validates :user_name, presence: true, length: { maximum: USER_NAME_MAX_LENGTH }
  validates :comment, length: { maximum: COMMENT_MAX_LENGTH }
end
