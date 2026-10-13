# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CanCan::ModelAdapters::ActiveRecordAdapter do
  let(:ability) { double.extend(CanCan::Ability) }

  before do
    connect_db
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Schema.define do
      create_table(:alias_companies) { |t| t.string :code }
      create_table(:alias_teams) { |t| t.integer :company_id }
      create_table(:alias_team_accesses) do |t|
        t.integer :privileged_team_id
        t.integer :accessible_team_id
      end
      create_table(:alias_memberships) { |t| t.integer :team_id }
      create_table(:alias_appreciations) do |t|
        t.integer :receiver_id
        t.integer :team_id
      end
    end

    stub_const('AliasUpcaseType', Class.new(ActiveModel::Type::String) do
      def serialize(value)
        super&.upcase
      end
    end)
    stub_const('AliasCompany', Class.new(ActiveRecord::Base) do
      attribute :code, AliasUpcaseType.new
    end)
    stub_const('AliasTeam', Class.new(ActiveRecord::Base) do
      belongs_to :company, class_name: 'AliasCompany'
      has_many :accessible_by_team_accesses, class_name: 'AliasTeamAccess', foreign_key: :accessible_team_id
      has_many :privileged_teams, through: :accessible_by_team_accesses
    end)
    stub_const('AliasTeamAccess', Class.new(ActiveRecord::Base) do
      belongs_to :privileged_team, class_name: 'AliasTeam'
      belongs_to :accessible_team, class_name: 'AliasTeam'
    end)
    stub_const('AliasMembership', Class.new(ActiveRecord::Base) do
      belongs_to :team, class_name: 'AliasTeam'
    end)
    stub_const('AliasAppreciation', Class.new(ActiveRecord::Base) do
      belongs_to :receiver, class_name: 'AliasMembership'
      belongs_to :team, class_name: 'AliasTeam'
    end)
  end

  def appreciation(team: AliasTeam.create!, receiver_team: AliasTeam.create!)
    AliasAppreciation.create!(team: team, receiver: AliasMembership.create!(team: receiver_team))
  end

  CanCan.valid_accessible_by_strategies.each do |strategy|
    context "using #{strategy} strategy" do
      around do |example|
        CanCan.with_accessible_by_strategy(strategy) { example.run }
      end

      context 'with a has_many through association below an association without conditions' do
        let(:deep) { { receiver: { team: { privileged_teams: { id: @team1.id } } } } }
        let(:shallow) { { receiver: { team: { id: @team1.id } } } }

        before do
          @team1 = AliasTeam.create!
          @team2 = AliasTeam.create!
          AliasTeamAccess.create!(privileged_team: @team1, accessible_team: @team2)
          @own = appreciation(receiver_team: @team1)
          @privileged = appreciation(receiver_team: @team2)
          @other = appreciation
        end

        it 'uses the alias of the joined table' do
          ability.can :read, AliasAppreciation, deep

          expect(AliasAppreciation.accessible_by(ability)).to contain_exactly(@privileged)
        end

        it 'combines it with a rule on the same association defined before' do
          ability.can :read, AliasAppreciation, shallow
          ability.can :read, AliasAppreciation, deep

          expect(AliasAppreciation.accessible_by(ability)).to contain_exactly(@own, @privileged)
        end

        it 'combines it with a rule on the same association defined after' do
          ability.can :read, AliasAppreciation, deep
          ability.can :read, AliasAppreciation, shallow

          expect(AliasAppreciation.accessible_by(ability)).to contain_exactly(@own, @privileged)
        end

        it 'uses the aliases of the joins of a cannot rule checked in a subquery' do
          ability.can :read, AliasAppreciation, team: { company_id: nil }
          ability.cannot :read, AliasAppreciation,
                         receiver: { team: { id: @team2.id, privileged_teams: { id: @team1.id } } }
          ability.can :read, AliasAppreciation, team: { id: nil }

          expect(AliasAppreciation.accessible_by(ability)).to contain_exactly(@own, @other)
        end
      end

      context 'with conditions on an aliased table' do
        before do
          @company = AliasCompany.create!(code: 'abc')
          @receiver_team_with_company = appreciation(receiver_team: AliasTeam.create!(company: @company))
          @team_with_company = appreciation(team: AliasTeam.create!(company: @company))
          appreciation(receiver_team: AliasTeam.create!(company: AliasCompany.create!(code: 'x')))
        end

        it 'converts a model to its foreign key' do
          ability.can :read, AliasAppreciation, team: { company: @company }
          ability.can :read, AliasAppreciation, receiver: { team: { company: @company } }

          expect(AliasAppreciation.accessible_by(ability))
            .to contain_exactly(@receiver_team_with_company, @team_with_company)
        end

        it 'casts the values with the attribute types of the model' do
          ability.can :read, AliasAppreciation, team: { company: { code: 'abc' } }
          ability.can :read, AliasAppreciation, receiver: { team: { company: { code: 'abc' } } }

          expect(AliasAppreciation.accessible_by(ability))
            .to contain_exactly(@receiver_team_with_company, @team_with_company)
        end

        it 'casts the values of a single rule with the attribute types of the model' do
          ability.can :read, AliasAppreciation, receiver: { team: { company: { code: 'abc' } } }

          expect(AliasAppreciation.accessible_by(ability)).to contain_exactly(@receiver_team_with_company)
        end
      end

      it 'uses the aliases of the tables joined for nil conditions' do
        receiver_team = AliasTeam.create!
        without_company = appreciation(receiver_team: receiver_team)
        appreciation(team: AliasTeam.create!(company: AliasCompany.create!), receiver_team: receiver_team)
        ability.can :read, AliasAppreciation, team: { company_id: nil }, receiver: { team: { id: receiver_team.id } }

        expect(AliasAppreciation.accessible_by(ability)).to contain_exactly(without_company)
      end
    end
  end
end
