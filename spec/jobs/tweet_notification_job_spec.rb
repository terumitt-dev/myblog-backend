# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TweetNotificationJob, type: :job do
  let(:blog) { FactoryBot.create(:blog) }

  describe '#perform' do
    it 'DispatchClient.post_tweet をブログのタイトルと公開URLで呼び出すこと' do
      allow(DispatchClient).to receive(:post_tweet)

      described_class.perform_now(blog_id: blog.id)

      expect(DispatchClient).to have_received(:post_tweet).with(title: blog.title, url: blog.public_url)
    end

    it '対象のブログが存在しない場合、DispatchClient を呼び出さず警告ログを出すこと' do
      allow(DispatchClient).to receive(:post_tweet)
      allow(Rails.logger).to receive(:warn).and_call_original

      described_class.perform_now(blog_id: -1)

      expect(DispatchClient).not_to have_received(:post_tweet)
      expect(Rails.logger).to have_received(:warn).with(/blog not found/)
    end

    it 'DispatchClient::ConfigurationMissing を握りつぶして info ログに残すこと' do
      allow(DispatchClient).to receive(:post_tweet).and_raise(DispatchClient::ConfigurationMissing, 'not configured')
      allow(Rails.logger).to receive(:info).and_call_original

      expect { described_class.perform_now(blog_id: blog.id) }.not_to raise_error
      expect(Rails.logger).to have_received(:info).with(/dispatch not configured/)
    end

    it 'DispatchClient::RequestFailed を握りつぶして error ログに残すこと' do
      allow(DispatchClient).to receive(:post_tweet).and_raise(DispatchClient::RequestFailed, 'boom')
      allow(Rails.logger).to receive(:error).and_call_original

      expect { described_class.perform_now(blog_id: blog.id) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/failed to post tweet/)
    end
  end
end
