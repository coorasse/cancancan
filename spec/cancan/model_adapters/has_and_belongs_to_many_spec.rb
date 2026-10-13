require 'spec_helper'

RSpec.describe CanCan::ModelAdapters::ActiveRecordAdapter do
  let(:ability) { double.extend(CanCan::Ability) }
  let(:users_table) { User.table_name }
  let(:posts_table) { Post.table_name }

  before :all do
    connect_db
    ActiveRecord::Migration.verbose = false

    ActiveRecord::Schema.define do
      create_table(:people) do |t|
        t.string :name
        t.timestamps null: false
      end

      create_table(:houses) do |t|
        t.boolean :restructured, default: true
        t.timestamps null: false
      end

      create_table(:houses_people) do |t|
        t.integer :person_id
        t.integer :house_id
        t.timestamps null: false
      end
    end

    class Person < ActiveRecord::Base
      has_and_belongs_to_many :houses
    end

    class House < ActiveRecord::Base
      has_and_belongs_to_many :people
    end
  end

  before do
    @person1 = Person.create!
    @person2 = Person.create!
    @house1 = House.create!(people: [@person1])
    @house2 = House.create!(restructured: false, people: [@person1, @person2])
    @house3 = House.create!(people: [@person2])
    ability.can :read, House, people: { id: @person1.id }
  end

  describe 'fetching of records - joined_alias_subquery strategy' do
    before do
      CanCan.accessible_by_strategy = :joined_alias_exists_subquery
    end

    it 'it retreives the records correctly' do
      houses = House.accessible_by(ability)
      expect(houses).to match_array [@house2, @house1]
    end

    it 'generates the correct query' do
      expect(ability.model_adapter(House, :read))
        .to generate_sql("SELECT \"houses\".*
                         FROM \"houses\"
                         JOIN \"houses\" AS \"houses_alias\" ON \"houses_alias\".\"id\" = \"houses\".\"id\"
                         WHERE (EXISTS (SELECT 1
                           FROM \"houses\"
                           LEFT OUTER JOIN \"houses_people\" ON \"houses_people\".\"house_id\" = \"houses\".\"id\"
                           LEFT OUTER JOIN \"people\" ON \"people\".\"id\" = \"houses_people\".\"person_id\"
                           WHERE
                             \"people\".\"id\" = #{@person1.id} AND
                             (\"houses\".\"id\" = \"houses_alias\".\"id\") LIMIT 1))
                        ")
    end
  end

  describe 'fetching of records - joined_alias_each_rule_as_exists_subquery strategy' do
    before do
      CanCan.accessible_by_strategy = :joined_alias_each_rule_as_exists_subquery
    end

    it 'it retreives the records correctly' do
      houses = House.accessible_by(ability)
      expect(houses).to match_array [@house2, @house1]
    end

    it 'generates the correct query' do
      expect(ability.model_adapter(House, :read))
        .to generate_sql("SELECT \"houses\".*
                         FROM \"houses\"
                         JOIN \"houses\" AS \"houses_alias\" ON \"houses_alias\".\"id\" = \"houses\".\"id\"
                         WHERE (EXISTS (SELECT 1
                           FROM \"houses\"
                           INNER JOIN \"houses_people\" ON \"houses_people\".\"house_id\" = \"houses\".\"id\"
                           INNER JOIN \"people\" ON \"people\".\"id\" = \"houses_people\".\"person_id\"
                           WHERE (\"houses\".\"id\" = \"houses_alias\".\"id\") AND
                           \"people\".\"id\" = #{@person1.id}
                           LIMIT 1))
                         ")
    end
  end

  describe 'fetching of records - subquery strategy' do
    before do
      CanCan.accessible_by_strategy = :subquery
    end

    it 'it retrieves the records correctly' do
      houses = House.accessible_by(ability)
      expect(houses).to match_array [@house2, @house1]
    end

    it 'generates the correct query' do
      expect(ability.model_adapter(House, :read))
        .to generate_sql("SELECT \"houses\".*
                        FROM \"houses\"
                        WHERE \"houses\".\"id\" IN
                          (SELECT \"houses\".\"id\"
                          FROM \"houses\"
                          LEFT OUTER JOIN \"houses_people\" ON \"houses_people\".\"house_id\" = \"houses\".\"id\"
                          LEFT OUTER JOIN \"people\" ON \"people\".\"id\" = \"houses_people\".\"person_id\"
                          WHERE \"people\".\"id\" = #{@person1.id})
                        ")
    end
  end

  describe 'fetching of records - left_join strategy' do
    before do
      CanCan.accessible_by_strategy = :left_join
    end

    it 'it retrieves the records correctly' do
      houses = House.accessible_by(ability)
      expect(houses).to match_array [@house2, @house1]
    end

    it 'generates the correct query' do
      expect(ability.model_adapter(House, :read)).to generate_sql(%(
    SELECT DISTINCT "houses".*
    FROM "houses"
    LEFT OUTER JOIN "houses_people" ON "houses_people"."house_id" = "houses"."id"
    LEFT OUTER JOIN "people" ON "people"."id" = "houses_people"."person_id"
    WHERE "people"."id" = #{@person1.id}))
    end
  end
end
