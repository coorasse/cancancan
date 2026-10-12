# frozen_string_literal: true

require 'spec_helper'

# integration tests for latest ActiveRecord version.
RSpec.describe CanCan::ModelAdapters::ActiveRecordAdapter do
  let(:ability) { double.extend(CanCan::Ability) }
  let(:users_table) { Post.table_name }
  let(:posts_table) { Post.table_name }
  let(:likes_table) { Like.table_name }
  before :each do
    connect_db
    ActiveRecord::Migration.verbose = false

    ActiveRecord::Schema.define do
      create_table(:users) do |t|
        t.string :name
        t.timestamps null: false
      end

      create_table(:posts) do |t|
        t.string :title
        t.boolean :published, default: true
        t.integer :user_id
        t.timestamps null: false
      end

      create_table(:likes) do |t|
        t.integer :post_id
        t.integer :user_id
        t.timestamps null: false
      end

      create_table(:editors) do |t|
        t.integer :post_id
        t.integer :user_id
        t.timestamps null: false
      end
    end

    class User < ActiveRecord::Base
      has_many :posts
      has_many :likes
      has_many :editors
    end

    class Post < ActiveRecord::Base
      belongs_to :user
      has_many :likes
      has_many :editors
    end

    class Like < ActiveRecord::Base
      belongs_to :user
      belongs_to :post
    end

    class Editor < ActiveRecord::Base
      belongs_to :user
      belongs_to :post
    end
  end

  before do
    @user1 = User.create!
    @user2 = User.create!
    @post1 = Post.create!(title: 'post1', user: @user1)
    @post2 = Post.create!(user: @user1, published: false)
    @post3 = Post.create!(user: @user2)
    @like1 = Like.create!(post: @post1, user: @user1)
    @like2 = Like.create!(post: @post1, user: @user2)
    @editor1 = Editor.create(user: @user1, post: @post2)
    ability.can :read, Post, user_id: @user1
    ability.can :read, Post, editors: { user_id: @user1 }
  end

  describe 'preloading of associations' do
    it 'preloads associations correctly' do
      posts = Post.accessible_by(ability).where(published: true).includes(likes: :user)
      expect(posts[0].association(:likes)).to be_loaded
      expect(posts[0].likes[0].association(:user)).to be_loaded
    end
  end

  describe 'filtering of results' do
    it 'adds the where clause correctly' do
      posts = Post.accessible_by(ability).where(published: true)
      expect(posts.length).to eq 1
    end
  end

  describe 'selecting custom columns' do
    it 'extracts custom columns correctly' do
      posts = Post.accessible_by(ability).where(published: true).select('title as mytitle')
      expect(posts[0].mytitle).to eq 'post1'
    end
  end
end
