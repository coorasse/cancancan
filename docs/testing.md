# Testing

This is an authorization library. Testing the permissions you defined is not important, **is essential**.

Be really careful when defining your abilities, and be even more careful when testing them.

It can be difficult to thoroughly test user permissions at the functional/integration level because there are often many branching possibilities. Since CanCanCan handles all permission logic in `Ability` classes this makes it easy to have a solid set of unit test for complete coverage.

The `can?` method can be called directly on any `Ability` (like you would in the controller or view) so it is easy to test permission logic.

```ruby
test "user can only destroy projects which they own" do
  user = User.create!
  project = Project.new(user: user)
  ability = Ability.new(user)
  assert ability.can?(:destroy, project)
  assert ability.cannot?(:destroy, Project.new)
end
```

## RSpec

If you are testing the `Ability` class through RSpec there is a `be_able_to` matcher available. This checks if the `can?` method returns `true`.

```ruby
require "cancan/matchers"
ability = Ability.new(user)
expect(ability).to be_able_to(:destroy, Project.new(user: user))
expect(ability).not_to be_able_to(:destroy, Project.new)
```

The matcher calls `can?`, so when you pass a class the conditions of the rules are ignored. To test the conditions, check instances or the records returned by `accessible_by`:

```ruby
can :index, Product, brand_id: user.brand_ids

expect(ability).to be_able_to(:index, Product.new(brand_id: allowed_brand.id))
expect(ability).not_to be_able_to(:index, Product.new(brand_id: other_brand.id))
expect(Product.accessible_by(ability, :index)).to contain_exactly(allowed_product)
```

The matcher accepts an array of actions, which passes only when all of them are allowed:

```ruby
expect(ability).to be_able_to(%i[read update], Project.new(user: user))
```

The negated form does not accept an array, because it would pass as soon as one action is forbidden. Write one expectation per action:

```ruby
expect(ability).not_to be_able_to(:update, Project.new)
expect(ability).not_to be_able_to(:destroy, Project.new)
```

Pro way 😉

```ruby
require "cancan/matchers"

describe "User" do
  describe "abilities" do
    subject(:ability) { Ability.new(user) }
    let(:user) { nil }

    context "when is an account manager" do
      let(:user) { create(:account_manager) }

      it { is_expected.to be_able_to(:manage, Account.new) }
    end
  end
end
```

## Cucumber

By default, Cucumber will ignore the `rescue_from` call in the `ApplicationController` and report the `CanCan::AccessDenied` exception when running the features. If you want full integration testing you can change this behavior so the exception is caught by Rails. You can do so by setting this in the `env.rb` file.

```ruby
# in features/support/env.rb
ActionController::Base.allow_rescue = true
```

Alternatively, if you don't want to allow rescue on everything, you can tag individual scenarios with `@allow-rescue` tag.

```ruby
@allow-rescue
Scenario: Update Article
```

Here the `rescue_from` block will take effect only in this scenario.

## Request Testing

If you want to test authorization functionality at the request level, one option is to log-in the user who has the appropriate permissions.

```ruby
user = User.create!(admin: true)
article = Article.create!
login user, as: :user # in devise
get article_path(article)
expect(response).to have_http_status(:ok)
```

If you have very complex permissions it can lead to many branching possibilities. If these are all tested in the request layer then it can lead to slow and bloated tests.

Instead we recommend keeping request authorization tests light and testing the authorization functionality more thoroughly in the Ability model through unit tests as shown at the top.
