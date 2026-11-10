# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Comment, type: :model do
  describe 'validations' do
    let(:blog) { Blog.create(title: 'Test', category: :hobby, content: 'test content') }

    it 'user_nameがない場合は無効であること' do
      comment = blog.comments.build(user_name: nil)
      expect(comment).to_not be_valid
    end

    it 'user_nameが上限 (50文字) ちょうどなら有効、超えると無効であること' do
      expect(blog.comments.build(user_name: 'a' * 50)).to be_valid
      expect(blog.comments.build(user_name: 'a' * 51)).to_not be_valid
    end

    it 'commentが上限 (2000文字) ちょうどなら有効、超えると無効であること' do
      expect(blog.comments.build(user_name: 'John', comment: 'a' * 2000)).to be_valid
      expect(blog.comments.build(user_name: 'John', comment: 'a' * 2001)).to_not be_valid
    end

    it 'commentが空でも有効であること (従来どおり)' do
      expect(blog.comments.build(user_name: 'John', comment: nil)).to be_valid
    end

    it 'blogがない場合は無効であること' do
      comment = Comment.new(user_name: 'John')
      expect(comment).to_not be_valid
    end
  end

  describe 'associations' do
    it 'Blogとのアソシエーション' do
      expect(Comment.reflect_on_association(:blog).macro).to eq :belongs_to
    end
  end
end
