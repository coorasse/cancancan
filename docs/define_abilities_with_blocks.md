# Define abilities with blocks

If your conditions are too complex to define in a [hash of conditions](./hash_of_conditions.md), you can use a block to define them in Ruby.

```ruby
can :update, Project do |project|
  project.priority < 3
end
```

Note that if you pass a block to a `can` or `cannot`, the block only executes if an instance of a class is passed to `can?` or `cannot?` calls.

If you define a `can` or `cannot` with a block and an object is not passed, the check will pass.

```ruby
can :update, Project do |project|
  false
end
```

```ruby
can? :update, Project # returns true!
```

Additional arguments passed to `can?` are passed to the block, again only when an instance is checked:

```ruby
can :create, Project do |project, remote_ip|
  remote_ip.start_with?("10.")
end

can? :create, @project, request.remote_ip # calls the block
can? :create, Project, request.remote_ip # does not call the block
```

To write the block with curly braces, put the arguments in parentheses. Without them, Ruby passes the block to `Project` instead of `can` and raises a `NoMethodError`:

```ruby
can(:update, Project) { |project| project.priority < 3 }
```

## Fetching Records

A block's conditions are only executable through Ruby. If you are [Fetching Records](./fetching_records.md) using `accessible_by` it will raise an exception.

To fetch records from the database you need to supply an SQL string representing the condition. The SQL will go in the `WHERE` clause:

```ruby
can :update, Project, ["priority < ?", 3] do |project|
  project.priority < 3
end
```

> If you are using `load_resource` and don't supply this SQL argument, the instance variable will not be set for the `index` action since they cannot be translated to a database query.

## Block Conditions with ActiveRecord Scopes

It's also possible to pass a scope instead of an SQL string when using a block in an ability. The block is **always required**, as it is called when checking discrete actions like `can` and `authorize`. See also [Defining Abilities: Best Practices](./define_abilities_best_practices.md).

```ruby
can :read, Article, Article.published do |article|
  article.published_at <= Time.now
end
```

This is really useful if you have complex conditions which require `joins`.

The scope can be combined with other `can` and `cannot` definitions for the same action and model, like hash
conditions: the records are the ones returned by any of the `can` scopes or conditions, minus the ones returned by
the `cannot` scopes or conditions. So, if you don't want someone to read discontinued products, the scope of the
`cannot` definition fetches the discontinued ones:

```ruby
can :read, Product
cannot :read, Product, Product.where(discontinued: true) do |product|
  product.discontinued?
end
```

Until version 4.0 the scope of a `cannot` definition selected the records that remained accessible, so it had to be
inverted. When upgrading, every `cannot` definition with a scope is reported once with a warning. Review them and
disable the warning:

```ruby
# config/initializers/cancan.rb
CanCan.warn_on_cannot_rules_with_scope = false
```

A couple of caveats:

- A scope with `joins`, `limit` or other clauses that select its records is used as a subquery on the primary
  key, as in `id IN (SELECT id FROM ...)`, so that these clauses apply to that definition only. MySQL does not
  support a `LIMIT` in such a subquery, so a scope with a limit cannot be used as a condition there.
- Only the records of the scope matter: its `includes`, `order` and `select` do not apply to the
  `accessible_by` query.

It is only recommended to use scopes if a situation is too complex for a hash condition.
