# Model Adapter

CanCanCan includes a model adapter system that allows developers to add their own adapters for handling behaviour depending on the model used.

CanCanCan provides maintained adapters for the following model types:

- ActiveRecord (native in `cancancan` gem)
- [Mongoid](https://github.com/CanCanCommunity/cancancan-mongoid)

## Creating a Model Adapter

Due to its flexible and extendable system of adapters, it is easy to implement a custom adapter if the currently provided adapters do not suffice.

To facilitate an easy implementation of a new adapter CanCanCan provides you with an [Abstract Adapter](https://github.com/CanCanCommunity/cancancan/blob/main/lib/cancan/model_adapters/abstract_adapter.rb) you can extend and build upon. This design allows for dynamic adapter handling and a decoupled handling of information.

### The Abstract Adapter

The abstract adapter has multiple methods that one has to overwrite in order to match the behaviour that is expected. It is used by the system to delegate the handling of fetching entries base on defined rules and conditions.

#### for_class

The `for_class?` method is a static method on the abstract adapter that has to be overwritten in your adapter.

This method is used to determine whether a model should be passed to the adapter or not.

If your `for_class?` implementation returns true, the adapter will be provided with the model to build and match the rules defined.

Otherwise the adapter will be skipped and the other subclasses of the abstract adapter will be checked.

#### database_records

Used to implement the loading of entries from the database, by a developer-defined handling of the given rules for a model.

### Dependencies

Because cancancan wants to provide an easy method of writing and testing your own adapters it uses appraisals to test the code against different versions of dependencies.

[Appraisals](https://github.com/thoughtbot/appraisal)

Thus you can add your own entry for your gems and dependencies.

An example could look like:

cancancan/Appraisals

```ruby

appraise 'cancancan_custom_adapter' do
  gem 'activerecord', '~> 8.1.0', require: 'active_record'

  platforms :jruby do
    gem 'jdbc-postgres'
  end

  platforms :ruby, :windows do
    gem 'pg', '~> 1.5.6'
  end
end
```

You would have to replace the dependencies with ones that fit your custom adapter.

After creating your dependency definition, run

```bash
bundle exec appraisal install
```

to install dependencies for your adapter.

### The Specs

To illustrate what a test for an adapter could look like, we will use [Mongoid](https://github.com/CanCanCommunity/cancancan-mongoid) as an example.

In good TDD fashion we create a spec / test for the new adapter to later confirm our implementation.

```ruby

RSpec.describe CanCan::ModelAdapters::MongoidAdapter do

  it 'is for only Mongoid classes' do
    expect(CanCan::ModelAdapters::MongoidAdapter).not_to be_for_class(Object)
    expect(CanCan::ModelAdapters::MongoidAdapter).to be_for_class(MongoidProject)
  end

  it 'finds record' do
      project = MongoidProject.create
      expect(CanCan::ModelAdapters::MongoidAdapter.find(MongoidProject, project.id)).to eq(project)
  end

  it "should return the correct records based on the defined ability" do
        @ability.can :read, MongoidProject, :title => "Sir"
        sir   = MongoidProject.create(:title => 'Sir')
        lord  = MongoidProject.create(:title => 'Lord')
        MongoidProject.accessible_by(@ability, :read).entries.should == [sir]
  end

end
```

In this case `MongoidProject` is a descendant of `MongoidDocument`. The implementation of this class will not be shown as it only acts as an example.

### Running tests

You can run tests for the project by running

```bash
bundle exec appraisal rake
```

or you can run tests only for your adapter with

```bash
bundle exec appraisal adapter_name rake
```

File specific tests can be run with:

```shell
bundle exec appraisal adapter_name rspec spec/cancan/model_adapters/adapter_name.rb
```

**Because we haven't implemented any functionality yet, the tests will fail.**

### The Implementation

First add a line to `lib/cancan.rb` to include the adapter if a condition is met. In this case we check if Mongoid is present.

```ruby
require 'cancan/model_adapters/mongoid_adapter' if defined? Mongoid
```

And after that, create a new adapter in `model_adapters`:

```ruby
module CanCan
  module ModelAdapters
    class MongoidAdapter < AbstractAdapter
      def self.for_class?(model_class)
        model_class <= Mongoid::Document
      end

      def database_records
        if @rules.size == 0
          @model_class.where(:_id => {'$exists' => false, '$type' => 7}) # return no records in Mongoid
        else
          @rules.inject(@model_class.all) do |records, rule|
            if rule.base_behavior
              records.or(rule.conditions)
            else
              records.excludes(rule.conditions)
            end
          end
        end
      end
    end
  end
end

module Mongoid::Document::ClassMethods
  include CanCan::ModelAdditions::ClassMethods
end
```

As mentioned before, there are methods that have to be overwritten in order to pass as a valid adapter.

In this case we overwrite the `for_class?` method to validate that the given model is a descendant of MongoidDocument. The adapter will only be used if `for_class?` evalues to true.

And in `database_records` we define the way data is loaded from the storage device. This message is used in `accessible_by`. In this example we fetch all entries for a model that match a given rule.

**If no rules for an object are defined, a query will be run that returns no results.**

If rules are present, we apply each of the rule conditions to them. The `rule.base_behavior` defines whether the rule should be additive or subtractive. It will result in false for `:cannot` and true for `:can`.

Some model types add additional features to the conditions hash. With Mongoid, for example, you can do something like `:age.gt => 13`.
Because the abstract adapter has no knowledge of this, we have to overwrite the provided methods in the new adapter.

```ruby
def self.override_conditions_hash_matching?(subject, conditions)
  conditions.any? { |k,v| !k.kind_of?(Symbol) }
end

def self.matches_conditions_hash?(subject, conditions)
  subject.matches? subject.class.where(conditions).selector
end
```

### Additional Examples

Eventhough CanCanCan tries to make the implementation of custom adapters easy and flexible, it can be hard task.

Thus you'd probably be best served with inspecting the actual implementation of the `activerecord` adapter to get a better overview how a battle tested adapter is structured and implemented.

#### Implementation

- [ActiveRecord](https://github.com/CanCanCommunity/cancancan/blob/main/lib/cancan/model_adapters/active_record_adapter.rb)

#### Tests / Specs

- [ActiveRecord](https://github.com/CanCanCommunity/cancancan/blob/main/spec/cancan/model_adapters/active_record_adapter_spec.rb)
- [ActiveRecord enums](https://github.com/CanCanCommunity/cancancan/blob/main/spec/cancan/model_adapters/active_record_adapter_enum_spec.rb)

**Mongoid, the adapter used in this entry as an example, can be found at:**

- [Mongoid](https://github.com/CanCanCommunity/cancancan-mongoid)
