# SQL Strategies

When [fetching records](./fetching_records.md) from the database, CanCanCan generates the SQL for you.

The generated SQL, although correct, might not be performant.

In the history of CanCanCan we had many issues with different versions of the generated SQL and we finally reached to the conclusion that there's no single solutions that fits all the needs.

That's why in the latest versions of CanCanCan, you are given the possibility to customize how the SQL is generated and choose from multiple options.

You can customize the SQL strategy globally with:

```ruby
# config/initializers/cancancan.rb

CanCan.accessible_by_strategy = :left_join # :subquery is the default
```

or on a single `accessible_by` call:

```ruby
Article.accessible_by(current_ability, strategy: :left_join) # :subquery is, again, the default
```

or on a group of queries:

```ruby
CanCan.with_accessible_by_strategy(:subquery) do
  Article.accessible_by(current_ability)
  # ...
end
```

Here is a complete list of the available strategies, explained by examples.

Given the following permissions:

```ruby
can :read, Article, mentions: { user: { name: u.name } }
```

## :left_join

Note that in the default strategy, we use the `DISTINCT` clause which might cause performance issues.

```sql
SELECT DISTINCT "articles".*
FROM "articles"
LEFT OUTER JOIN "mentions" ON "mentions"."article_id" = "articles"."id"
LEFT OUTER JOIN "users" ON "users"."id" = "mentions"."user_id"
WHERE "users"."name" = 'pippo'
```

## :subquery

By using the `:subquery` strategy, the `DISTINCT` clause can be removed.

```sql
SELECT "articles".*
FROM "articles"
WHERE "articles"."id" IN
  (SELECT "articles"."id"
   FROM "articles"
   LEFT OUTER JOIN "mentions" ON "mentions"."article_id" = "articles"."id"
   LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
   WHERE "users"."name" = 'pippo')
```

## :joined_alias_exists_subquery

The records are joined with an alias of their own table, and the conditions are checked in an `EXISTS`
subquery on the alias. This can be faster than `:subquery` on large tables.

```sql
SELECT "articles".*
FROM "articles"
JOIN "articles" AS "articles_alias" ON "articles_alias"."id" = "articles"."id"
WHERE (EXISTS (SELECT 1
  FROM "articles"
  LEFT OUTER JOIN "mentions" ON "mentions"."article_id" = "articles"."id"
  LEFT OUTER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
  WHERE "users"."name" = 'pippo' AND ("articles"."id" = "articles_alias"."id")
  LIMIT 1))
```

## :joined_alias_each_rule_as_exists_subquery

Like `:joined_alias_exists_subquery`, but with one `EXISTS` subquery per `can` definition, joined with `OR`, and
with inner joins instead of left outer joins when the conditions do not check for a missing association.

**WARNING**: this strategy ignores `cannot` definitions. Only use it when the permissions of the model are made of
`can` definitions.

```sql
SELECT "articles".*
FROM "articles"
JOIN "articles" AS "articles_alias" ON "articles_alias"."id" = "articles"."id"
WHERE (EXISTS (SELECT 1
  FROM "articles"
  INNER JOIN "mentions" ON "mentions"."article_id" = "articles"."id"
  INNER JOIN "users" ON "users"."id" = "legacy_mentions"."user_id"
  WHERE ("articles"."id" = "articles_alias"."id") AND "users"."name" = 'pippo'
  LIMIT 1))
```

## Custom strategies

If none of the built-in strategies fits your needs, you can write your own: subclass
`CanCan::ModelAdapters::Strategies::Base`, implement `execute!` and return the relation.
The class is accepted wherever a strategy symbol is: globally, in a block or on a single call.

```ruby
class InnerJoinStrategy < CanCan::ModelAdapters::Strategies::Base
  def execute!
    relation.joins(joins).distinct
  end
end

CanCan.accessible_by_strategy = InnerJoinStrategy
Article.accessible_by(current_ability, strategy: InnerJoinStrategy)
```

Inside `execute!` you have access to `relation` (the records filtered by the conditions of the rules),
`joins` (the associations referenced by the conditions), `where_conditions` (the conditions of the rules as an
Arel node, to pass to `where`) and `model_class`.
