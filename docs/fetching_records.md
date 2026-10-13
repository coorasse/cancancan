# Fetching records

One of the key features of CanCanCan, compared to other authorization libraries, is the possibility to retrieve all the objects that the user is authorized to access. The following:

```ruby
Article.accessible_by(current_ability)
```

will use the rules you already defined to ensure that the users retrieve only a list of articles that they can read.

This tool is very powerful and magic at the same time.

Given the following ability file:

```ruby
can :read, Article, published: true

return unless user.present?

can :read, Article, user: user

return unless user.admin?

can :manage, :all
```

you will not only be able to check if the user `can? :read, @article` on a single article, but also to limit the articles fetched from the database, to only the ones that they can read.

In an `index` action the following will just work:

```ruby
@articles = Article.accessible_by(current_ability)
```

`current_ability` is already made available by CanCanCan in your controller and the default action of `accessible_by` is `:index`, which is aliased by `:read`.

You can change the action by passing it as the second argument. Here we find only the records the user has permission to update.

```ruby
@articles = Article.accessible_by(current_ability, :update)
```

And this is just an ActiveRecord scope so other scopes and pagination can be chained onto it. It can also be
chained onto existing scopes: `current_user.articles.accessible_by(current_ability)` keeps the conditions of the
association.

## Under the hood

The call to accessible_by in the example above will generate the proper SQL to limit the records fetched.

This works also with multiple `can` definitions, which allows you to define complex permission logic and have it translated properly to SQL.

Given the definition:

```ruby
class Ability
  can :read, Article, public: true
  cannot :read, Article, self_managed: true
  can :read, Article, user: user
end
```

a call to `Article.accessible_by(current_ability)` generates the following SQL

```sql
SELECT *
FROM articles
WHERE (user_id = 1) OR ((self_managed = 'true') IS NOT TRUE AND (public = 'true'))
```

The conditions of the rules are built with Arel, the query builder of Active Record, so rules defined with hash
conditions, SQL fragments and [Active Record scopes](./define_abilities_with_blocks.md#block-conditions-with-activerecord-scopes)
can be combined freely.

The generation of the SQL query is a very complex task and probably the most powerful feature of CanCanCan.

Even if the default behaviour will suffice at the beginning, larger databases or more complex rules, might lead to very complex SQL queries. 
This might result in a slow fetching of records. This is why it is possible to use different strategies to generate the SQL.
You will see that in one of the last chapters: [SQL strategies](./sql_strategies.md)

## Blocks

We haven't spoken about block abilities yet, but the SQL generation will not be possible if you have even a single rule that is defined using just a block.
You can define SQL fragments in addition to block to fix that. But we'll see that in the [Define Abilities with Blocks](./define_abilities_with_blocks.md) chapter.
