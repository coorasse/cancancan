# frozen_string_literal: true

require 'spec_helper'

# accessible_by must not return records that can? denies.
RSpec.describe CanCan::ModelAdapters::ActiveRecordAdapter do
  let(:ability) { double.extend(CanCan::Ability) }

  before :each do
    connect_db
    ActiveRecord::Migration.verbose = false

    ActiveRecord::Schema.define do
      create_table(:stories) do |t|
        t.string :title
        t.boolean :secret
        t.boolean :published
      end

      create_table(:replies) do |t|
        t.integer :story_id
        t.boolean :spam
      end

      create_table(:labels) do |t|
        t.string :name
      end

      create_table(:topics) do |t|
        t.string :name
      end

      create_table(:labellings) do |t|
        t.integer :story_id
        t.integer :label_id
        t.integer :topic_id
      end

      create_table(:plants) do |t|
        t.string :type
      end
    end

    stub_const('Story', Class.new(ActiveRecord::Base) do
      has_many :replies
      has_many :labellings
      has_many :labels, through: :labellings
      has_many :topics, through: :labellings
    end)
    stub_const('Reply', Class.new(ActiveRecord::Base) { belongs_to :story })
    stub_const('Label', Class.new(ActiveRecord::Base))
    stub_const('Topic', Class.new(ActiveRecord::Base))
    stub_const('Labelling', Class.new(ActiveRecord::Base) do
      belongs_to :story
      belongs_to :label
      belongs_to :topic
    end)
    stub_const('Plant', Class.new(ActiveRecord::Base))
    stub_const('Tree', Class.new(Plant))
    stub_const('Oak', Class.new(Tree))
  end

  CanCan.valid_accessible_by_strategies.each do |strategy|
    context "with the #{strategy} strategy" do
      before { CanCan.accessible_by_strategy = strategy }

      it 'keeps the conditions of every has_many through association that shares the through table' do
        story = Story.create!
        Labelling.create!(story: story, label: Label.create!(name: 'z'), topic: Topic.create!(name: 'y'))
        allowed = Story.create!
        Labelling.create!(story: allowed, label: Label.create!(name: 'x'), topic: Topic.create!(name: 'y'))
        ability.can :read, Story, labels: { name: 'x' }, topics: { name: 'y' }

        expect(ability.can?(:read, story)).to be(false)
        expect(Story.accessible_by(ability)).to eq([allowed])
      end

      it 'excludes the subclasses of a class denied by a cannot rule' do
        plant = Plant.create!
        Oak.create!
        ability.can :read, Plant
        ability.cannot :read, Tree

        expect(ability.can?(:read, Oak.first)).to be(false)
        expect(Plant.accessible_by(ability)).to eq([plant])
      end

      it 'filters by type a rule on a subclass and a class without single table inheritance' do
        Plant.create!
        oak = Oak.create!
        label = Label.create!
        ability.can :read, [Tree, Label]

        expect(Plant.accessible_by(ability)).to eq([oak])
        expect(Label.accessible_by(ability)).to eq([label])
      end

      it 'applies a cannot rule defined after a rule with conditions on an association' do
        secret = Story.create!(secret: true)
        Reply.create!(story: secret, spam: false)
        allowed = Story.create!(secret: false)
        Reply.create!(story: allowed, spam: false)
        ability.can :read, Story, replies: { spam: false }
        ability.cannot :read, Story, secret: true

        expect(ability.can?(:read, secret)).to be(false)
        expect(Story.accessible_by(ability)).to eq([allowed])
      end

      it 'gives precedence to a can rule defined after a cannot rule on an association' do
        story = Story.create!(published: true)
        Reply.create!(story: story, spam: true)
        ability.cannot :read, Story, replies: { spam: true }
        ability.can :read, Story, published: true

        expect(ability.can?(:read, story)).to be(true)
        expect(Story.accessible_by(ability)).to eq([story])
      end

      it 'excludes a record when any of its has_many records matches a cannot rule' do
        story = Story.create!
        Reply.create!(story: story, spam: true)
        Reply.create!(story: story, spam: false)
        allowed = Story.create!
        Reply.create!(story: allowed, spam: false)
        without_replies = Story.create!
        ability.can :read, Story
        ability.cannot :read, Story, replies: { spam: true }

        expect(ability.can?(:read, story)).to be(false)
        expect(Story.accessible_by(ability)).to contain_exactly(allowed, without_replies)
      end

      it 'excludes a record when any of its has_many through records matches a cannot rule' do
        story = Story.create!
        Labelling.create!(story: story, label: Label.create!(name: 'hidden'))
        Labelling.create!(story: story, label: Label.create!(name: 'visible'))
        allowed = Story.create!
        Labelling.create!(story: allowed, label: Label.create!(name: 'visible'))
        ability.can :read, Story, labels: { name: 'visible' }
        ability.cannot :read, Story, labels: { name: 'hidden' }

        expect(ability.can?(:read, story)).to be(false)
        expect(Story.accessible_by(ability)).to eq([allowed])
      end

      it 'excludes the records without associated records with a cannot rule on nil values' do
        Story.create!
        with_replies = Story.create!
        Reply.create!(story: with_replies)
        ability.can :read, Story
        ability.cannot :read, Story, replies: { id: nil }

        expect(ability.can?(:read, Story.first)).to be(false)
        expect(Story.accessible_by(ability)).to eq([with_replies])
      end

      it 'does not exclude the records with NULL in the column of a cannot rule' do
        secret = Story.create!(secret: true)
        unknown = Story.create!(secret: nil)
        ability.can :read, Story
        ability.cannot :read, Story, secret: true

        expect(ability.can?(:read, secret)).to be(false)
        expect(Story.accessible_by(ability)).to eq([unknown])
      end
    end
  end

  it 'checks in a subquery only the cannot rules on a has_many association' do
    ability.can :read, Story
    ability.cannot :read, Story, secret: true
    ability.cannot :read, Story, replies: { spam: true }

    expect(Story.accessible_by(ability).to_sql).to match(
      /WHERE \("stories"\."id" IN \(SELECT .+\)\) IS NOT TRUE AND \(\("stories"\."secret" = \S+\) IS NOT TRUE\)\z/
    )
    expect(ability.model_adapter(Story, :read).joins).to be_nil
  end

  it 'does not return the records of a cannot rule defined with a scope' do
    Story.create!(secret: true)
    ability.cannot :read, Story, Story.where(secret: true)

    expect(Story.accessible_by(ability)).to be_empty
  end

  it 'keeps the other rules next to a scope with a where clause in SQL' do
    published = Story.create!(published: true, secret: true)
    public_story = Story.create!(published: false, secret: false)
    Story.create!(published: false, secret: true)
    ability.can :read, Story, published: true
    ability.can :read, Story, Story.where('secret = ?', false)

    expect(Story.accessible_by(ability)).to contain_exactly(published, public_story)
  end
end
