# frozen_string_literal: true

# 記事の新規作成後に myblog-dispatch へツイート投稿をリクエストする非同期ジョブ。
#
# 設計方針:
# - 失敗しても記事の保存自体には一切影響させない (SolidQueue のジョブとして
#   completely 切り離す)。X 連携は付加機能であり、ここで例外を伝播させて
#   controller のレスポンスを壊すべきではない。
# - 失敗時は管理画面から手動でツイートを再送できる想定
#   (Api::Admin::BlogsController#tweet)。ここでは自動リトライは行わず、
#   ログに残すだけに留める。
class TweetNotificationJob < ApplicationJob
  queue_as :default

  def perform(blog_id:)
    blog = Blog.find_by(id: blog_id)
    unless blog
      Rails.logger.warn("TweetNotificationJob: blog not found (id=#{blog_id})")
      return
    end

    DispatchClient.post_tweet(title: blog.title, url: blog.public_url)
  rescue DispatchClient::ConfigurationMissing => e
    Rails.logger.info("TweetNotificationJob: dispatch not configured, skipping (blog_id=#{blog_id}): #{e.message}")
  rescue DispatchClient::RequestFailed => e
    Rails.logger.error("TweetNotificationJob: failed to post tweet (blog_id=#{blog_id}): #{e.message}")
  end
end
