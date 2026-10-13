# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CanCan::ModelAdapters::ActiveRecordAdapter do
  let(:true_v) do
    ActiveRecord::Base.connection.quoted_true
  end
  let(:false_v) do
    ActiveRecord::Base.connection.quoted_false
  end

  let(:false_condition) { '1=0' }

  before :each do
    connect_db
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Schema.define do
      create_table(:categories) do |t|
        t.string :name
        t.boolean :visible
        t.timestamps null: false
      end

      create_table(:projects) do |t|
        t.string :name
        t.timestamps null: false
      end

      create_table(:companies) do |t|
        t.boolean :admin
      end

      create_table(:articles) do |t|
        t.string :name
        t.timestamps null: false
        t.boolean :published
        t.boolean :secret
        t.integer :priority
        t.integer :category_id
        t.integer :project_id
        t.integer :user_id
      end

      create_table(:comments) do |t|
        t.boolean :spam
        t.integer :article_id
        t.integer :project_id
        t.timestamps null: false
      end

      create_table(:legacy_comments) do |t|
        t.integer :post_id
        t.timestamps null: false
      end

      create_table(:legacy_mentions) do |t|
        t.integer :user_id
        t.integer :article_id
        t.timestamps null: false
      end

      create_table(:attachments) do |t|
        t.integer :attachable_id
        t.string :attachable_type
        t.timestamps null: false
      end

      create_table(:users) do |t|
        t.string :name
        t.timestamps null: false
      end
    end

    class Project < ActiveRecord::Base
      has_many :articles
      has_many :comments
    end

    class Category < ActiveRecord::Base
      has_many :articles
    end

    class Company < ActiveRecord::Base
    end

    class Article < ActiveRecord::Base
      belongs_to :category
      belongs_to :company
      has_many :comments
      has_many :mentions
      has_many :mentioned_users, through: :mentions, source: :user
      belongs_to :user
      belongs_to :project
      has_many :attachments, as: :attachable

      scope :unpopular, lambda {
        joins('LEFT OUTER JOIN comments ON (comments.post_id = posts.id)')
          .group('articles.id')
          .where('COUNT(comments.id) < 3')
      }
    end

    class Mention < ActiveRecord::Base
      self.table_name = 'legacy_mentions'
      belongs_to :user
      belongs_to :article
    end

    class Comment < ActiveRecord::Base
      belongs_to :article
      belongs_to :project
      has_many :attachments, as: :attachable
    end

    class LegacyComment < ActiveRecord::Base
      belongs_to :article, foreign_key: 'post_id'
      belongs_to :project
    end

    class Attachment < ActiveRecord::Base
      belongs_to :attachable, polymorphic: true
    end

    class User < ActiveRecord::Base
      has_many :articles
      has_many :mentions
      has_many :mentioned_articles, through: :mentions, source: :article
      has_many :comments, through: :articles
      has_many :published_articles, -> { where(published: true) }, class_name: 'Article'
    end

    (@ability = double).extend(CanCan::Ability)
    @article_table = Article.table_name
    @comment_table = Comment.table_name
  end

  CanCan.valid_accessible_by_strategies.each do |strategy|
    context "base functionality with #{strategy} strategy" do
      before :each do
        CanCan.accessible_by_strategy = strategy
      end

      it 'does not fires query with accessible_by() for abilities defined with association' do
        user = User.create!
        @ability.can :edit, Article, user.articles.unpopular
        callback = ->(*) { raise 'No query expected' }

        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          Article.accessible_by(@ability, :edit)
          nil
        end
      end

      it 'fetches only the articles that are published' do
        @ability.can :read, Article, published: true
        article1 = Article.create!(published: true)
        Article.create!(published: false)
        expect(Article.accessible_by(@ability)).to eq([article1])
      end

      it 'is for only active record classes' do
        expect(CanCan::ModelAdapters::ActiveRecordAdapter).to_not be_for_class(Object)
        expect(CanCan::ModelAdapters::ActiveRecordAdapter).to be_for_class(Article)
        expect(CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article))
          .to eq(CanCan::ModelAdapters::ActiveRecordAdapter)
      end

      it 'finds record' do
        article = Article.create!
        adapter = CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article)
        expect(adapter.find(Article, article.id)).to eq(article)
      end

      it 'does not fetch any records when no abilities are defined' do
        Article.create!
        expect(Article.accessible_by(@ability)).to be_empty
      end

      it 'fetches all articles when one can read all' do
        @ability.can :read, Article
        article = Article.create!
        expect(Article.accessible_by(@ability)).to match_array([article])
      end

      it 'fetches only the articles that are published' do
        @ability.can :read, Article, published: true
        article1 = Article.create!(published: true)
        Article.create!(published: false)
        expect(Article.accessible_by(@ability)).to match_array([article1])
      end

      it 'fetches any articles which are published or secret' do
        @ability.can :read, Article, published: true
        @ability.can :read, Article, secret: true
        article1 = Article.create!(published: true, secret: false)
        article2 = Article.create!(published: true, secret: true)
        article3 = Article.create!(published: false, secret: true)
        Article.create!(published: false, secret: false)
        expect(Article.accessible_by(@ability)).to match_array([article1, article2, article3])
      end

      it 'fetches any articles which we are cited in' do
        user = User.create!
        cited = Article.create!
        Article.create!
        cited.mentioned_users << user
        @ability.can :read, Article, mentioned_users: { id: user.id }
        @ability.can :read, Article, mentions: { user_id: user.id }
        expect(Article.accessible_by(@ability)).to match_array([cited])
      end

      it 'fetches only the articles that are published and not secret' do
        @ability.can :read, Article, published: true
        @ability.cannot :read, Article, secret: true
        article1 = Article.create!(published: true, secret: false)
        Article.create!(published: true, secret: true)
        Article.create!(published: false, secret: true)
        Article.create!(published: false, secret: false)
        expect(Article.accessible_by(@ability)).to match_array([article1])
      end

      it 'only reads comments for articles which are published' do
        @ability.can :read, Comment, article: { published: true }
        comment1 = Comment.create!(article: Article.create!(published: true))
        Comment.create!(article: Article.create!(published: false))
        expect(Comment.accessible_by(@ability)).to match_array([comment1])
      end

      it 'should only read articles which are published or in visible categories' do
        @ability.can :read, Article, category: { visible: true }
        @ability.can :read, Article, published: true
        article1 = Article.create!(published: true)
        Article.create!(published: false)
        article3 = Article.create!(published: false, category: Category.create!(visible: true))
        expect(Article.accessible_by(@ability)).to match_array([article1, article3])
      end

      it 'should only read categories once even if they have multiple articles' do
        @ability.can :read, Category, articles: { published: true }
        @ability.can :read, Article, published: true
        category = Category.create!
        Article.create!(published: true, category: category)
        Article.create!(published: true, category: category)
        expect(Category.accessible_by(@ability)).to match_array([category])
      end

      it 'only reads comments for visible categories through articles' do
        @ability.can :read, Comment, article: { category: { visible: true } }
        comment1 = Comment.create!(article: Article.create!(category: Category.create!(visible: true)))
        Comment.create!(article: Article.create!(category: Category.create!(visible: false)))
        expect(Comment.accessible_by(@ability)).to match_array([comment1])
        expect(Comment.accessible_by(@ability).count).to eq(1)
      end

      it 'allows conditions in SQL and merge with hash conditions' do
        @ability.can :read, Article, published: true
        @ability.can :read, Article, ['secret=?', true]
        article1 = Article.create!(published: true, secret: false)
        article2 = Article.create!(published: true, secret: true)
        article3 = Article.create!(published: false, secret: true)
        Article.create!(published: false, secret: false)
        expect(Article.accessible_by(@ability)).to match_array([article1, article2, article3])
      end

      it 'allows a scope for conditions' do
        @ability.can :read, Article, Article.where(secret: true)
        article1 = Article.create!(secret: true)
        Article.create!(secret: false)
        expect(Article.accessible_by(@ability)).to match_array([article1])
      end

      it 'matches records for can? when a condition value is an ActiveRecord relation selecting ids' do
        user = User.create!(name: 'Arthur Dent')
        article = Article.create!(name: 'How to fly', user: user)
        other_article = Article.create!(name: 'Mostly Harmless')
        ability = Ability.new(user)

        ability.can :read, Article, id: Article.where(user_id: user.id).select(:id)

        expect(Article.accessible_by(ability)).to match_array([article])
        expect(ability.can?(:read, article)).to eq(true)
        expect(ability.can?(:read, other_article)).to eq(false)
      end

      it 'matches records for can? when a condition value is an ActiveRecord relation selecting names' do
        user = User.create!(name: 'Arthur Dent')
        article = Article.create!(name: 'How to fly', user: user)
        other_article = Article.create!(name: 'Mostly Harmless')
        ability = Ability.new(user)

        ability.can :read, Article, name: Article.where(user_id: user.id).select(:name)

        expect(Article.accessible_by(ability)).to match_array([article])
        expect(ability.can?(:read, article)).to eq(true)
        expect(ability.can?(:read, other_article)).to eq(false)
      end

      it 'fetches only associated records when using with a scope for conditions' do
        @ability.can :read, Article, Article.where(secret: true)
        category1 = Category.create!(visible: false)
        category2 = Category.create!(visible: true)
        article1 = Article.create!(secret: true, category: category1)
        Article.create!(secret: true, category: category2)
        expect(category1.articles.accessible_by(@ability)).to match_array([article1])
      end

      it 'keeps the conditions of the association when the scope constrains the same column' do
        category1 = Category.create!
        category2 = Category.create!
        @ability.can :read, Article, Article.where(category_id: [category1.id, category2.id])
        article1 = Article.create!(category: category1)
        Article.create!(category: category2)

        expect(category1.articles.accessible_by(@ability)).to match_array([article1])
        expect(Article.accessible_by(@ability).count).to eq(2)
      end

      it 'keeps the conditions of the base relation on a subquery when using a scope for conditions' do
        category1 = Category.create!
        category2 = Category.create!
        @ability.can :read, Article, Article.where(secret: true)
        article1 = Article.create!(secret: true, category: category1)
        Article.create!(secret: true, category: category2)
        Article.create!(secret: false, category: category1)

        articles = Article.where(category: Category.where(id: category1.id)).accessible_by(@ability)
        expect(articles).to match_array([article1])
      end

      it 'merges a scope with hash conditions' do
        @ability.can :read, Article, published: true
        @ability.can :read, Article, Article.where(secret: true)
        published = Article.create!(published: true, secret: false)
        secret = Article.create!(published: false, secret: true)
        Article.create!(published: false, secret: false)
        expect(Article.accessible_by(@ability)).to contain_exactly(published, secret)
      end

      it 'merges several scopes' do
        @ability.can :read, Article, Article.where(published: true)
        @ability.can :read, Article, Article.where(secret: true)
        @ability.cannot :read, Article, Article.where(priority: 1)
        published = Article.create!(published: true, secret: false)
        secret = Article.create!(published: false, secret: true)
        Article.create!(published: true, secret: true, priority: 1)
        Article.create!(published: false, secret: false)
        expect(Article.accessible_by(@ability)).to contain_exactly(published, secret)
      end

      it 'merges a scope with a join with conditions on an association' do
        @ability.can :read, Article, Article.joins(:category).where(categories: { visible: true })
        @ability.can :read, Article, project: { name: 'cancancan' }
        visible = Category.create!(visible: true)
        hidden = Category.create!(visible: false)
        project = Project.create!(name: 'cancancan')
        in_visible_category = Article.create!(category: visible)
        in_project = Article.create!(category: hidden, project: project)
        without_category = Article.create!(project: project)
        Article.create!(category: hidden)
        expect(Article.accessible_by(@ability)).to contain_exactly(in_visible_category, in_project, without_category)
      end

      it 'does not duplicate the records matched several times by the join of a scope' do
        @ability.can :read, Article, Article.joins(:comments).where(comments: { spam: false })
        @ability.can :read, Article, project: { name: 'cancancan' }
        commented = Article.create!(project: Project.create!(name: 'cancancan'))
        2.times { commented.comments.create!(spam: false) }
        Article.create!.comments.create!(spam: true)
        expect(Article.accessible_by(@ability).to_a).to eq([commented])
      end

      it 'merges a scope with a join without conditions' do
        @ability.can :read, Article, published: true
        @ability.can :read, Article, Article.joins(:comments)
        published = Article.create!(published: true)
        commented = Article.create!(published: false)
        2.times { commented.comments.create! }
        Article.create!(published: false)
        expect(Article.accessible_by(@ability).to_a).to contain_exactly(published, commented)
      end

      it 'ignores the select and the order of a scope' do
        @ability.can :read, Article, Article.where(published: true).order(:priority).select(:id)
        @ability.can :read, Article, secret: true
        published = Article.create!(published: true, priority: 2)
        secret = Article.create!(secret: true, priority: 1)
        expect(Article.accessible_by(@ability).order(:priority).map(&:priority)).to eq([1, 2])
        expect(Article.accessible_by(@ability)).to contain_exactly(published, secret)
      end

      # MySQL does not support a LIMIT in an IN subquery, so a scope with a limit cannot be used as a rule there.
      it 'applies the limit of a scope in a subquery, without applying it to the other rules' do
        @ability.can :read, Article, Article.where(published: true).order(:priority).limit(1)
        @ability.can :read, Article, secret: true
        first = Article.create!(published: true, priority: 1)
        Article.create!(published: true, priority: 2)
        secret = Article.create!(secret: true, priority: 3)
        expect(Article.accessible_by(@ability).to_sql).to include('"articles"."id" IN (SELECT "articles"."id"')
        expect(Article.accessible_by(@ability).to_sql).to include('LIMIT 1)')
        expect(Article.accessible_by(@ability)).to contain_exactly(first, secret)
      end

      it 'does not fetch any records for an empty scope' do
        @ability.can :read, Article, published: true
        @ability.can :read, Article, Article.none
        @ability.cannot :read, Article, Article.none
        published = Article.create!(published: true)
        Article.create!(published: false)
        expect(Article.accessible_by(@ability)).to contain_exactly(published)
      end

      it 'negates the scope of a cannot rule' do
        @ability.can :read, Article
        @ability.cannot :read, Article, Article.where(secret: true)
        public = Article.create!(secret: false)
        unknown = Article.create!(secret: nil)
        Article.create!(secret: true)
        expect(Article.accessible_by(@ability)).to contain_exactly(public, unknown)
      end

      it 'does not load the records of a scope to build the query' do
        @ability.can :read, Article, Article.joins(:category).where(categories: { visible: true })
        @ability.can :read, Article, project: { name: 'cancancan' }
        Article.create!(category: Category.create!(visible: true))
        expect(count_queries { Article.accessible_by(@ability).to_sql }).to eq(0)
      end

      it 'negates a scope with a join of a cannot rule without excluding the records without the association' do
        @ability.can :read, Article
        @ability.cannot :read, Article, Article.joins(:category).where(categories: { visible: false })
        visible = Article.create!(category: Category.create!(visible: true))
        Article.create!(category: Category.create!(visible: false))
        without_category = Article.create!
        expect(Article.accessible_by(@ability)).to contain_exactly(visible, without_category)
      end

      it 'merges a scope with eager loading with conditions on an association' do
        scope = Article.includes(:category).references(:categories).where(categories: { visible: true })
        @ability.can :read, Article, scope
        @ability.can :read, Article, project: { name: 'cancancan' }
        in_visible_category = Article.create!(category: Category.create!(visible: true))
        in_project = Article.create!(project: Project.create!(name: 'cancancan'))
        Article.create!(category: Category.create!(visible: false))
        expect(Article.accessible_by(@ability)).to contain_exactly(in_visible_category, in_project)
      end

      it 'keeps the conditions of the association when a scope has a join' do
        @ability.can :read, Article, Article.joins(:category).where(categories: { visible: true })
        category = Category.create!(visible: true)
        article = Article.create!(category: category)
        Article.create!(category: Category.create!(visible: true))
        expect(category.articles.accessible_by(@ability)).to contain_exactly(article)
      end

      it 'merges SQL conditions, a scope and a cannot rule' do
        @ability.can :read, Article, ['published = ?', true]
        @ability.can :read, Article, Article.where(secret: true)
        @ability.cannot :read, Article, priority: 1
        published = Article.create!(published: true)
        secret = Article.create!(secret: true)
        Article.create!(published: true, priority: 1)
        Article.create!(secret: true, priority: 1)
        Article.create!
        expect(Article.accessible_by(@ability)).to contain_exactly(published, secret)
      end

      it 'merges a scope built with or' do
        @ability.can :read, Article, Article.where(published: true).or(Article.where(secret: true))
        @ability.cannot :read, Article, priority: 1
        published = Article.create!(published: true)
        secret = Article.create!(secret: true)
        Article.create!(published: true, priority: 1)
        Article.create!
        expect(Article.accessible_by(@ability)).to contain_exactly(published, secret)
      end

      it 'does not fetch any records when the rule with scope is suppressed' do
        @ability.can :read, Article, published: true
        @ability.can :read, Article, Article.where(secret: true)
        @ability.cannot :read, Article
        Article.create!(published: true, secret: true)
        expect(Article.accessible_by(@ability)).to be_empty
      end

      it 'recognises empty scopes and compresses them' do
        @ability.can :read, Article, published: true
        @ability.can :read, Article, Article.all
        expect { Article.accessible_by(@ability) }.not_to raise_error
      end

      it 'does not allow to fetch records when ability with just block present' do
        @ability.can :read, Article do
          false
        end
        expect { Article.accessible_by(@ability) }.to raise_error(CanCan::Error)
      end

      it 'should support more than one deeply nested conditions' do
        @ability.can :read, Comment, article: {
          category: {
            name: 'foo', visible: true
          }
        }
        expect { Comment.accessible_by(@ability) }.to_not raise_error
      end

      it 'does not allow to check ability on object against SQL conditions without block' do
        @ability.can :read, Article, ['secret=?', true]
        expect { @ability.can? :read, Article.new }.to raise_error(CanCan::Error)
      end

      it 'has false conditions if no abilities match' do
        expect(@ability.model_adapter(Article, :read).conditions).to eq(false_condition)
      end

      it 'returns false conditions for cannot clause' do
        @ability.cannot :read, Article
        expect(@ability.model_adapter(Article, :read).conditions).to eq(false_condition)
      end

      it 'returns SQL for single `can` definition in front of default `cannot` condition' do
        @ability.cannot :read, Article
        @ability.can :read, Article, published: false, secret: true
        expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
    SELECT "articles".*
    FROM "articles"
    WHERE "articles"."published" = #{false_v} AND "articles"."secret" = #{true_v}))
      end

      it 'returns true condition for single `can` definition in front of default `can` condition' do
        @ability.can :read, Article
        @ability.can :read, Article, published: false, secret: true
        expect(@ability.model_adapter(Article, :read).conditions).to eq({})
        expect(@ability.model_adapter(Article, :read)).to generate_sql(%(SELECT "articles".* FROM "articles"))
      end

      it 'returns `false condition` for single `cannot` definition in front of default `cannot` condition' do
        @ability.cannot :read, Article
        @ability.cannot :read, Article, published: false, secret: true
        expect(@ability.model_adapter(Article, :read).conditions).to eq(false_condition)
      end

      it 'returns `not (sql)` for single `cannot` definition in front of default `can` condition' do
        @ability.can :read, Article
        @ability.cannot :read, Article, published: false, secret: true
        expect(@ability.model_adapter(Article, :read).conditions)
          .to orderlessly_match(
            %[("#{@article_table}"."published" = #{false_v} AND "#{@article_table}"."secret" = #{true_v}) IS NOT TRUE]
          )
      end

      it 'returns appropriate sql conditions in complex case' do
        @ability.can :read, Article
        @ability.can :manage, Article, id: 1
        @ability.can :update, Article, published: true
        @ability.cannot :update, Article, secret: true
        expect(@ability.model_adapter(Article, :update).conditions)
          .to eq(%[("#{@article_table}"."secret" = #{true_v}) IS NOT TRUE ] +
                   %[AND (("#{@article_table}"."published" = #{true_v}) ] +
                   %[OR ("#{@article_table}"."id" = 1))])
        expect(@ability.model_adapter(Article, :manage).conditions).to eq(id: 1)
        expect(@ability.model_adapter(Article, :read).conditions).to eq({})
        expect(@ability.model_adapter(Article, :read)).to generate_sql(%(SELECT "articles".* FROM "articles"))
      end

      it 'joins consecutive can rules in a flat chain of ORs' do
        @ability.can :read, Article, id: 1
        @ability.can :read, Article, id: 2
        @ability.can :read, Article, id: 3
        expect(@ability.model_adapter(Article, :read).conditions)
          .to eq(%[("#{@article_table}"."id" = 3) OR ("#{@article_table}"."id" = 2) OR ("#{@article_table}"."id" = 1)])
      end

      it 'keeps the precedence of a can rule following a cannot rule' do
        @ability.can :read, Article, id: 1
        @ability.can :read, Article, id: 2
        @ability.cannot :read, Article, secret: true
        @ability.can :read, Article, published: true
        expect(@ability.model_adapter(Article, :read).conditions)
          .to eq(%[("#{@article_table}"."published" = #{true_v}) OR ] +
                   %[(("#{@article_table}"."secret" = #{true_v}) IS NOT TRUE AND ] +
                   %[(("#{@article_table}"."id" = 2) OR ("#{@article_table}"."id" = 1)))])

        secret = Article.create!(id: 1, secret: true, published: false)
        article2 = Article.create!(id: 2, secret: false, published: false)
        published_secret = Article.create!(id: 3, secret: true, published: true)
        Article.create!(id: 4, secret: false, published: false)
        expect(Article.accessible_by(@ability)).to match_array([article2, published_secret])
        expect(Article.accessible_by(@ability)).not_to include(secret)
      end

      it 'fetches records with hundreds of can rules' do
        300.times { |i| @ability.can :read, Article, priority: i + 1 }
        first = Article.create!(priority: 1)
        last = Article.create!(priority: 300)
        Article.create!(priority: 301)
        expect(Article.accessible_by(@ability)).to match_array([first, last])
      end

      it 'does not exclude records with NULL in the column of a cannot rule, like can? does' do
        @ability.can :read, Article
        @ability.cannot :read, Article, secret: true
        secret = Article.create!(secret: true)
        public = Article.create!(secret: false)
        unknown = Article.create!(secret: nil)

        expect(Article.accessible_by(@ability)).to match_array([public, unknown])
        expect(@ability.can?(:read, secret)).to be(false)
        expect(@ability.can?(:read, public)).to be(true)
        expect(@ability.can?(:read, unknown)).to be(true)
      end

      it 'returns appropriate sql conditions in complex case with nested joins' do
        @ability.can :read, Comment, article: { category: { visible: true } }
        expect(@ability.model_adapter(Comment, :read).conditions).to eq(Category.table_name.to_sym => { visible: true })
      end

      it 'returns appropriate sql conditions in complex case with nested joins of different depth' do
        @ability.can :read, Comment, article: { published: true, category: { visible: true } }
        expect(@ability.model_adapter(Comment, :read).conditions)
          .to eq(Article.table_name.to_sym => { published: true }, Category.table_name.to_sym => { visible: true })
      end

      it 'does not forget conditions when calling with SQL string' do
        @ability.can :read, Article, published: true
        @ability.can :read, Article, ['secret = ?', false]
        adapter = @ability.model_adapter(Article, :read)
        2.times do
          expect(adapter.conditions).to eq(%[(secret = #{false_v}) OR ("#{@article_table}"."published" = #{true_v})])
        end
      end

      it 'has nil joins if no rules' do
        expect(@ability.model_adapter(Article, :read).joins).to be_nil
      end

      context 'if rules got compressed' do
        it 'has nil joins' do
          @ability.can :read, Comment, article: { category: { visible: true } }
          @ability.can :read, Comment
          expect(@ability.model_adapter(Comment, :read))
            .to generate_sql("SELECT \"#{@comment_table}\".* FROM \"#{@comment_table}\"")
          expect(@ability.model_adapter(Comment, :read).joins).to be_nil
        end
      end

      context 'if rules did not get compressed' do
        before :each do
          CanCan.rules_compressor_enabled = false
        end

        it 'has joins' do
          @ability.can :read, Comment, article: { category: { visible: true } }
          @ability.can :read, Comment
          expect(@ability.model_adapter(Comment, :read).joins).to be_present
        end
      end

      it 'has nil joins if no nested hashes specified in conditions' do
        @ability.can :read, Article, published: false
        @ability.can :read, Article, secret: true
        expect(@ability.model_adapter(Article, :read).joins).to be_nil
      end

      it 'merges separate joins into a single array' do
        @ability.can :read, Article, project: { blocked: false }
        @ability.can :read, Article, company: { admin: true }
        expect(@ability.model_adapter(Article, :read).joins.inspect).to orderlessly_match(%i[company project].inspect)
      end

      it 'merges same joins into a single array' do
        @ability.can :read, Article, project: { blocked: false }
        @ability.can :read, Article, project: { admin: true }
        expect(@ability.model_adapter(Article, :read).joins).to eq([:project])
      end

      it 'merges nested and non-nested joins' do
        @ability.can :read, Article, project: { blocked: false }
        @ability.can :read, Article, project: { comments: { spam: true } }
        expect(@ability.model_adapter(Article, :read).joins).to eq([{ project: [:comments] }])
      end

      it 'merges :all conditions with other conditions' do
        user = User.create!
        article = Article.create!(user: user)
        ability = Ability.new(user)
        ability.can :manage, :all
        ability.can :manage, Article, user_id: user.id
        expect(Article.accessible_by(ability)).to eq([article])
      end

      it 'should not execute a scope when checking ability on the class' do
        relation = Article.where(secret: true)
        @ability.can :read, Article, relation do |article|
          article.secret == true
        end

        allow(relation).to receive(:count).and_raise('Unexpected scope execution.')

        expect { @ability.can? :read, Article }.not_to raise_error
      end

      it 'should ignore cannot rules with attributes when querying' do
        user = User.create!
        article = Article.create!(user: user)
        ability = Ability.new(user)
        ability.can :read, Article
        ability.cannot :read, Article, :secret
        expect(Article.accessible_by(ability)).to eq([article])
      end

      describe 'when can? is used with a Hash (nested resources)' do
        it 'verifies parent equality correctly' do
          user1 = User.create!(name: 'user1')
          user2 = User.create!(name: 'user2')
          category = Category.create!(name: 'cat')
          article1 = Article.create!(name: 'article1', category: category, user: user1)
          article2 = Article.create!(name: 'article2', category: category, user: user2)
          comment1 = Comment.create!(article: article1)
          comment2 = Comment.create!(article: article2)

          ability1 = Ability.new(user1)
          ability1.can :read, Article
          ability1.can :manage, Article, user: user1
          ability1.can :manage, Comment, article: user1.articles

          expect(ability1.can?(:manage, { article1 => Comment })).to eq(true)
          expect(ability1.can?(:manage, { article2 => Comment })).to eq(false)
          expect(ability1.can?(:manage, { article1 => comment1 })).to eq(true)
          expect(ability1.can?(:manage, { article2 => comment2 })).to eq(false)

          ability2 = Ability.new(user2)

          expect(ability2.can?(:manage, { article1 => Comment })).to eq(false)
          expect(ability2.can?(:manage, { article2 => Comment })).to eq(false)
          expect(ability2.can?(:manage, { article1 => comment1 })).to eq(false)
          expect(ability2.can?(:manage, { article2 => comment2 })).to eq(false)
        end
      end
    end
  end

  describe 'when can? is used with a Hash (nested resources)' do
    let(:user1) { User.create!(name: 'user1') }
    let(:user2) { User.create!(name: 'user2') }

    before do
      category = Category.create!(name: 'category')
      @article1 = Article.create!(name: 'article1', category: category, user: user1)
      @article2 = Article.create!(name: 'article2', category: category, user: user2)
      @comment1 = Comment.create!(article: @article1)
      @comment2 = Comment.create!(article: @article2)
      @legacy_comment1 = LegacyComment.create!(article: @article1)
      @legacy_comment2 = LegacyComment.create!(article: @article2)
      @attachment1 = Attachment.create!(attachable: @article1)
      @comment_attachment1 = Attachment.create!(attachable: @comment1)
      @attachment2 = Attachment.create!(attachable: @article2)
      @comment_attachment2 = Attachment.create!(attachable: @comment2)
    end

    context 'when conditions are defined using the parent model' do
      let(:ability) do
        Ability.new(user1).tap do |ability|
          ability.can :read, Article
          ability.can :manage, Article, user: user1
          ability.can :manage, Comment, article: user1.articles
          ability.can :manage, LegacyComment, article: user1.articles
          ability.can :manage, Attachment, attachable: user1.articles
          ability.can :manage, Attachment, attachable: user1.comments
        end
      end

      it 'verifies parent equality correctly' do
        expect(ability.can?(:manage, { @article1 => Comment })).to eq(true)
        expect(ability.can?(:manage, { @article1 => LegacyComment })).to eq(true)
        expect(ability.can?(:manage, { @article1 => @comment1 })).to eq(true)
        expect(ability.can?(:manage, { @article1 => @legacy_comment1 })).to eq(true)

        expect(ability.can?(:manage, { @article2 => Comment })).to eq(false)
        expect(ability.can?(:manage, { @article2 => LegacyComment })).to eq(false)
        expect(ability.can?(:manage, { @article2 => @legacy_comment2 })).to eq(false)
      end

      context 'when the association is polymorphic' do
        it 'verifies parent equality correctly' do
          expect(ability.can?(:manage, { @article1 => Attachment })).to eq(true)
          expect(ability.can?(:manage, { @article1 => @attachment1 })).to eq(true)
          expect(ability.can?(:manage, { @comment1 => Attachment })).to eq(true)
          expect(ability.can?(:manage, { @comment1 => @comment_attachment1 })).to eq(true)

          expect(ability.can?(:manage, { @article2 => Attachment })).to eq(false)
          expect(ability.can?(:manage, { @article2 => @attachment2 })).to eq(false)
          expect(ability.can?(:manage, { @comment2 => Attachment })).to eq(false)
          expect(ability.can?(:manage, { @comment2 => @comment_attachment2 })).to eq(false)
        end
      end
    end

    context 'when conditions are defined using the parent id' do
      let(:ability) do
        Ability.new(user1).tap do |ability|
          ability.can :read, Article
          ability.can :manage, Article, user_id: user1.id
          ability.can :manage, Comment, article_id: user1.article_ids
          ability.can :manage, LegacyComment, post_id: user1.article_ids
          ability.can :manage, Attachment, attachable_id: user1.article_ids
        end
      end

      it 'verifies parent equality correctly' do
        expect(ability.can?(:manage, { @article1 => Comment })).to eq(true)
        expect(ability.can?(:manage, { @article1 => LegacyComment })).to eq(true)
        expect(ability.can?(:manage, { @article1 => @comment1 })).to eq(true)
        expect(ability.can?(:manage, { @article1 => @legacy_comment1 })).to eq(true)

        expect(ability.can?(:manage, { @article2 => Comment })).to eq(false)
        expect(ability.can?(:manage, { @article2 => LegacyComment })).to eq(false)
        expect(ability.can?(:manage, { @article2 => @legacy_comment2 })).to eq(false)
      end

      context 'when the association is polymorphic' do
        it 'verifies parent equality correctly' do
          expect(ability.can?(:manage, { @article1 => Attachment })).to eq(true)
          expect(ability.can?(:manage, { @article1 => @attachment1 })).to eq(true)
          expect(ability.can?(:manage, { @comment1 => Attachment })).to eq(true)
          expect(ability.can?(:manage, { @comment1 => @comment_attachment1 })).to eq(true)

          expect(ability.can?(:manage, { @article2 => Attachment })).to eq(false)
          expect(ability.can?(:manage, { @article2 => @attachment2 })).to eq(false)
          expect(ability.can?(:manage, { @comment2 => Attachment })).to eq(false)
          expect(ability.can?(:manage, { @comment2 => @comment_attachment2 })).to eq(false)
        end
      end
    end

    context 'when a cannot rule has conditions' do
      let(:ability) { Ability.new(user1).tap { |ability| ability.can :index, Comment } }

      it 'does not deny the class when the conditions are on the child' do
        ability.cannot :index, Comment, spam: true

        expect(ability.can?(:index, Comment)).to eq(true)
        expect(ability.can?(:index, { @article1 => Comment })).to eq(true)
      end

      it 'does not deny the class when the conditions are on the parent and the child' do
        ability.cannot :index, Comment, spam: true, article: { user_id: user1.id }

        expect(ability.can?(:index, { @article1 => Comment })).to eq(true)
      end

      it 'denies the class when the conditions are on the parent only' do
        ability.cannot :index, Comment, article: { user_id: user1.id }

        expect(ability.can?(:index, { @article1 => Comment })).to eq(false)
        expect(ability.can?(:index, { @article2 => Comment })).to eq(true)
      end

      it 'denies the class when the conditions are on the parent id only' do
        ability.cannot :index, Comment, article_id: @article1.id

        expect(ability.can?(:index, { @article1 => Comment })).to eq(false)
        expect(ability.can?(:index, { @article2 => Comment })).to eq(true)
      end
    end
  end

  context 'base behaviour subquery specific' do
    before :each do
      CanCan.accessible_by_strategy = :subquery
    end

    it 'allows ordering via relations' do
      @ability.can :read, Comment, article: { category: { visible: true } }
      comment1 = Comment.create!(article: Article.create!(name: 'B', category: Category.create!(visible: true)))
      comment2 = Comment.create!(article: Article.create!(name: 'A', category: Category.create!(visible: true)))
      Comment.create!(article: Article.create!(category: Category.create!(visible: false)))

      # doesn't work without explicitly calling a join
      expect { Comment.accessible_by(@ability).order('articles.name').to_a }
        .to raise_error(ActiveRecord::StatementInvalid)

      # works with the explicit join
      expect(Comment.accessible_by(@ability).joins(:article).order('articles.name'))
        .to match_array([comment2, comment1])
    end
  end

  context 'base behaviour left_join specific' do
    before :each do
      CanCan.accessible_by_strategy = :left_join
    end

    it 'allows ordering via relations in sqlite' do
      skip unless sqlite?

      @ability.can :read, Comment, article: { category: { visible: true } }
      comment1 = Comment.create!(article: Article.create!(name: 'B', category: Category.create!(visible: true)))
      comment2 = Comment.create!(article: Article.create!(name: 'A', category: Category.create!(visible: true)))
      Comment.create!(article: Article.create!(category: Category.create!(visible: false)))

      # works without explicitly calling a join
      expect(Comment.accessible_by(@ability).order('articles.name')).to match_array([comment2, comment1])

      # works with the explicit join
      expect(Comment.accessible_by(@ability).joins(:article).order('articles.name'))
        .to match_array([comment2, comment1])
    end

    # this fails on Postgres. see https://github.com/CanCanCommunity/cancancan/pull/608
    it 'fails to order via relations in postgres' do
      skip unless postgres?

      @ability.can :read, Comment, article: { category: { visible: true } }
      Comment.create!(article: Article.create!(name: 'B', category: Category.create!(visible: true)))
      Comment.create!(article: Article.create!(name: 'A', category: Category.create!(visible: true)))
      Comment.create!(article: Article.create!(category: Category.create!(visible: false)))

      # doesn't work with or without the join
      expect { Comment.accessible_by(@ability).order('articles.name').to_a }
        .to raise_error(ActiveRecord::StatementInvalid)
      expect { Comment.accessible_by(@ability).joins(:article).order('articles.name').to_a }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  it 'allows an empty array to be used as a condition for a has_many, but this is never a passing condition' do
    a1 = Article.create!
    a2 = Article.create!
    a2.comments = [Comment.create!]

    @ability.can :read, Article, comment_ids: []

    expect(@ability.can?(:read, a1)).to eq(false)
    expect(@ability.can?(:read, a2)).to eq(false)

    expect(Article.accessible_by(@ability)).to eq([])

    expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT "articles".*
  FROM "articles"
  WHERE 1=0))
  end

  it 'allows a nil to be used as a condition for a has_many - with join' do
    a1 = Article.create!
    a2 = Article.create!
    a2.comments = [Comment.create!]

    @ability.can :read, Article, comments: { id: nil }

    expect(@ability.can?(:read, a1)).to eq(true)
    expect(@ability.can?(:read, a2)).to eq(false)

    expect(Article.accessible_by(@ability)).to eq([a1])

    expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN (SELECT "articles"."id" FROM "articles"
    LEFT OUTER JOIN "comments" ON "comments"."article_id" = "articles"."id"
    WHERE "comments"."id" IS NULL)))
  end

  it 'allows several nils to be used as a condition for a has_many - with join' do
    a1 = Article.create!
    a2 = Article.create!
    a2.comments = [Comment.create!]

    @ability.can :read, Article, comments: { id: nil, spam: nil }

    expect(@ability.can?(:read, a1)).to eq(true)
    expect(@ability.can?(:read, a2)).to eq(false)

    expect(Article.accessible_by(@ability)).to eq([a1])

    expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN (SELECT "articles"."id" FROM "articles"
    LEFT OUTER JOIN "comments" ON "comments"."article_id" = "articles"."id"
    WHERE "comments"."id" IS NULL AND "comments"."spam" IS NULL)))
  end

  it 'doesn\'t permit anything if a nil is used as a condition for a has_many alongside other attributes' do
    a1 = Article.create!
    a2 = Article.create!
    a2.comments = [Comment.create!(spam: true)]
    a3 = Article.create!
    a3.comments = [Comment.create!(spam: false)]

    # if we are checking for `id: nil` and any other criteria, we should never return any Article.
    # either the Article has Comments, which means `id: nil` fails.
    # or the Article has no Comments, which means `spam: true` fails.
    @ability.can :read, Article, comments: { id: nil, spam: true }

    expect(@ability.can?(:read, a1)).to eq(false)
    expect(@ability.can?(:read, a2)).to eq(false)
    expect(@ability.can?(:read, a3)).to eq(false)

    expect(Article.accessible_by(@ability)).to eq([])

    expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN (SELECT "articles"."id" FROM "articles"
    LEFT OUTER JOIN "comments" ON "comments"."article_id" = "articles"."id"
    WHERE "comments"."id" IS NULL AND "comments"."spam" = #{true_v})))
  end

  it 'doesn\'t permit if a nil is used as a condition for a has_many alongside other attributes - false case' do
    a1 = Article.create!
    a2 = Article.create!
    a2.comments = [Comment.create!(spam: true)]
    a3 = Article.create!
    a3.comments = [Comment.create!(spam: false)]

    # if we are checking for `id: nil` and any other criteria, we should never return any Article.
    # either the Article has Comments, which means `id: nil` fails.
    # or the Article has no Comments, which means `spam: false` fails.
    @ability.can :read, Article, comments: { id: nil, spam: false }

    expect(@ability.can?(:read, a1)).to eq(false)
    expect(@ability.can?(:read, a2)).to eq(false)
    expect(@ability.can?(:read, a3)).to eq(false)

    expect(Article.accessible_by(@ability)).to eq([])

    expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN (SELECT "articles"."id" FROM "articles"
    LEFT OUTER JOIN "comments" ON "comments"."article_id" = "articles"."id"
    WHERE "comments"."id" IS NULL AND "comments"."spam" = #{false_v})))
  end

  it 'allows a nil to be used as a condition for a has_many when combined with other conditions' do
    a1 = Article.create!
    a2 = Article.create!
    a2.comments = [Comment.create!(spam: true)]
    a3 = Article.create!
    a3.comments = [Comment.create!(spam: false)]

    @ability.can :read, Article, comments: { spam: true }
    @ability.can :read, Article, comments: { id: nil }

    expect(@ability.can?(:read, a1)).to eq(true) # true because no comments
    expect(@ability.can?(:read, a2)).to eq(true) # true because has comments but they have spam=true
    expect(@ability.can?(:read, a3)).to eq(false) # false because has comments but none with spam=true

    expect(Article.accessible_by(@ability).sort_by(&:id)).to eq([a1, a2].sort_by(&:id))

    expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN (SELECT "articles"."id" FROM "articles"
    LEFT OUTER JOIN "comments" ON "comments"."article_id" = "articles"."id"
    WHERE (("comments"."id" IS NULL) OR ("comments"."spam" = #{true_v})))))
  end

  it 'allows a nil to be used as a condition for a has_many alongside other attributes on the parent' do
    a1 = Article.create!(secret: true)
    a2 = Article.create!(secret: true)
    a2.comments = [Comment.create!]
    a3 = Article.create!(secret: false)
    a3.comments = [Comment.create!]
    a4 = Article.create!(secret: false)

    @ability.can :read, Article, secret: true, comments: { id: nil }

    expect(@ability.can?(:read, a1)).to eq(true)
    expect(@ability.can?(:read, a2)).to eq(false)
    expect(@ability.can?(:read, a3)).to eq(false)
    expect(@ability.can?(:read, a4)).to eq(false)

    expect(Article.accessible_by(@ability)).to eq([a1])

    expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN (SELECT "articles"."id" FROM "articles"
    LEFT OUTER JOIN "comments" ON "comments"."article_id" = "articles"."id"
    WHERE "articles"."secret" = #{true_v} AND "comments"."id" IS NULL)))
  end

  CanCan.valid_accessible_by_strategies.each do |strategy|
    context "when a condition is on an association that is not loaded, with #{strategy} strategy" do
      def count_queries(&block)
        count = 0
        counter = lambda { |_name, _started, _finished, _unique_id, payload|
          count += 1 unless payload[:name].in?(%w[CACHE SCHEMA])
        }
        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
        count
      end

      before do
        CanCan.accessible_by_strategy = strategy
      end

      it 'checks the conditions with one query instead of loading the records' do
        @ability.can :read, Article, comments: { spam: true }
        article = Article.create!
        Comment.create!(article: article, spam: false)
        Comment.create!(article: article, spam: true)

        expect(count_queries { expect(@ability.can?(:read, article)).to be(true) }).to eq(1)
        expect(article.comments).not_to be_loaded
      end

      it 'does not match when no record of the association matches' do
        @ability.can :read, Article, comments: { spam: true }
        article = Article.create!
        Comment.create!(article: article, spam: false)

        expect(@ability.can?(:read, article)).to be(false)
        expect(article.comments).not_to be_loaded
      end

      it 'checks the records in memory when the association is loaded' do
        @ability.can :read, Article, comments: { spam: true }
        article = Article.create!
        Comment.create!(article: article, spam: true)
        article = Article.includes(:comments).find(article.id)

        expect(count_queries { expect(@ability.can?(:read, article)).to be(true) }).to eq(0)
      end

      it 'joins the associations nested below the association' do
        @ability.can :read, Project, comments: { article: { published: true } }
        project = Project.create!
        Comment.create!(project: project, article: Article.create!(published: false))
        expect(@ability.can?(:read, project)).to be(false)

        Comment.create!(project: project, article: Article.create!(published: true))
        expect(@ability.can?(:read, project)).to be(true)
        expect(project.comments).not_to be_loaded
      end

      it 'keeps the scope of the association' do
        @ability.can :read, User, published_articles: { name: 'cancan' }
        user = User.create!
        Article.create!(user: user, name: 'cancan', published: false)
        expect(@ability.can?(:read, user)).to be(false)

        Article.create!(user: user, name: 'cancan', published: true)
        expect(@ability.can?(:read, user)).to be(true)
      end

      it 'supports a has_many through association' do
        @ability.can :read, User, comments: { spam: true }
        user = User.create!
        article = Article.create!(user: user)
        Comment.create!(article: article, spam: false)
        expect(@ability.can?(:read, user)).to be(false)

        Comment.create!(article: article, spam: true)
        expect(@ability.can?(:read, user)).to be(true)
        expect(user.comments).not_to be_loaded
      end

      it 'matches an association without records when the values are nil' do
        @ability.can :read, Article, comments: { id: nil }
        article = Article.create!
        expect(@ability.can?(:read, article)).to be(true)

        Comment.create!(article: article)
        expect(@ability.can?(:read, Article.find(article.id))).to be(false)
      end

      it 'matches a record with a NULL column when the value is nil' do
        @ability.can :read, Article, comments: { spam: nil }
        article = Article.create!
        Comment.create!(article: article, spam: nil)
        expect(@ability.can?(:read, article)).to be(true)

        Comment.find_by(article: article).update!(spam: false)
        expect(@ability.can?(:read, Article.find(article.id))).to be(false)
      end

      it 'applies to the conditions of a cannot rule' do
        @ability.can :read, Article
        @ability.cannot :read, Article, comments: { spam: true }
        article = Article.create!
        Comment.create!(article: article, spam: false)
        expect(@ability.can?(:read, article)).to be(true)

        Comment.create!(article: article, spam: true)
        expect(@ability.can?(:read, Article.find(article.id))).to be(false)
        expect(article.comments).not_to be_loaded
      end
    end
  end

  it 'allows an empty array to be used as a condition for a belongs_to; this never returns true' do
    a1 = Article.create!
    a2 = Article.create!
    a2.project = Project.create!

    @ability.can :read, Article, project_id: []

    expect(@ability.can?(:read, a1)).to eq(false)
    expect(@ability.can?(:read, a2)).to eq(false)

    expect(Article.accessible_by(@ability)).to eq([])

    expect(@ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT "articles".*
  FROM "articles"
  WHERE 1=0))
  end

  it 'does not change the rules of the ability when it builds a query' do
    @ability.can :read, [Article, User], comments: { spam: false }
    article = Article.create!
    Comment.create!(article: article, spam: false)

    User.accessible_by(@ability)

    expect(@ability.can?(:read, article)).to be(true)
  end

  describe '#permitted_attributes' do
    let(:all_attributes) { Article.attribute_names.map(&:to_sym) - [:id] }

    it 'returns all attributes except the primary key for a can rule without attributes' do
      @ability.can :update, Article

      expect(@ability.permitted_attributes(:update, Article)).to match_array(all_attributes)
    end

    it 'returns no attributes when no rule is defined' do
      expect(@ability.permitted_attributes(:update, Article)).to eq([])
    end

    it 'returns no attributes when the action is forbidden' do
      @ability.cannot :update, Article

      expect(@ability.permitted_attributes(:update, Article)).to eq([])
    end

    it 'returns no attributes when a cannot rule follows a can rule' do
      @ability.can :update, Article
      @ability.cannot :update, Article

      expect(@ability.permitted_attributes(:update, Article)).to eq([])
    end

    it 'returns no attributes when a cannot rule with conditions matches the record' do
      @ability.can :update, Article
      @ability.cannot :update, Article, secret: true

      expect(@ability.permitted_attributes(:update, Article.new(secret: true))).to eq([])
      expect(@ability.permitted_attributes(:update, Article.new(secret: false))).to match_array(all_attributes)
    end

    it 'returns no attributes when a can rule with attributes is followed by a cannot rule' do
      @ability.can :update, Article, [:name]
      @ability.cannot :update, Article

      expect(@ability.permitted_attributes(:update, Article)).to eq([])
    end

    it 'returns no attributes when a cannot rule follows a can rule with attributes that are not columns' do
      @ability.can :update, Article, %i[name password]
      @ability.cannot :update, Article

      expect(@ability.permitted_attributes(:update, Article)).to eq([])
    end
  end

  describe '#disallowed_attributes' do
    it 'returns the attributes forbidden by a cannot rule' do
      @ability.can :update, Article
      @ability.cannot :update, Article, %i[secret priority]

      expect(@ability.disallowed_attributes(:update, Article)).to match_array(%i[secret priority])
    end

    it 'returns all attributes when a cannot rule has no attributes' do
      @ability.cannot :update, Article

      expect(@ability.disallowed_attributes(:update, Article))
        .to include(*(Article.attribute_names.map(&:to_sym) - [:id]))
    end

    it 'returns no attributes when no rule is defined' do
      expect(@ability.disallowed_attributes(:update, Article)).to eq([])
    end

    it 'returns no attributes when a can rule only allows some attributes' do
      @ability.can :update, Article, [:name]

      expect(@ability.disallowed_attributes(:update, Article)).to eq([])
    end

    it 'does not return attributes allowed again by a later can rule' do
      @ability.cannot :update, Article, [:secret]
      @ability.can :update, Article, [:secret]

      expect(@ability.disallowed_attributes(:update, Article)).to eq([])
    end

    it 'applies the conditions of the cannot rule to the record' do
      @ability.can :update, Article
      @ability.cannot :update, Article, [:secret], published: true

      expect(@ability.disallowed_attributes(:update, Article.new(published: true))).to eq([:secret])
      expect(@ability.disallowed_attributes(:update, Article.new(published: false))).to eq([])
    end
  end

  context 'with namespaced models' do
    before :each do
      ActiveRecord::Schema.define do
        create_table(:table_xes) do |t|
          t.timestamps null: false
        end

        create_table(:table_zs) do |t|
          t.integer :table_x_id
          t.integer :user_id
          t.timestamps null: false
        end
      end

      module Namespace
      end

      class Namespace::TableX < ActiveRecord::Base
        has_many :table_zs
      end

      class Namespace::TableZ < ActiveRecord::Base
        belongs_to :table_x
        belongs_to :user
      end
    end

    it 'fetches all namespace::table_x when one is related by table_y' do
      user = User.create!

      ability = Ability.new(user)
      ability.can :read, Namespace::TableX, table_zs: { user_id: user.id }

      table_x = Namespace::TableX.create!
      table_x.table_zs.create(user: user)
      expect(Namespace::TableX.accessible_by(ability)).to match_array([table_x])
    end
  end

  context 'when conditions are non iterable ranges' do
    before :each do
      ActiveRecord::Schema.define do
        create_table(:courses) do |t|
          t.datetime :start_at
        end
      end

      class Course < ActiveRecord::Base
      end
    end

    it 'fetches only the valid records' do
      @ability.can :read, Course, start_at: 1.day.ago..1.day.from_now
      Course.create!(start_at: 10.days.ago)
      valid_course = Course.create!(start_at: Time.now)

      expect(Course.accessible_by(@ability)).to match_array([valid_course])
    end
  end

  context 'when conditions use symbols for string columns' do
    let(:draft) { Article.create!(name: 'draft') }
    let(:published) { Article.create!(name: 'published') }

    it 'applies a cannot rule in can? as in accessible_by' do
      @ability.can :read, Article
      @ability.cannot :read, Article, name: :draft

      expect(Article.accessible_by(@ability)).to match_array([published])
      expect(@ability).not_to be_able_to(:read, draft)
      expect(@ability).to be_able_to(:read, published)
    end

    it 'applies a can rule in can? as in accessible_by' do
      @ability.can :read, Article, name: :published

      expect(Article.accessible_by(@ability)).to match_array([published])
      expect(@ability).to be_able_to(:read, published)
      expect(@ability).not_to be_able_to(:read, draft)
    end

    it 'applies the rules when accessible_by gets the action as a string' do
      @ability.can :read, Article
      @ability.cannot :read, Article, name: :draft

      expect(Article.accessible_by(@ability, 'read')).to match_array([published])
      expect(@ability).not_to be_able_to('read', draft)
      expect(@ability).to be_able_to('read', published)
    end

    it 'matches an array of symbols' do
      @ability.can :read, Article
      @ability.cannot :read, Article, name: %i[draft archived]

      expect(Article.accessible_by(@ability)).to match_array([published])
      expect(@ability).not_to be_able_to(:read, draft)
      expect(@ability).to be_able_to(:read, published)
    end

    it 'matches symbols in the conditions of an association' do
      category = Category.create!(name: 'drafts')
      article = Article.create!(category: category)
      @ability.can :read, Article
      @ability.cannot :read, Article, category: { name: :drafts }

      expect(Article.accessible_by(@ability)).to be_empty
      expect(@ability).not_to be_able_to(:read, article)
    end
  end

  context 'when conditions are an array of ranges and nil' do
    it 'matches the same records with can? and accessible_by' do
      @ability.can :read, Article, priority: [1..2, 10.., nil]
      matching = [Article.create!(priority: 2), Article.create!(priority: 15), Article.create!(priority: nil)]
      not_matching = [Article.create!(priority: 0), Article.create!(priority: 5)]

      expect(Article.accessible_by(@ability)).to match_array(matching)
      matching.each { |article| expect(@ability).to be_able_to(:read, article) }
      not_matching.each { |article| expect(@ability).not_to be_able_to(:read, article) }
    end
  end

  context 'when an association is used to create a rule' do
    before do
      ActiveRecord::Schema.define do
        create_table(:foos) do |t|
          t.string :name
        end
        create_table(:bars) do |t|
          t.string :name
        end
        create_table :roles do |t|
          t.string :name

          t.timestamps
        end
        create_table :user_roles do |t|
          t.references :user, foreign_key: true
          t.references :role, foreign_key: true
          t.references :subject, polymorphic: true

          t.timestamps
        end
      end

      class Foo < ActiveRecord::Base
        has_many :user_roles, as: :subject
      end

      class Bar < ActiveRecord::Base
        has_many :user_roles, as: :subject
      end

      class Role < ActiveRecord::Base
        has_many :user_roles
        has_many :users, through: :user_roles
        has_many :foos, through: :user_roles
        has_many :bars, through: :user_roles
      end

      class UserRole < ActiveRecord::Base
        belongs_to :user
        belongs_to :role
        belongs_to :subject, polymorphic: true, required: false
      end
    end

    it 'allows for access with association' do
      user = User.create!
      foo = Foo.create(name: 'foo')
      role = Role.create(name: 'adviser')
      UserRole.create(user: user, role: role, subject: foo)
      ability = Ability.new(user)
      ability.can :read, Foo, user_roles: { user: user }
      expect(ability.can?(:read, Foo)).to eq(true)
    end

    it 'allows for access with association with accessible_by' do
      user = User.new
      foo = Foo.create(name: 'foo')
      bar = Bar.create(name: 'bar')
      role = Role.create(name: 'adviser')
      UserRole.create(user: user, role: role, subject: foo)
      UserRole.create(user: user, role: role, subject: bar)
      ability = Ability.new(user)
      ability.can :read, Foo, user_roles: { user: user }
      expect(Foo.accessible_by(ability)).to match_array([foo])
      expect(Bar.accessible_by(ability)).to match_array([])
    end

    it 'blocks access with association' do
      user = User.create!
      foo = Foo.create(name: 'foo')
      role = Role.create(name: 'adviser')
      UserRole.create(user: user, role: role, subject: foo)
      ability = Ability.new(user)
      ability.cannot :read, Foo, user_roles: { user: user }
      expect(ability.can?(:read, Foo)).to eq(false)
    end

    it 'blocks access with association for accessible_by' do
      user = User.create!
      foo = Foo.create(name: 'foo')
      role = Role.create(name: 'adviser')
      UserRole.create(user: user, role: role, subject: foo)
      ability = Ability.new(user)
      ability.cannot :read, Foo, user_roles: { user: user }
      expect(Foo.accessible_by(ability)).to match_array([])
      expect(ability.can?(:read, Foo)).to eq(false)
    end

    it 'manages access with multiple models and users' do
      (0..5).each do |index|
        user = User.create!
        foo = Foo.create(name: 'foo')
        role = Role.create(name: "adviser_#{index}")
        UserRole.create(user: user, role: role, subject: foo)
      end

      user = User.first

      Foo.all.each do |foo|
        role = Role.create(name: 'new_user')
        UserRole.create(user: user, role: role, subject: foo)
      end

      ability = Ability.new(user)
      ability.can :read, Foo, user_roles: { user: user }
      expect(Foo.accessible_by(ability).count).to eq(Foo.count)

      User.where.not(id: user.id).each do |limited_permission_user|
        ability = Ability.new(limited_permission_user)
        expect(ability.can?(:read, Foo)).to eq(false)
        expect(Foo.accessible_by(ability).count).to eq(0)
        ability.can :read, Foo, user_roles: { user: limited_permission_user }
        expect(ability.can?(:read, Foo)).to eq(true)
        expect(Foo.accessible_by(ability).count).to eq(1)
      end
    end
  end

  context 'when a table references another one twice' do
    before do
      ActiveRecord::Schema.define do
        create_table(:transactions) do |t|
          t.integer :sender_id
          t.integer :receiver_id
        end
      end

      class Transaction < ActiveRecord::Base
        belongs_to :sender, class_name: 'User', foreign_key: :sender_id
        belongs_to :receiver, class_name: 'User', foreign_key: :receiver_id
      end
    end

    it 'can filter correctly on both associations' do
      sender = User.create!
      receiver = User.create!
      t1 = Transaction.create!(sender: sender, receiver: receiver)
      t2 = Transaction.create!(sender: receiver, receiver: sender)

      ability = Ability.new(sender)
      ability.can :read, Transaction, sender: { id: sender.id }
      ability.can :read, Transaction, receiver: { id: sender.id }
      expect(Transaction.accessible_by(ability)).to match_array([t1, t2])
    end
  end

  CanCan.valid_accessible_by_strategies.each do |strategy|
    context "when a table is referenced multiple times with #{strategy} strategy" do
      before :each do
        CanCan.accessible_by_strategy = strategy
      end
      it 'can filter correctly on the different associations' do
        u1 = User.create!(name: 'pippo')
        u2 = User.create!(name: 'paperino')

        a1 = Article.create!(user: u1)
        a2 = Article.create!(user: u2)

        ability = Ability.new(u1)
        ability.can :read, Article, user: { id: u1.id }
        ability.can :read, Article, mentioned_users: { name: u1.name }
        ability.can :read, Article, mentioned_users: { mentioned_articles: { id: a2.id } }
        ability.can :read, Article, mentioned_users: { articles: { user: { name: 'deep' } } }
        ability.can :read, Article, mentioned_users: { articles: { mentioned_users: { name: 'd2' } } }
        expect(Article.accessible_by(ability)).to match_array([a1])
      end
    end
  end

  context 'has_many through is defined and referenced differently - subquery strategy' do
    before do
      CanCan.accessible_by_strategy = :subquery
    end

    it 'recognises it and simplifies the query' do
      u1 = User.create!(name: 'pippo')
      u2 = User.create!(name: 'paperino')

      a1 = Article.create!(mentioned_users: [u1])
      a2 = Article.create!(mentioned_users: [u2])

      ability = Ability.new(u1)
      ability.can :read, Article, mentioned_users: { name: u1.name }
      ability.can :read, Article, mentions: { user: { name: u2.name } }
      expect(Article.accessible_by(ability)).to match_array([a1, a2])
      expect(ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN
  (SELECT "articles"."id"
    FROM "articles"
    LEFT OUTER JOIN "legacy_mentions" ON "legacy_mentions"."article_id" = "articles"."id"
    LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
    WHERE (("users"."name" = 'paperino') OR ("users"."name" = 'pippo')))
  ))
    end
  end

  context 'has_many through is defined and referenced differently - left_join strategy' do
    before do
      CanCan.accessible_by_strategy = :left_join
    end

    it 'recognises it and simplifies the query' do
      u1 = User.create!(name: 'pippo')
      u2 = User.create!(name: 'paperino')

      a1 = Article.create!(mentioned_users: [u1])
      a2 = Article.create!(mentioned_users: [u2])

      ability = Ability.new(u1)
      ability.can :read, Article, mentioned_users: { name: u1.name }
      ability.can :read, Article, mentions: { user: { name: u2.name } }
      expect(Article.accessible_by(ability)).to match_array([a1, a2])

      expect(ability.model_adapter(Article, :read)).to generate_sql(%(
  SELECT DISTINCT "articles".*
  FROM "articles"
  LEFT OUTER JOIN "legacy_mentions" ON "legacy_mentions"."article_id" = "articles"."id"
  LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
  WHERE (("users"."name" = 'paperino') OR ("users"."name" = 'pippo'))))
    end
  end

  context 'switching strategies' do
    before do
      CanCan.accessible_by_strategy = :left_join # default - should be ignored in these tests
    end

    it 'allows you to switch strategies with a keyword argument' do
      u = User.create!(name: 'pippo')
      Article.create!(mentioned_users: [u])

      ability = Ability.new(u)
      ability.can :read, Article, mentions: { user: { name: u.name } }

      subquery_sql = Article.accessible_by(ability, strategy: :subquery).to_sql
      left_join_sql = Article.accessible_by(ability, strategy: :left_join).to_sql

      expect(subquery_sql.strip.squeeze(' ')).to eq(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN
  (SELECT "articles"."id"
    FROM "articles"
    LEFT OUTER JOIN "legacy_mentions" ON "legacy_mentions"."article_id" = "articles"."id"
    LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
    WHERE "users"."name" = 'pippo')
  ).gsub(/\s+/, ' ').strip)

      expect(left_join_sql.strip.squeeze(' ')).to eq(%(
  SELECT DISTINCT "articles".*
  FROM "articles"
  LEFT OUTER JOIN "legacy_mentions" ON "legacy_mentions"."article_id" = "articles"."id"
  LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
  WHERE "users"."name" = 'pippo').gsub(/\s+/, ' ').strip)
    end

    it 'allows you to switch strategies with a block' do
      u = User.create!(name: 'pippo')
      Article.create!(mentioned_users: [u])

      ability = Ability.new(u)
      ability.can :read, Article, mentions: { user: { name: u.name } }

      subquery_sql = CanCan.with_accessible_by_strategy(:subquery) { Article.accessible_by(ability).to_sql }
      left_join_sql = CanCan.with_accessible_by_strategy(:left_join) { Article.accessible_by(ability).to_sql }

      expect(subquery_sql.strip.squeeze(' ')).to eq(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN
  (SELECT "articles"."id"
    FROM "articles"
    LEFT OUTER JOIN "legacy_mentions" ON "legacy_mentions"."article_id" = "articles"."id"
    LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
    WHERE "users"."name" = 'pippo')
  ).gsub(/\s+/, ' ').strip)

      expect(left_join_sql.strip.squeeze(' ')).to eq(%(
  SELECT DISTINCT "articles".*
  FROM "articles"
  LEFT OUTER JOIN "legacy_mentions" ON "legacy_mentions"."article_id" = "articles"."id"
  LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
  WHERE "users"."name" = 'pippo').gsub(/\s+/, ' ').strip)
    end

    it 'allows a subclass of CanCan::ModelAdapters::Strategies::Base as strategy' do
      u = User.create!(name: 'pippo')
      article = Article.create!(mentioned_users: [u])
      Article.create!(mentioned_users: [User.create!(name: 'pluto')])

      ability = Ability.new(u)
      ability.can :read, Article, mentions: { user: { name: u.name } }

      inner_join_strategy = Class.new(CanCan::ModelAdapters::Strategies::Base) do
        def execute!
          relation.joins(joins).distinct
        end
      end

      expected_sql = %(
  SELECT DISTINCT "articles".*
  FROM "articles"
  INNER JOIN "legacy_mentions" ON "legacy_mentions"."article_id" = "articles"."id"
  INNER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
  WHERE "users"."name" = 'pippo').gsub(/\s+/, ' ').strip

      keyword_sql = Article.accessible_by(ability, strategy: inner_join_strategy).to_sql
      block_sql = CanCan.with_accessible_by_strategy(inner_join_strategy) { Article.accessible_by(ability).to_sql }
      CanCan.accessible_by_strategy = inner_join_strategy
      global_sql = Article.accessible_by(ability).to_sql

      expect(keyword_sql.strip.squeeze(' ')).to eq(expected_sql)
      expect(block_sql.strip.squeeze(' ')).to eq(expected_sql)
      expect(global_sql.strip.squeeze(' ')).to eq(expected_sql)
      expect(Article.accessible_by(ability)).to eq([article])
    end

    it 'passes the conditions of the rules to a custom strategy as an Arel node' do
      u = User.create!(name: 'pippo')
      mentioned = Article.create!(mentioned_users: [u])
      published = Article.create!(published: true)
      Article.create!(mentioned_users: [User.create!(name: 'pluto')])

      ability = Ability.new(u)
      ability.can :read, Article, mentions: { user: { name: u.name } }
      ability.can :read, Article, Article.where(published: true)
      ability.cannot :read, Article, secret: true

      strategy = Class.new(CanCan::ModelAdapters::Strategies::Base) do
        def execute!
          model_class.where(where_conditions).left_joins(joins).distinct
        end
      end

      expect(Article.accessible_by(ability, strategy: strategy)).to contain_exactly(mentioned, published)
    end

    it 'allows you to switch strategies with a block, and to_sql called outside the block' do
      u = User.create!(name: 'pippo')
      Article.create!(mentioned_users: [u])

      ability = Ability.new(u)
      ability.can :read, Article, mentions: { user: { name: u.name } }

      subquery_sql = CanCan.with_accessible_by_strategy(:subquery) { Article.accessible_by(ability) }.to_sql
      left_join_sql = CanCan.with_accessible_by_strategy(:left_join) { Article.accessible_by(ability) }.to_sql

      expect(subquery_sql.strip.squeeze(' ')).to eq(%(
  SELECT "articles".*
  FROM "articles"
  WHERE "articles"."id" IN
  (SELECT "articles"."id"
    FROM "articles"
    LEFT OUTER JOIN "legacy_mentions" ON "legacy_mentions"."article_id" = "articles"."id"
    LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
    WHERE "users"."name" = 'pippo')
  ).gsub(/\s+/, ' ').strip)

      expect(left_join_sql.strip.squeeze(' ')).to eq(%(
  SELECT DISTINCT "articles".*
  FROM "articles"
  LEFT OUTER JOIN "legacy_mentions" ON "legacy_mentions"."article_id" = "articles"."id"
  LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
  WHERE "users"."name" = 'pippo').gsub(/\s+/, ' ').strip)
    end
  end

  CanCan.valid_accessible_by_strategies.each do |strategy|
    context "when a model has renamed primary_key with #{strategy} strategy" do
      before :each do
        CanCan.accessible_by_strategy = strategy
      end
      before do
        ActiveRecord::Schema.define do
          create_table(:custom_pk_users, primary_key: :gid) do |t|
            t.string :name
          end

          create_table(:custom_pk_transactions, primary_key: :gid) do |t|
            t.integer :custom_pk_user_id
            t.string :data
          end
        end

        class CustomPkUser < ActiveRecord::Base
          self.primary_key = 'gid'
        end

        class CustomPkTransaction < ActiveRecord::Base
          self.primary_key = 'gid'

          belongs_to :custom_pk_user
        end
      end

      it 'can filter correctly' do
        user1 = CustomPkUser.create!
        user2 = CustomPkUser.create!

        transaction1 = CustomPkTransaction.create!(custom_pk_user: user1)
        CustomPkTransaction.create!(custom_pk_user: user2)

        ability = Ability.new(user1)
        ability.can :read, CustomPkTransaction, custom_pk_user: { gid: user1.gid }

        expect(CustomPkTransaction.accessible_by(ability)).to match_array([transaction1])
      end
    end

    context "when a model has a composite primary key with #{strategy} strategy" do
      before :each do
        CanCan.accessible_by_strategy = strategy
      end
      before do
        ActiveRecord::Schema.define do
          create_table(:customers) do |t|
            t.boolean :vip
          end

          create_table(:orders, primary_key: %i[shop_id number]) do |t|
            t.integer :shop_id
            t.integer :number
            t.integer :customer_id
          end
        end

        class Customer < ActiveRecord::Base
        end

        class Order < ActiveRecord::Base
          self.primary_key = %i[shop_id number]

          belongs_to :customer
        end
      end

      let(:vip) { Customer.create!(vip: true) }
      let(:regular) { Customer.create!(vip: false) }
      let!(:vip_order) { Order.create!(shop_id: 1, number: 1, customer: vip) }
      let!(:regular_order) { Order.create!(shop_id: 1, number: 2, customer: regular) }
      let!(:other_shop_order) { Order.create!(shop_id: 2, number: 1, customer: regular) }

      it 'filters with a hash rule on an association' do
        ability = Ability.new(nil)
        ability.can :read, Order, customer: { vip: true }

        expect(Order.accessible_by(ability)).to contain_exactly(vip_order)
      end

      it 'merges a scope with a join with a hash rule' do
        ability = Ability.new(nil)
        ability.can :read, Order, Order.joins(:customer).where(customers: { vip: true })
        ability.can :read, Order, shop_id: 2

        expect(Order.accessible_by(ability)).to contain_exactly(vip_order, other_shop_order)
      end

      it 'negates a scope with a join of a cannot rule' do
        ability = Ability.new(nil)
        ability.can :read, Order
        ability.cannot :read, Order, Order.joins(:customer).where(customers: { vip: false })

        expect(Order.accessible_by(ability)).to contain_exactly(vip_order)
      end
    end
  end

  context 'when a table has json type column' do
    before do
      json_supported =
        ActiveRecord::Base.connection.respond_to?(:supports_json?) &&
        ActiveRecord::Base.connection.supports_json?

      skip "Adapter don't support JSON column type" unless json_supported

      ActiveRecord::Schema.define do
        create_table(:json_transactions) do |t|
          t.integer :user_id
          t.json :additional_data
        end
      end

      class JsonTransaction < ActiveRecord::Base
        belongs_to :user
      end
    end

    it 'can filter correctly if using subquery strategy' do
      CanCan.accessible_by_strategy = :subquery

      user = User.create!
      transaction = JsonTransaction.create!(user: user)

      ability = Ability.new(user)
      ability.can :read, JsonTransaction, user: { id: user.id }

      expect(JsonTransaction.accessible_by(ability)).to match_array([transaction])
    end

    # this fails on Postgres. see https://github.com/CanCanCommunity/cancancan/pull/608
    it 'cannot filter JSON on postgres columns using left_join strategy' do
      skip unless postgres?

      CanCan.accessible_by_strategy = :left_join

      user = User.create!
      JsonTransaction.create!(user: user)

      ability = Ability.new(user)
      ability.can :read, JsonTransaction, user: { id: user.id }

      expect { JsonTransaction.accessible_by(ability).to_a }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  context 'with rule application to subclass for non sti class' do
    before do
      ActiveRecord::Schema.define do
        create_table :parents, force: true

        create_table :children, force: true
      end

      class ApplicationRecord < ActiveRecord::Base
        self.abstract_class = true
      end

      class Parent < ActiveRecord::Base
      end

      class Child < Parent
      end
    end

    it 'cannot rules are not effecting parent class' do
      u1 = User.create!(name: 'pippo')
      ability = Ability.new(u1)
      ability.can :manage, Parent
      ability.cannot :manage, Child
      expect(ability).not_to be_able_to(:index, Child)
      expect(ability).to be_able_to(:index, Parent)
    end

    it 'can rules are not effecting parent class' do
      u1 = User.create!(name: 'pippo')
      ability = Ability.new(u1)
      ability.can :manage, Child
      expect(ability).to be_able_to(:index, Child)
      expect(ability).not_to be_able_to(:index, Parent)
    end
  end

  context 'when STI is in use' do
    before do
      ActiveRecord::Schema.define do
        create_table(:brands) do |t|
          t.string :name
        end

        create_table(:vehicles) do |t|
          t.string :type
          t.integer :capacity
        end
      end

      class ApplicationRecord < ActiveRecord::Base
        self.abstract_class = true
      end

      class Vehicle < ApplicationRecord
      end

      class Airplane < Vehicle
      end

      class Car < Vehicle
      end

      class Motorbike < Vehicle
      end

      class Suzuki < Motorbike
      end
    end

    it 'recognises rules applied to the base class' do
      u1 = User.create!(name: 'pippo')

      car = Car.create!
      motorbike = Motorbike.create!

      ability = Ability.new(u1)
      ability.can :read, Vehicle
      expect(Vehicle.accessible_by(ability)).to match_array([car, motorbike])
      expect(Car.accessible_by(ability)).to match_array([car])
      expect(Motorbike.accessible_by(ability)).to match_array([motorbike])
    end

    it 'recognises rules applied to the base class multiple classes deep' do
      u1 = User.create!(name: 'pippo')

      car = Car.create!
      motorbike = Motorbike.create!
      suzuki = Suzuki.create!

      ability = Ability.new(u1)
      ability.can :read, Vehicle
      expect(Vehicle.accessible_by(ability)).to match_array([suzuki, car, motorbike])
      expect(Car.accessible_by(ability)).to match_array([car])
      expect(Motorbike.accessible_by(ability)).to match_array([suzuki, motorbike])
      expect(Suzuki.accessible_by(ability)).to match_array([suzuki])
    end

    it 'recognises rules applied to subclasses' do
      u1 = User.create!(name: 'pippo')
      car = Car.create!
      Motorbike.create!

      ability = Ability.new(u1)
      ability.can :read, [Car]
      expect(Vehicle.accessible_by(ability)).to match_array([car])
      expect(Car.accessible_by(ability)).to eq([car])
      expect(Motorbike.accessible_by(ability)).to eq([])
    end

    it 'recognises rules applied to subclasses on 3 level' do
      u1 = User.create!(name: 'pippo')
      suzuki = Suzuki.create!
      Motorbike.create!
      ability = Ability.new(u1)
      ability.can :read, [Suzuki]
      expect(Motorbike.accessible_by(ability)).to eq([suzuki])
    end

    it 'recognises rules applied to subclass of subclass even with be_able_to' do
      u1 = User.create!(name: 'pippo')
      motorbike = Motorbike.create!
      ability = Ability.new(u1)
      ability.can :read, [Motorbike]
      expect(ability).to be_able_to(:read, motorbike)
      expect(ability).to be_able_to(:read, Suzuki.new)
    end

    it 'allows a scope of a subclass for conditions' do
      u1 = User.create!(name: 'pippo')
      car = Car.create!(capacity: 2)
      Car.create!(capacity: 4)
      Motorbike.create!(capacity: 2)

      ability = Ability.new(u1)
      ability.can :read, [Car], Car.where(capacity: 2)
      expect(Vehicle.accessible_by(ability)).to match_array([car])
      expect(Car.accessible_by(ability)).to eq([car])
      expect(Motorbike.accessible_by(ability)).to eq([])
    end

    it 'merges a scope of a subclass with the conditions of another subclass' do
      u1 = User.create!(name: 'pippo')
      car = Car.create!(capacity: 2)
      Car.create!(capacity: 4)
      motorbike = Motorbike.create!(capacity: 4)
      Motorbike.create!(capacity: 2)

      ability = Ability.new(u1)
      ability.can :read, Car, Car.where(capacity: 2)
      ability.can :read, Motorbike, capacity: 4
      expect(Vehicle.accessible_by(ability)).to contain_exactly(car, motorbike)
      expect(Car.accessible_by(ability)).to contain_exactly(car)
      expect(Motorbike.accessible_by(ability)).to contain_exactly(motorbike)
    end

    it 'allows a selectable scope when permit by two subclasses' do
      u1 = User.create!(name: 'pippo')
      Airplane.create!(capacity: 1)
      car = Car.create!(capacity: 4)
      mortorbike = Motorbike.create!(capacity: 2)

      ability = Ability.new(u1)
      ability.can :read, Car
      ability.can :read, Motorbike
      expect(Vehicle.accessible_by(ability)).to contain_exactly(car, mortorbike)
      expect(Airplane.accessible_by(ability)).to be_empty
      expect(Car.accessible_by(ability)).to contain_exactly(car)
      expect(Motorbike.accessible_by(ability)).to contain_exactly(mortorbike)
    end

    it 'allows access to both base class and subclass when permissions are defined for both' do
      u1 = User.create!(name: 'pippo')
      vehicle = Vehicle.create!(capacity: 1)
      car = Car.create!(capacity: 4)

      ability = Ability.new(u1)
      ability.can :read, Vehicle
      ability.can :read, Car
      expect(Vehicle.accessible_by(ability)).to contain_exactly(vehicle, car)
      expect(Car.accessible_by(ability)).to contain_exactly(car)
    end

    it 'applies rules defined on the base class and on several subclasses' do
      u1 = User.create!(name: 'pippo')
      vehicle = Vehicle.create!
      car = Car.create!
      motorbike = Motorbike.create!
      suzuki = Suzuki.create!

      ability = Ability.new(u1)
      ability.can :read, Vehicle
      ability.can :read, Car
      ability.can :read, Motorbike
      ability.can :read, Suzuki
      expect(Vehicle.accessible_by(ability)).to contain_exactly(vehicle, car, motorbike, suzuki)
      expect(Motorbike.accessible_by(ability)).to contain_exactly(motorbike, suzuki)
      expect(Suzuki.accessible_by(ability)).to contain_exactly(suzuki)
    end

    it 'excludes the records of a subclass forbidden by a cannot rule, like can? does' do
      u1 = User.create!(name: 'pippo')
      vehicle = Vehicle.create!
      car = Car.create!
      motorbike = Motorbike.create!

      ability = Ability.new(u1)
      ability.can :read, Vehicle
      ability.cannot :read, Car
      expect(Vehicle.accessible_by(ability)).to contain_exactly(vehicle, motorbike)
      expect(Car.accessible_by(ability)).to be_empty
      expect(ability.can?(:read, vehicle)).to be(true)
      expect(ability.can?(:read, motorbike)).to be(true)
      expect(ability.can?(:read, car)).to be(false)
    end

    it 'applies the conditions of a cannot rule defined on a subclass' do
      u1 = User.create!(name: 'pippo')
      vehicle = Vehicle.create!
      small_car = Car.create!(capacity: 2)
      big_car = Car.create!(capacity: 4)

      ability = Ability.new(u1)
      ability.can :read, Vehicle
      ability.cannot :read, Car, capacity: 4
      expect(Vehicle.accessible_by(ability)).to contain_exactly(vehicle, small_car)
      expect(ability.can?(:read, big_car)).to be(false)
      expect(ability.can?(:read, small_car)).to be(true)
    end

    it 'negates the scope of a cannot rule defined on a subclass' do
      u1 = User.create!(name: 'pippo')
      vehicle = Vehicle.create!
      small_car = Car.create!(capacity: 2)
      Car.create!(capacity: 4)

      ability = Ability.new(u1)
      ability.can :read, Vehicle
      ability.cannot :read, Car, Car.where(capacity: 4)
      expect(Vehicle.accessible_by(ability)).to contain_exactly(vehicle, small_car)
      expect(Car.accessible_by(ability)).to contain_exactly(small_car)
    end

    it 'applies a rule defined on a subclass of a subclass to the base class' do
      u1 = User.create!(name: 'pippo')
      Vehicle.create!
      Motorbike.create!
      suzuki = Suzuki.create!

      ability = Ability.new(u1)
      ability.can :read, Suzuki
      expect(Vehicle.accessible_by(ability)).to contain_exactly(suzuki)
      expect(Motorbike.accessible_by(ability)).to contain_exactly(suzuki)
      expect(ability.can?(:read, Vehicle)).to be(true)
      expect(ability.can?(:read, Motorbike)).to be(true)
      expect(ability.can?(:read, Car)).to be(false)
    end

    describe 'checking a class' do
      let(:ability) { Ability.new(User.create!(name: 'pippo')) }

      it 'passes when the class is allowed, even if a subclass is forbidden' do
        ability.can :read, Vehicle
        ability.cannot :read, Car
        expect(ability.can?(:read, Vehicle)).to be(true)
        expect(ability.can?(:read, Motorbike)).to be(true)
        expect(ability.can?(:read, Car)).to be(false)
      end

      it 'passes when a subclass is forbidden with conditions' do
        ability.can :read, Vehicle
        ability.cannot :read, Car, capacity: 4
        expect(ability.can?(:read, Vehicle)).to be(true)
        expect(ability.can?(:read, Car)).to be(true)
      end

      it 'passes when a subclass is allowed' do
        ability.can :read, Car
        expect(ability.can?(:read, Vehicle)).to be(true)
        expect(ability.can?(:read, Car)).to be(true)
        expect(ability.can?(:read, Motorbike)).to be(false)
      end

      it 'fails when the only allowed subclass is forbidden again' do
        ability.can :read, Car
        ability.cannot :read, Car
        expect(ability.can?(:read, Vehicle)).to be(false)
        expect(ability.can?(:read, Car)).to be(false)
      end

      it 'passes when a subclass is allowed after the class is forbidden' do
        ability.cannot :read, Vehicle
        ability.can :read, Car
        expect(ability.can?(:read, Vehicle)).to be(true)
        expect(ability.can?(:read, Car)).to be(true)
        expect(ability.can?(:read, Motorbike)).to be(false)
      end

      it 'passes for a subclass when one of its subclasses is forbidden' do
        ability.can :read, Motorbike
        ability.cannot :read, Suzuki
        expect(ability.can?(:read, Motorbike)).to be(true)
        expect(ability.can?(:read, Suzuki)).to be(false)
        expect(ability.can?(:read, Vehicle)).to be(true)
      end
    end
  end
end
