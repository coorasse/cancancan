# Defining abilities - Hash of conditions

Let's start our journey into the abilities definition by explaining the CanCanCan Hash of conditions mechanism.

In the chapter [Define and Check Abilities](./define_check_abilities.md) we defined

```ruby
can :update, @article, user: user
```

to say that an Article can be updated only by it's author. But how does it work?

The third argument of the `can` method (`{ user: user }`) is the hash of conditions for this rule.

A hash of conditions can be passed to further restrict which records this permission applies to.

In the example below the user will only have permission to read active projects which they own.

```ruby
can :read, Project, active: true, user_id: user.id
```

When defining a condition, the key should always be either a database column of the model, or the association name. In the example above, if the Project has defined

```ruby
belongs_to :owner, class_name: 'User', foreign_key: :user_id
```

the rule can also be written as:

```ruby
can :read, Project, active: true, owner: user
```

so by using the association `owner` instead of the database column `user_id`.

You can nest conditions associations. Here the project can only be read if the category it belongs to is visible.

```ruby
can :read, Project, category: { visible: true }
```

An array or range can be passed to match multiple values. Here the user can only read projects of priority 1 through 3.

```ruby
can :read, Project, priority: 1..3
```

If you want to a negative match, you can pass in `nil`.

```ruby
# Can read projects that don't have any members.
can :read, Project, members: { id: nil }
```

This is also true for any condition on a `has_many` association where all values are `nil`: it matches the records with no associated records at all. For example, `can :read, Document, authors: { user_id: nil }` allows documents with an author without user, but also documents without authors. Add `cannot :read, Document, authors: { id: nil }` to exclude the latter.

Almost anything that you can pass to a hash of conditions in ActiveRecord will work here as well.

A nested hash always refers to an association, so keys inside a `json` or `jsonb` column cannot be used as conditions. Expose the key as a column instead, for example with a stored generated column, and use it as any other attribute:

```ruby
# migration
t.virtual :shop_id, type: :integer, as: "(data->>'shop_id')::int", stored: true

# ability
can :read, Product, shop_id: user.shop_id
```

## Arrays and relations as values

The value of a condition can be an array, in which case the attribute has to match one of its elements:

```ruby
can :read, Project, id: user.project_ids
```

It can also be an Active Record relation that selects a single column, or no column at all, in which case the primary key is used:

```ruby
can :read, Project, id: Project.where(user_id: user.id).select(:id)
```

`accessible_by` turns the relation into a subquery. `can?` runs one `EXISTS` query per check, so prefer an array when the checks are many and the set of values is small.

## Traverse associations

All associations can be traversed when defining a rule.

```ruby
class User
  belongs_to :account
end

class Account
  has_one :user
  has_many :services
end

class Service
  belongs_to :account
  has_many :parts
end

class Part
  belongs_to :service
end

# Ability
can :manage, Part, service: { account: { user: user } }
```

## Collection associations

`can?` does not load the records of a `has_many` or `has_and_belongs_to_many` association to check the conditions
below it. When the association is not loaded, the conditions are checked with one query, the same one that
`accessible_by` would build:

```ruby
can :read, Author, books: { user: user }

can? :read, author # SELECT 1 FROM books WHERE books.author_id = ? AND books.user_id = ? LIMIT 1
author.books.loaded? # => false
```

When the association is already loaded, for example through `includes`, the loaded records are checked in memory
and no query runs. The keys below such an association must be columns or associations, as for `accessible_by`.

Let's now quickly see how to [Combine Abilities](./combine_abilities.md)
