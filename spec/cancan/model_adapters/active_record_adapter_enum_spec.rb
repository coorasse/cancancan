# frozen_string_literal: true

require 'spec_helper'

describe CanCan::ModelAdapters::ActiveRecordAdapter do
  CanCan.valid_accessible_by_strategies.each do |strategy|
    context "with sqlite3 and #{strategy} strategy" do
      before :each do
        CanCan.accessible_by_strategy = strategy

        connect_db
        ActiveRecord::Migration.verbose = false

        ActiveRecord::Schema.define do
          create_table(:shapes) do |t|
            t.integer :color, default: 0, null: false
          end

          create_table(:things) do |t|
            t.string :size, default: 'big', null: false
          end

          create_table(:discs) do |t|
            t.integer :color, default: 0, null: false
            t.integer :shape, default: 3, null: false
          end

          create_table(:foods) do |t|
            t.integer :status
          end
        end

        unless defined?(Food)
          class Food < ActiveRecord::Base
            enum :status, %i[rotten good]
          end
        end

        unless defined?(Thing)
          class Thing < ActiveRecord::Base
            enum :size, { big: 'big', medium: 'average', small: 'small' }
          end
        end

        unless defined?(Shape)
          class Shape < ActiveRecord::Base
            enum :color, %i[red green blue]
          end
        end

        unless defined?(Disc)
          class Disc < ActiveRecord::Base
            enum :color, %i[red green blue]
            enum :shape, { triangle: 3, rectangle: 4 }
          end
        end
      end

      subject(:ability) { Ability.new(nil) }

      context 'when enum allows null values' do
        let(:rotten) { Food.create!(status: :rotten) }
        let(:good) { Food.create!(status: :good) }
        let(:no_status) { Food.create!(status: nil) }

        context 'when the condition contains a single value' do
          before do
            ability.can :eat, Food, status: nil
          end

          it 'can check ability on single models' do
            is_expected.not_to be_able_to(:eat, rotten)
            is_expected.to be_able_to(:eat, no_status)
            is_expected.not_to be_able_to(:eat, good)
          end

          it 'can use accessible_by helper' do
            accessible = Food.accessible_by(ability, :eat)
            expect(accessible).to contain_exactly(no_status)
          end
        end

        context 'when the condition contains multiple values' do
          before do
            ability.can :eat, Food, status: [nil, :good]
          end

          it 'can check ability on single models' do
            is_expected.not_to be_able_to(:eat, rotten)
            is_expected.to be_able_to(:eat, no_status)
            is_expected.to be_able_to(:eat, good)
          end

          it 'can use accessible_by helper' do
            accessible = Food.accessible_by(ability, :eat)
            expect(accessible).to contain_exactly(no_status, good)
          end
        end
      end

      context 'when enums use integers as values' do
        let(:red) { Shape.create!(color: :red) }
        let(:green) { Shape.create!(color: :green) }
        let(:blue) { Shape.create!(color: :blue) }

        context 'when the condition contains a single value' do
          before do
            ability.can :read, Shape, color: :green
          end

          it 'can check ability on single models' do
            is_expected.not_to be_able_to(:read, red)
            is_expected.to be_able_to(:read, green)
            is_expected.not_to be_able_to(:read, blue)
          end

          it 'can use accessible_by helper' do
            accessible = Shape.accessible_by(ability)
            expect(accessible).to contain_exactly(green)
          end
        end

        context 'when the condition contains multiple values' do
          before do
            ability.can :update, Shape, color: %i[red blue]
          end

          it 'can check ability on single models' do
            is_expected.to be_able_to(:update, red)
            is_expected.not_to be_able_to(:update, green)
            is_expected.to be_able_to(:update, blue)
          end

          it 'can use accessible_by helper' do
            accessible = Shape.accessible_by(ability, :update)
            expect(accessible).to contain_exactly(red, blue)
          end
        end
      end

      context 'when enums use strings as values' do
        let(:big) { Thing.create!(size: :big) }
        let(:medium) { Thing.create!(size: :medium) }
        let(:small) { Thing.create!(size: :small) }

        context 'when the condition contains a single value' do
          before do
            ability.can :read, Thing, size: :medium
          end

          it 'can check ability on single models' do
            is_expected.not_to be_able_to(:read, big)
            is_expected.to be_able_to(:read, medium)
            is_expected.not_to be_able_to(:read, small)
          end

          it 'can use accessible_by helper' do
            expect(Thing.accessible_by(ability)).to contain_exactly(medium)
          end

          context 'when a rule is overridden' do
            before do
              ability.cannot :read, Thing, size: 'average'
            end

            it 'is recognised correctly' do
              is_expected.not_to be_able_to(:read, medium)
              expect(Thing.accessible_by(ability)).to be_empty
            end
          end
        end

        context 'when the condition contains multiple values' do
          before do
            ability.can :update, Thing, size: %i[big small]
          end

          it 'can check ability on single models' do
            is_expected.to be_able_to(:update, big)
            is_expected.not_to be_able_to(:update, medium)
            is_expected.to be_able_to(:update, small)
          end

          it 'can use accessible_by helper' do
            expect(Thing.accessible_by(ability, :update)).to contain_exactly(big, small)
          end
        end
      end

      context 'when multiple enums are present' do
        let(:red_triangle) { Disc.create!(color: :red, shape: :triangle) }
        let(:green_triangle) { Disc.create!(color: :green, shape: :triangle) }
        let(:green_rectangle) { Disc.create!(color: :green, shape: :rectangle) }
        let(:blue_rectangle) { Disc.create!(color: :blue, shape: :rectangle) }

        before do
          ability.can :read, Disc, color: :green, shape: :rectangle
        end

        it 'can check ability on single models' do
          is_expected.not_to be_able_to(:read, red_triangle)
          is_expected.not_to be_able_to(:read, green_triangle)
          is_expected.to be_able_to(:read, green_rectangle)
          is_expected.not_to be_able_to(:read, blue_rectangle)
        end

        it 'can use accessible_by helper' do
          expect(Disc.accessible_by(ability)).to contain_exactly(green_rectangle)
        end
      end
    end
  end
end
