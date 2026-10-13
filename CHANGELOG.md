## 4.0.0 (unreleased)

### Breaking changes

#### Ruby 3.2+ and Rails 8.0+

* Drop support for Ruby < 3.2 and Rails < 8.0. The `ActiveRecord4Adapter` and `ActiveRecord5Adapter` classes are merged into `ActiveRecordAdapter`, and `:subquery` is always the default `accessible_by_strategy`. ([@coorasse][])

#### Active Record scopes can be combined with other rules

* [#717](https://github.com/CanCanCommunity/cancancan/pull/717): The conditions of `accessible_by` are built with Arel instead of SQL strings, so a rule with an Active Record scope can be combined with other rules. ([@mamhoff][], [@coorasse][])

  ```ruby
  can :read, Article, published: true
  can :read, Article, Article.where(author: user)

  # 3.x: raises "Unable to merge an Active Record scope with other conditions"
  # 4.0: returns the published articles and the articles of the user
  Article.accessible_by(ability)
  ```

  A `cannot` rule with a scope now excludes the records of the scope, like a `cannot` rule with hash conditions. In 3.x the scope was used as the records that remain accessible, so the scope had to select the opposite of what the rule says. Take a user who cannot read discontinued products:

  ```ruby
  # 3.x: the scope selects the products the user can read, so it must be inverted
  can :read, Product
  cannot :read, Product, Product.where(discontinued: false)

  # 4.0: the scope selects the products the user cannot read, like the hash condition `discontinued: true`
  can :read, Product
  cannot :read, Product, Product.where(discontinued: true)
  ```

  If you keep a 3.x rule as it is, `accessible_by` returns the opposite records: only the discontinued products. To help with the upgrade, every `cannot` rule with a scope is reported once with a warning, until the rules are reviewed and the warning is disabled with `CanCan.warn_on_cannot_rules_with_scope = false`.

  Only the records of a scope matter: a scope with `joins`, `limit`, `group` or other clauses that select its records is used as a subquery on the primary key, and its `includes`, `order` and `select` no longer apply to the query.

  ```ruby
  can :read, Article, Article.includes(:comments).joins(:category).where(categories: { visible: true }).order(:title)
  can :read, Article, author: user

  # 4.0: the inner join applies to the first rule only, the order and the eager loading are dropped
  # SELECT articles.* FROM articles
  # WHERE (articles.id IN (SELECT articles.id FROM articles INNER JOIN categories ... WHERE categories.visible = TRUE))
  #    OR (articles.author_id = 1)
  Article.accessible_by(ability)
  ```

  Also:

  - A scope with conditions on a joined table, or with a join or a limit, is no longer treated as a rule without conditions, which silently discarded the rules defined before it.
  - `ActiveRecordAdapter#conditions`, which is not public API, returns the SQL of a single scope rule instead of the scope, and `'1=0'` instead of `'t'='f'` when no record is accessible.
  - A custom strategy receives `where_conditions` as an Arel node, to pass to `where`, instead of an array of conditions.

#### The RSpec matcher cannot be negated with several actions

* [#796](https://github.com/CanCanCommunity/cancancan/pull/796): The RSpec matcher raises `CanCan::ImplementationRemoved` when negated with several actions. It passed as soon as one action was forbidden, which was often misread as all actions being forbidden. Write one expectation per action instead. ([@coorasse][])

  ```ruby
  # 3.x: passes as soon as one of the actions is forbidden
  expect(ability).not_to be_able_to(%i[read update], article)

  # 4.0: raises CanCan::ImplementationRemoved. Write instead:
  expect(ability).not_to be_able_to(:read, article)
  expect(ability).not_to be_able_to(:update, article)
  ```

#### `permitted_attributes` excludes the primary key

* [#903](https://github.com/CanCanCommunity/cancancan/pull/903): `permitted_attributes` no longer includes the primary key when a rule has no attributes. It was documented to exclude it, but a bug kept `id` in the returned array. If your strong parameters rely on `permitted_attributes` to permit the primary key, add it explicitly. ([@coorasse][])

  ```ruby
  can :update, Project

  # 3.x: [:id, :name, :description, ...]
  # 4.0: [:name, :description, ...]
  current_ability.permitted_attributes(:update, @project)

  # Permit the primary key explicitly when you need it
  params.require(:project).permit(:id, *current_ability.permitted_attributes(:update, @project))
  ```

#### `:only` and `:except` of the skip helpers are combined with AND

* [#808](https://github.com/CanCanCommunity/cancancan/pull/808): `skip_load_resource`, `skip_authorize_resource` and `skip_load_and_authorize_resource` combine the `:only` and `:except` options with AND, like `before_action` does. They were combined with OR. If you passed both options and relied on that, pass only `:except` to keep the old behavior. ([@coorasse][])

  ```ruby
  # 3.x: skips every action but `show`
  # 4.0: skips no action, since no action is both `index` and not `show`
  skip_authorize_resource only: :index, except: :show

  # Keep the old behavior
  skip_authorize_resource except: :show
  ```

#### `can?` matches the ranges in an array of values

* [#924](https://github.com/CanCanCommunity/cancancan/pull/924): `can?` matches a value against the ranges in an array of values, as `accessible_by` already did. The ranges were compared with `==` and never matched, so `can?` denied records that `accessible_by` returned. When the attribute is itself a range, it now matches a range of the array that covers it. ([@coorasse][])

  ```ruby
  can :read, Product, stock: [1.., nil]

  # 3.x: false, although Product.accessible_by(ability) returns the product
  # 4.0: true
  can? :read, Product.new(stock: 5)
  ```

#### A resource named differently than the controller is a parent only when it is nested

* [#925](https://github.com/CanCanCommunity/cancancan/pull/925): A resource whose name does not match the controller is a parent resource only when another resource of the controller is loaded `through` it, or when the request has a parameter named after it, such as `book_id`. Every resource named differently than the controller was considered a parent, so it was loaded with `params[:book_id]` and authorized with `:show` instead of the action of the controller: an `update` passed with a `:read` permission. ([@enmanuelm19][], [@coorasse][])

  ```ruby
  class BookServicesController < ApplicationController
    load_and_authorize_resource :book
  end

  # PATCH /book_services/1
  # 3.x: authorizes :show on the book, so `can :read, Book` is enough
  # 4.0: authorizes :update on the book loaded with params[:id]
  ```

  A parent resource that is not loaded `through` by another resource and is not in the parameters, such as one found with `id_param`, needs `parent: true`.

#### The conditions of the ability pre-fill a new resource only when they restrict it

* [#926](https://github.com/CanCanCommunity/cancancan/pull/926): `load_resource` builds a new resource on `new` and `create` with the values of the hash conditions of the `can` rules, through `attributes_for`. These values are no longer assigned when a `can` rule without conditions allows the action, since any value is allowed. When several rules set the same attribute, the most recent rule wins instead of the oldest, and the rules defined before a `cannot` rule without conditions are ignored. ([@coorasse][])

  ```ruby
  can :create, Boat if user.admin?
  can :create, Boat, slow: true

  # 3.x: { slow: true }, so the boats built for an admin are slow
  # 4.0: {}
  attributes_for(:create, Boat)

  can :new, Foo, bar: 22
  can :new, Foo, bar: 33

  # 3.x: { bar: 22 }
  # 4.0: { bar: 33 }
  attributes_for(:new, Foo)
  ```

### Other changes

#### `accessible_by` returns only the records that `can?` allows

* [#932](https://github.com/CanCanCommunity/cancancan/pull/932): Keep the conditions of every `has_many :through` association that goes through the same table. ([@coorasse][])

  ```ruby
  class Post < ApplicationRecord
    has_many :taggings
    has_many :tags, through: :taggings
    has_many :topics, through: :taggings
  end

  can :read, Post, tags: { name: 'ruby' }, topics: { name: 'rails' }

  # 3.x: ignores the condition on the tags, so it returns posts with any tag
  # 4.0: returns only the posts tagged 'ruby' with the topic 'rails'
  Post.accessible_by(ability)
  ```

* [#932](https://github.com/CanCanCommunity/cancancan/pull/932): Exclude the subclasses of a class denied by a `cannot` rule, with single table inheritance. ([@coorasse][])

  ```ruby
  class Animal < ApplicationRecord; end
  class Dog < Animal; end
  class Puppy < Dog; end

  can :read, Animal
  cannot :read, Dog

  # 3.x: returns the puppies, although can?(:read, puppy) is false
  # 4.0: returns neither the dogs nor the puppies
  Animal.accessible_by(ability)
  ```

* [#932](https://github.com/CanCanCommunity/cancancan/pull/932): Filter by type a rule on a single table inheritance subclass and on another class. ([@coorasse][])

  ```ruby
  class Car < Vehicle; end
  class Airplane < Vehicle; end

  can :read, [Car, Brand]

  # 3.x: returns every vehicle, airplanes included
  # 4.0: returns only the cars
  Vehicle.accessible_by(ability)
  ```

* [#932](https://github.com/CanCanCommunity/cancancan/pull/932): Apply the `cannot` rules and the order of the rules with the `:joined_alias_each_rule_as_exists_subquery` strategy, as the other strategies do. ([@coorasse][])

  ```ruby
  CanCan.accessible_by_strategy = :joined_alias_each_rule_as_exists_subquery

  can :read, Post, comments: { spam: false }
  cannot :read, Post, secret: true

  # 3.x: returns the secret posts too
  # 4.0: excludes the secret posts
  Post.accessible_by(ability)
  ```

* [#932](https://github.com/CanCanCommunity/cancancan/pull/932): Exclude a record when any of its `has_many` records matches a `cannot` rule, as `can?` does. Such a rule is now checked in a subquery on the primary key, `NOT (posts.id IN (SELECT ...))`. The SQL of the other `cannot` rules does not change. ([@coorasse][])

  ```ruby
  can :read, Post
  cannot :read, Post, comments: { spam: true }

  # A post with one spam comment and one other comment
  # 3.x: returned, because the other comment does not match the cannot rule
  # 4.0: excluded
  Post.accessible_by(ability)
  ```

* [#918](https://github.com/CanCanCommunity/cancancan/pull/918): Support models with a composite primary key. The subqueries of the `:subquery`, `:joined_alias_exists_subquery` and `:joined_alias_each_rule_as_exists_subquery` strategies, and of the rules with a scope, compare every column of the primary key. ([@coorasse][])

  ```ruby
  class Membership < ApplicationRecord
    self.primary_key = %i[team_id user_id]
  end

  # 4.0: the subqueries compare both team_id and user_id
  Membership.accessible_by(ability)
  ```

#### `can?` and action aliases

* [#932](https://github.com/CanCanCommunity/cancancan/pull/932): Raise an error when an action is aliased to `:manage` or to itself. ([@coorasse][])

  ```ruby
  # 3.x: grants every action
  # 4.0: raises CanCan::Error
  alias_action :edit, to: :manage

  # 3.x: loops forever
  # 4.0: raises CanCan::Error
  alias_action :read, to: :read
  ```

* [#915](https://github.com/CanCanCommunity/cancancan/pull/915): Check the conditions on an association that is not loaded with one query, instead of loading all of its records. An association that is already loaded is still checked in memory, without queries. ([@oboxodo][], [@coorasse][])

  ```ruby
  can :read, Author, books: { user: user }

  # 3.x: loads every book of the author
  # 4.0: checks the books with one query
  can? :read, author
  ```

  **WARNING**: the keys below such an association must be columns or associations, as `accessible_by` requires, and NULL columns of the records below it are matched as in `accessible_by`.

* [#887](https://github.com/CanCanCommunity/cancancan/pull/887): Speed up `can?` by 20% to 100% on CRuby, depending on the check. The subjects are checked with a loop instead of a lazy enumerator, the expanded actions of a rule are memoized, the possibly relevant rules are fetched with `values_at`, and class names are compared with `Module#name` instead of `to_s`. The memoized actions are forgotten when `alias_action`, `clear_aliased_actions` or `merge` change the aliases, so an alias defined after a `can?` call is now applied. ([@tr4b4nt][], [@coorasse][])

  ```ruby
  can :read, Article
  can? :read, article

  alias_action :preview, to: :read

  # 4.0: true, the alias is applied although it was defined after the first check
  can? :preview, article
  ```

#### Controllers

* [#808](https://github.com/CanCanCommunity/cancancan/pull/808): Add the `:if` and `:unless` options to `skip_load_resource`, `skip_authorize_resource` and `skip_load_and_authorize_resource`, as `check_authorization` already supports. ([@ammarghaus][])

  ```ruby
  skip_authorize_resource if: :public_page?
  skip_load_resource unless: -> { params[:id].present? }
  ```

* [#921](https://github.com/CanCanCommunity/cancancan/pull/921): Keep the parent of a nested resource built on `new` and `create`. The conditions of the ability no longer overwrite the foreign key set by the `through` association. ([@coorasse][])

  ```ruby
  class BooksController < ApplicationController
    load_and_authorize_resource :author
    load_and_authorize_resource :book, through: :author
  end

  can :create, Book, author_id: user.id

  # POST /authors/2/books by the user 1
  # 3.x: builds the book for the author 1, so authorization passes
  # 4.0: builds the book for the author 2, so authorization is denied
  ```

## 3.7.0

* Merge the `ControllerResourceLoader`, `ControllerResourceBuilder`, `ControllerResourceFinder`, `ControllerResourceNameFinder` and `ControllerResourceSanitizer` modules into `CanCan::ControllerResource`, and call the params method of the controller only once per request: it was called once more for every attribute set by the conditions of the ability. **WARNING**: the five modules no longer exist; override their methods in a subclass of `CanCan::ControllerResource` instead. ([@coorasse][])
* Expand the actions again after `alias_action`, `clear_aliased_actions` and `merge`: `can?` kept using the aliases expanded by a previous check, so `clear_aliased_actions` did not remove `can :read` from `can?(:index, Model)`. ([@coorasse][])
* Raise an error when an action is aliased to `:manage`, which granted every action, or to itself, which looped forever. ([@coorasse][])
* Do not include the primary key in `permitted_attributes` for a rule without attributes, remove every attribute with a `cannot` rule without attributes, including those that are not columns, and accept a hash subject instead of raising a `TypeError`. **WARNING**: `permitted_attributes` no longer returns `:id`, and with a composite primary key none of its columns are returned. ([@coorasse][])
* Convert a String resource name to a symbol in `load_and_authorize_resource` and the `skip_*` methods: `load_and_authorize_resource 'article'` treated the resource as a parent and authorized `:show` on the class instead of the action on the record. ([@coorasse][])
* [#927](https://github.com/CanCanCommunity/cancancan/pull/927): Look up the unauthorized message of a String action through its aliases: `authorize!('index', post)` did not use the message defined for `read`. ([@coorasse][])
* [#913](https://github.com/CanCanCommunity/cancancan/pull/913): Match a symbol in a condition with the string that has the same name in `can?`, as `accessible_by` already did: `cannot :read, Post, state: :draft` on a string column no longer allows `can?(:read, draft)`. **WARNING**: a `can` rule with a symbol now also allows records whose string attribute has the same name. ([@bruno-costanzo][])
* [#905](https://github.com/CanCanCommunity/cancancan/pull/905): Match String actions like Symbol actions: `can?('destroy', user)` ignored `cannot :destroy, User` when `can :manage` was defined, and `skip_authorize_resource except: 'destroy'` also skipped the authorization of `destroy`. **WARNING**: a String action now goes through the aliases like a Symbol action, so `can?('show', order)` and `authorize!(action_name, order)` are allowed by `can :read, Order` and may grant access that 3.6 denied. A rule defined with a String action now matches the same Symbol action, `permissions` returns symbols, and a block rule without a subject receives the action as a symbol. ([@bruno-costanzo][])
* [#848](https://github.com/CanCanCommunity/cancancan/issues/848): Do not deny `can?(:index, parent => Model)` because of a `cannot` rule with conditions on the model, as `can?(:index, Model)` already did: `load_and_authorize_resource` failed on the `index` of a nested resource. ([@coorasse][])
* [#861](https://github.com/CanCanCommunity/cancancan/issues/861), [#846](https://github.com/CanCanCommunity/cancancan/issues/846), [#690](https://github.com/CanCanCommunity/cancancan/issues/690): Give the conditions of `accessible_by` the table aliases that Active Record gives to the joined associations, and build them with the model of each table. A rule with a `has_many :through` association, or with an association without conditions, used the alias of another table: the query failed or returned the wrong records. On an aliased table, a model was not converted to its foreign key and the values were not cast with the attribute types of the model. ([@coorasse][])
* [#911](https://github.com/CanCanCommunity/cancancan/pull/911): Load the resource when the id is only whitespace: a request like `/books/%20` ran the action with a `nil` resource, authorized only against the class, instead of raising `ActiveRecord::RecordNotFound`. ([@bruno-costanzo][])
* [#833](https://github.com/CanCanCommunity/cancancan/pull/833): Match `nil` in an array of enum values in `can?`, as `accessible_by` already did: `can :read, Post, status: [nil, :published]` now allows a post without a status. ([@jtagle2][], [@coorasse][])
* [#910](https://github.com/CanCanCommunity/cancancan/pull/910): Accept a subclass of `CanCan::ModelAdapters::Strategies::Base` as `accessible_by_strategy`, so the SQL generated by `accessible_by` can be customized with your own strategy. ([@cb341][], [@coorasse][])
* [#909](https://github.com/CanCanCommunity/cancancan/pull/909): Make `can?` and `accessible_by` consistent for `cannot` rules and single table inheritance: a `cannot` rule on a subclass keeps its precedence in `accessible_by`, records with NULL in a column of a `cannot` condition are no longer excluded, rules on subclasses of subclasses reach the base class, and a class check passes when the class or any of its subclasses is allowed. **WARNING**: `accessible_by` returns more records when a `cannot` rule has conditions on a nullable column, and `can?` on an STI base class no longer fails because a subclass is forbidden. ([@coorasse][], [@0llirocks][], [@kevinluo201][])
* [#880](https://github.com/CanCanCommunity/cancancan/pull/880): Fix `accessible_by` with rules on STI subclasses: a rule on a subclass without conditions no longer discards the rules defined before it, and rules with the same conditions on different subjects are no longer compressed into one. ([@takayamaki][], [@sjoulbak][])
* [#890](https://github.com/CanCanCommunity/cancancan/pull/890): Support an Active Record relation as the value of a condition in `can?`: the selected column, or the primary key, is checked with a query, as `accessible_by` already did. ([@olistik][])
* [#853](https://github.com/CanCanCommunity/cancancan/pull/853): Run the test suite on TruffleRuby. ([@andrykonchin][])
* [#908](https://github.com/CanCanCommunity/cancancan/pull/908): Join consecutive `can` rules in a flat chain of ORs in the SQL conditions, so that many rules on the same model no longer overflow the parser of SQLite. ([@coorasse][])
* [#907](https://github.com/CanCanCommunity/cancancan/pull/907): Make `with_accessible_by_strategy` thread safe: the strategy chosen in the block no longer leaks into concurrent requests. ([@NikosVlagoidis][], [@coorasse][])
* [#906](https://github.com/CanCanCommunity/cancancan/pull/906): Keep the conditions of an association when a rule is a scope: `group.posts.accessible_by(ability)` returned the posts of every group matched by the scope. **WARNING**: `accessible_by` called on an association now returns fewer records when the scope of a rule constrains the same column as the association. Only the conditions dropped by `merge` are applied again, so a condition on a subquery like `where(category: Category.where(...))` is not turned into `IS NULL`, and the conditions of a default scope removed by `unscope` in the rule stay removed. ([@coorasse][])
* [#694](https://github.com/CanCanCommunity/cancancan/pull/694): Document that `cannot` supports the `:all` subject. ([@jaredbeck][])
* [#852](https://github.com/CanCanCommunity/cancancan/pull/852): Add `changelog_uri` to the gemspec, so rubygems.org links to the changelog. ([@mark-young-atg][])
* [#842](https://github.com/CanCanCommunity/cancancan/pull/842): Add `disallowed_attributes` to retrieve the attributes forbidden by `cannot` rules. ([@mswiszcz][])
* [#904](https://github.com/CanCanCommunity/cancancan/pull/904): Assign the parent of a singleton resource through the inverse of the association when the resource has no setter named after the `through` option. ([@coorasse][])
* [#878](https://github.com/CanCanCommunity/cancancan/pull/878): Support `through_association` together with `singleton` when loading a resource. ([@cgunther][])
* [#786](https://github.com/CanCanCommunity/cancancan/pull/786): Fix the table aliases generated by `accessible_by` when the same association is joined more than twice: the WHERE clause referenced an alias that was never joined. ([@daveallie][])
* [#902](https://github.com/CanCanCommunity/cancancan/pull/902): Do not change the rules of the ability in `accessible_by`: a rule shared by several models kept the conditions normalized for the first queried model. ([@bruno-costanzo][])
* [#901](https://github.com/CanCanCommunity/cancancan/pull/901): Keep the scope of a `has_many :through` association in `accessible_by`: the association was rewritten into its through and source associations and its scope was dropped, so `accessible_by` returned records that `can?` denies. **WARNING**: `accessible_by` returns fewer records for a rule on a `has_many :through` association with a scope. ([@bruno-costanzo][])
* Remove the VitePress documentation website: the documentation lives in the `docs` folder as plain Markdown. ([@coorasse][])

## 3.6.2

* [#898](https://github.com/CanCanCommunity/cancancan/pull/898): Do not share `cancan_skipper` between controller subclasses: `skip_authorize_resource` and `skip_load_resource` in a subclass no longer apply to the superclass or sibling controllers. ([@bruno-costanzo][])
* [#894](https://github.com/CanCanCommunity/cancancan/pull/894): Use `lease_connection` instead of the deprecated `connection` on Rails 7.2+. ([@benaitcheson][])

## 3.6.1

* Fix the 3.6.0 release, which was published without [#839](https://github.com/CanCanCommunity/cancancan/pull/839). ([@coorasse][])

## 3.6.0

* [#849](https://github.com/CanCanCommunity/cancancan/pull/849): Update tests matrix. ([@coorasse][])
* [#843](https://github.com/CanCanCommunity/cancancan/pull/843): Compress duplicate rules. ([@MrChoclate][])
* [#841](https://github.com/CanCanCommunity/cancancan/pull/841): New https://cancancan.dev website. ([@pandermatt][])
* [#839](https://github.com/CanCanCommunity/cancancan/pull/839): Switch from database column detection to Rails attributes detection. ([@kalsan][])

## 3.5.0

* [#653](https://github.com/CanCanCommunity/cancancan/pull/653): Add support for using an nil relation as a condition. **WARNING**: a condition on a `has_many` association where all values are `nil` now also matches the records without associated records, as `accessible_by` already did. ([@ghiculescu][])
* [#702](https://github.com/CanCanCommunity/cancancan/pull/702): Support scopes of STI classes as ability conditions. ([@honigc][])
* [#798](https://github.com/CanCanCommunity/cancancan/pull/798): Allow disabling of rules compressor via `CanCan.rules_compressor_enabled = false`. ([@coorasse][])
* [#814](https://github.com/CanCanCommunity/cancancan/pull/814): Fix issue with polymorphic associations. ([@WriterZephos][])

## 3.4.0

* [#691](https://github.com/CanCanCommunity/cancancan/pull/691): Add two new subquery strategies: `joined_alias_exists_subquery`, `joined_alias_each_rule_as_exists_subquery`. ([@kaspernj][])
* [#767](https://github.com/CanCanCommunity/cancancan/pull/767): Improve ability checks with nested resources (hash checks)vim. ([@Juleffel][])
* [#772](https://github.com/CanCanCommunity/cancancan/pull/772): Support non-hash conditions in ability definitions. ([@Juleffel][])
* [#773](https://github.com/CanCanCommunity/cancancan/pull/773): Drop support for ruby 2.4 and 2.5. ([@coorasse][])
* [#778](https://github.com/CanCanCommunity/cancancan/pull/778): Drop support for ActiveRecord 4. ([@coorasse][])

## 3.3.0

* [#675](https://github.com/CanCanCommunity/cancancan/pull/675): Support modifying the `accessible_by` querying strategy on a per-query basis. ([@ghiculescu][])
* [#714](https://github.com/CanCanCommunity/cancancan/pull/714): Don't hold unnecessary references to subjects in @rules_index. ([@mtoneil][])

## 3.2.2

* Added funding metadata to Gemspec. ([@coorasse][])

## 3.2.1

* [#674](https://github.com/CanCanCommunity/cancancan/pull/674): Fix accidental dependency on ActiveRecord in 3.2.0. ([@ghiculescu][])

## 3.2.0

* [#649](https://github.com/CanCanCommunity/cancancan/pull/649): Add support for Single Table Inheritance. ([@Liberatys][])
* [#640](https://github.com/CanCanCommunity/cancancan/pull/640): Simplify implementation of new model adapters. ([@ghiculescu][])
* [#650](https://github.com/CanCanCommunity/cancancan/pull/650): Support associations in rules. ([@Liberatys][])
* [#657](https://github.com/CanCanCommunity/cancancan/pull/657): Support for Rails 6.1. ([@ghiculescu][])
* [#655](https://github.com/CanCanCommunity/cancancan/pull/655): Add option for `accessible_by` querying strategy. ([@ghiculescu][])

## 3.1.0

* [#605](https://github.com/CanCanCommunity/cancancan/pull/605): Generate inner queries instead of join+distinct. ([@fsateler][])
* [#608](https://github.com/CanCanCommunity/cancancan/pull/608): Spec for json column regression. ([@aleksejleonov][])
* [#571](https://github.com/CanCanCommunity/cancancan/pull/571): Allows to check ability even the object implements `#to_a`. ([@mtsmfm][])
* [#612](https://github.com/CanCanCommunity/cancancan/pull/612): Suppress keyword arguments warning for Ruby 2.7.0. ([@koic][])
* [#569](https://github.com/CanCanCommunity/cancancan/pull/569): Fix accessible_by fires query for rules using association as condition. ([@albb0920][])
* [#594](https://github.com/CanCanCommunity/cancancan/pull/594): Support translation of action name. ([@ayumu838][])

## 3.0.2

* [#590](https://github.com/CanCanCommunity/cancancan/pull/590): Fix Rule#inspect when rule is created through a SQL array. ([@frostblooded][])
* [#592](https://github.com/CanCanCommunity/cancancan/pull/592): Prevent normalization of through polymorphic associations.([@eloyesp][])

## 3.0.1

* [#583](https://github.com/CanCanCommunity/cancancan/pull/583): Fix regression when using a method reference block. ([@coorasse][])

## 3.0.0

Please read the [guide on migrating from CanCanCan 2.x to 3.0](https://github.com/CanCanCommunity/cancancan/blob/develop/docs/migrating.md#from-2x-to-3x)

* [#560](https://github.com/CanCanCommunity/cancancan/pull/560): Add support for Rails 6.0. ([@coorasse][])
* [#489](https://github.com/CanCanCommunity/cancancan/pull/489): Drop support for actions without a subject. ([@andrew-aladev][])
* [#474](https://github.com/CanCanCommunity/cancancan/pull/474): Allow to add attribute-level rules. ([@phaedryx][])
* [#512](https://github.com/CanCanCommunity/cancancan/pull/512): Removed automatic eager loading of associations for ActiveRecord >= 5.0. ([@kaspernj][])
* [#575](https://github.com/CanCanCommunity/cancancan/pull/575): Use the rules compressor when generating joins in accessible_by. ([@coorasse][])

* [#444](https://github.com/CanCanCommunity/cancancan/issues/444): Allow to use symbols when defining conditions over enums. ([@s-mage][])
* [#538](https://github.com/CanCanCommunity/cancancan/issues/538): Merge alias actions when merging abilities. ([@Jcambass][])
* [#462](https://github.com/CanCanCommunity/cancancan/issues/462): Add support to translate the model name in messages. ([@nyamadori][])
* [#567](https://github.com/CanCanCommunity/cancancan/issues/567): Extensively run tests on different databases (sqlite and postgres). ([@coorasse][])
* [#566](https://github.com/CanCanCommunity/cancancan/issues/566): Avoid queries on session dumps (speed up error pages). ([@coorasse][])
* [#568](https://github.com/CanCanCommunity/cancancan/issues/568): Automatically freeze strings in all files. ([@coorasse][])
* [#577](https://github.com/CanCanCommunity/cancancan/pull/577): Normalise rules traversing associations to reduce the number of joins. ([@coorasse][])

## 2.3.0 (Sep 16th, 2018)

* [#528](https://github.com/CanCanCommunity/cancancan/issues/528): Compress irrelevant rules before generating a query to optimize performances. ([@coorasse][])
* [#529](https://github.com/CanCanCommunity/cancancan/issues/529): Remove ruby 2.2 from Travis and add ruby 2.5.1. ([@coorasse][])
* [#530](https://github.com/CanCanCommunity/cancancan/issues/530): Predict associations names to support multiple references to the same table. ([@coorasse][])
* [#530](https://github.com/CanCanCommunity/cancancan/issues/530): Raise a specific exception when using a wrong association name in rules definition. ([@coorasse][])

## 2.2.0 (Apr 13th, 2018)

* [#482](https://github.com/CanCanCommunity/cancancan/issues/482): Include conditions passed to authorize! in AccessDenied exception. ([@kraflab][])
* Removed support for dynamic finders. ([@coorasse][])
* [#479](https://github.com/CanCanCommunity/cancancan/issues/479): Support Rails 5.2. ([@lizzyaustad][])
* Use ActiveSupport standard loader. ([@BookOfGreg][])

## 2.1.4 (Apr 09th, 2018)

* Inject cancancan in ActionController::API and ActionController::Base when they are both defined. ([@arturoherrero][])

## 2.1.3 (Jan 16th, 2018)

* Fix compatibility with Rails 5 API. ([@Eric-Guo][])

## 2.1.2 (Nov 22th, 2017)

* Various bugfixes on version 2.1.0. ([@coorasse][])

## 2.1.0 (Nov 10th, 2017)

* Adds support for Rails Api applications. ([@ajgon][])
* Controller subclasses inherit skip_load_resource from superclass. ([@jpmckinney][])
* Fix instance variable not initialized warnings. ([@sethcharles][])
* Fix build_resource when model name is Action. ([@anilmaurya][])
* Smaller performance improvements. ([@DNNX][])
* Fix i18n lookup for unauthorized message. ([@clemens][])

## 2.0.0 (May 18th, 2017)

* Drop support for Rails < 4.2. ([@oliverklee][])
* Drop support for ruby < 2.2. ([@coorasse][])
* Drop support for InheritedResource. ([@coorasse][])
* Drop support for Sequel. ([@coorasse][])
* Drop support for Mongoid. ([@coorasse][])
* Add ability to rspec matcher to take array of abilities. ([@gingray][])
* [#204](https://github.com/CanCanCommunity/cancancan/pull/204): Increase Performance. ([@timraymond][])
* Removed controller methods: skip_authorization, unauthorized!. ([@coorasse][])
* Removed options: nested, name, resource. ([@coorasse][])

## 1.17.0 (March 26th, 2017)

* Improve performance for the Mongoid Adapter.


## 1.16.0 (February 2nd, 2017)

* Introduce rubocop and fixes most of the issues ([@coorasse][]).

## 1.15.0 (June 13th, 2016)

* Add support for Rails 5 (craig1410).

## 1.14.0 (May 14th, 2016)

* Use cover for ranges.
* Add support for rails 4 enum's (markpmitchell).

## 1.13.1 (Oct 8th, 2015)

* Fix #merge with empty Ability (jhawthorn).

## 1.13.0 (Oct 7th, 2015)

* Significantly improve rule lookup time (amarshall).
* Removed deprecation warnings for RSpec 3.2 (NekoNova).
* Drop support for REE and Ruby 1.x and so Rails 2 (Richard Wilson).

## 1.12.0 (June 28th, 2015)

* Add a permissions method to Ability (devaroop).

## 1.11.0 (June 15th, 2015)

* Complete cancancan#115 - Specify authorization action for parent resources. (phallguy).

## 1.10.1 (January 13th, 2015)

* Fix cancancan#168 - A bug with ActiveRecord 4.2 support causing ProtocolViolation due to named parameters not being passed in.


## 1.10.0 (January 7th, 2015)

* Fix i18n issue for Ruby < 1.9.3 ([@bryanrite][]).

* Fix cancancan#149 - Fix an issue loading namespaced models (darthjee).

* Fix cancancan#160 - Support for Rails 4.2 (marshall-lee).

* Fix cancancan#153 - More useful output in ability spec matchers (jondkinney).


## 1.9.2 (August 8th, 2014)

* Fix cancancan#77, 78 - Fix an issue with associations for namespaced models (jjp).


## 1.9.1 (July 21st, 2014)

* Fix cancancan#101 - Fixes an issue where overjealous use of references would cause issues with scopes when loading associations ([@bryanrite][]).


## 1.9.0 (July 20th, 2014)

* Fix cancancan#59 - Parameters are automatically detected and sanitized for all actions, not just create and update ([@bryanrite][]).

* Fix cancancan#97, 72, 40, 39, 26 - Support Active Record 4 properly with references on nested permissions (scpike, tdg5, Crystark).


## 1.8.4 (June 24th, 2014)

* Fix cancancan#86 - Fixes previous RSpec 3 update as there was a bug in the fix for RSpec 2.99 ([@bryanrite][]).


## 1.8.3 (June 24th, 2014)

* Fix cancancan#85 - Remove deprecation notices for RSpec 3 and continue backwards compatibility (andypike, bryanrite, porteta).


## 1.8.2 (June 5th, 2014)

* Fix cancancan#75 - More specific hash-like object check. ([@bryanrite][]).


## 1.8.1 (May 27th, 2014)

* Fix cancancan#67 - Sequel tests are run properly for JRuby. ([@bryanrite][]).

* Fix cancancan#68 - Checks for hash-like objects in subject better. ([@bryanrite][]).


## 1.8.0 (May 8th, 2014)

* Feature cancan#884 - Add a Sequel model adapter (szetobo).

* Feature cancancan#3 - Permit "can?" check multiple subjects (cefigueiredo).

* Feature cancancan#29 - Add ability to use a String that will get instance_eval'd or a Proc that will get called as the parameter method option for strong_parameter sanitization (svoop).

* Feature cancancan#48 - Define a CanCanCan module. Even though it is not used, it is standard practice to define the module, and helpful for determining between CanCanCan and CanCan for external libraries.


## 1.7.1 (March 19th, 2014)

* Fix ryanb/cancan#992 - Remove Rails 4 deprecations for scoped (thejchap & hitendrasingh).

* Fix cancancan#16 - RSpec expectations are not explicitly required in RSpec > 2.13 (justinaiken & bryanrite).


## 1.7.0 (February 19th, 2014)

* Feature #988 Adds support for strong_parameters ([@bryanrite][]).

* Fix #726 - Allow multiple abilities with associations (elabs-dev).

* Fix #864 - Fix id_param in shallow routes (francocatena).

* Fix #871 - Fixes nested ability conditions (ricec).

* Fix #935 - Reduce unnecessary object allocations (grosser).

* Fix #966 - Fixes a variable name collision in nested conditions (knoopx).

* Fix #971 - Does not execute "empty?" scope when checking class rule (matt-glover).

* Fix #974 - Avoid unnecessary sql execution (inkstak).


## 1.6.10 (May 7, 2013)

* Fix matches_conditons_hash for string values on 1.8 ([@rrosen][]).

* Work around SQL injection vulnerability in older Rails versions ([@steerio][]) - issue #800.

* Add support for nested join conditions ([@yuszuv][]) - issue #806.

* Fix load_resource "find_by" in mongoid resources ([@albertobajo][]) - issue #705.

* Fix namespace split behavior ([@xinuc][]) - issue #668.


## 1.6.9 (February 4, 2013)

* Fix inserting AND (NULL) to end of SQL queries (jonsgreen) - issue #687.

* Fix merge_joins for nested association hashes (DavidMikeSimon) - issues #655, #560.

* Raise error on recursive alias_action (fl00r) - issue #660.

* Fix namespace controllers not loading params (andhapp) - issues #670, #664.


## 1.6.8 (June 25, 2012)

* Improved support for namespaced controllers and models.

* Pass :if and :unless options for load and authorize resource (mauriciozaffari).

* Travis CI badge (plentz).

* Adding Ability#merge for combining multiple abilities (rogercampos).

* Support for multiple MetaWhere rules (andhapp).

* Various fixes for DataMapper, Mongoid, and Inherited Resource integration.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.6.7...1.6.8].


## 1.6.7 (October 4, 2011)

* Fixing nested resource problem caused by namespace addition - issue #482.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.6.6...1.6.7].


## 1.6.6 (September 28, 2011)

* Correct "return cant jump across threads" error when using check_authorization (codeprimate) - issues #463, #469.

* Fixing tests in development by specifying with_model version  (kirkconnell) - issue #476.

* Added travis.yml file for TravisCI support (bai) - issue #427.

* Better support for namespaced models (whilefalse) - issues #424.

* Adding :id_param option to load_and_authorize_resource (skhisma) - issue #425.

* Make default unauthorized message translatable text (nhocki) - issue #409.

* Improving DataMapper behavior (psanford, maxsum-corin) - issue #410, #373.

* Allow :find_by option to be full find method name - issue #335.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.6.5...1.6.6].


## 1.6.5 (May 18, 2011)

* [#366](https://github.com/CanCanCommunity/cancancan/issues/366): Pass action and subject through AccessDenied exception when :through isn't found.

* Many Mongoid adapter improvements (rahearn, cardagin) - issues #363, #352, #343.

* [#360](https://github.com/CanCanCommunity/cancancan/issues/360): Allow :through option to work with private controller methods.

* [#359](https://github.com/CanCanCommunity/cancancan/issues/359): Ensure Mongoid::Document is defined before loading Mongoid adapter.

* [#355](https://github.com/CanCanCommunity/cancancan/issues/355): Many DataMapper adapter improvements ([@emmanuel][]).

* [#330](https://github.com/CanCanCommunity/cancancan/issues/330): Handle checking nil attributes through associations ([@thatothermitch][]).

* Improve scope merging - issue #328.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.6.4...1.6.5].


## 1.6.4 (March 29, 2011)

* Fixed mongoid 'or' error - see issue #322.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.6.3...1.6.4].


## 1.6.3 (March 25, 2011)

* Make sure ActiveRecord::Relation is defined before checking conditions against it so Rails 2 is supported again - see issue #312.

* Return subject passed to authorize! - see issue #314.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.6.2...1.6.3].


## 1.6.2 (March 18, 2011)

* Fixed instance loading when :singleton option is used - see issue #310.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.6.1...1.6.2].


## 1.6.1 (March 15, 2011)

* Use Item.new instead of build_item for singleton resource so it doesn't effect database - see issue #304.

* Made accessible_by action default to :index and parent action default to :show instead of :read - see issue #302.

* Reverted Inherited Resources "collection" override since it doesn't seem to be working - see issue #305.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.6.0...1.6.1].


## 1.6.0 (March 11, 2011)

* Added MetaWhere support - see issue #194 and #261.

* Allow Active Record scopes in Ability conditions - see issue #257.

* Added :if and :unless options to check_authorization - see issue #284.

* Several Inherited Resources fixes (aq1018, tanordheim and stefanoverna).

* Pass action name to accessible_by call when loading a collection ([@amw][]).

* Added :prepend option to load_and_authorize_resource to load before other filters - see issue #290.

* Fixed spacing issue in I18n message for multi-word model names - see issue #292.

* Load resource collection for any action which doesn't have an "id" parameter - see issue #296.

* Raise an exception when trying to make a Ability condition with both a hash of conditions and a block - see issue #269.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.5.1...1.6.0].


## 1.5.1 (January 20, 2011)

* Fixing deeply nested conditions in Active Record adapter - see issue #246.

* Improving Mongoid support for multiple can and cannot definitions ([@stellard][]) - see issue #239.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.5.0...1.5.1].


## 1.5.0 (January 11, 2011)

* Added an Ability generator - see issue #170.

* Added DataMapper support ([@natemueller][]).

* Added Mongoid support ([@bowsersenior][]).

* Added skip_load_and_authorize_resource methods to controller class - see issue #164.

* Added support for uncountable resources in index action - see issue #193.

* Cleaned up README and added spec/README.

* Internal: renamed CanDefinition to Rule.

* Internal: added a model adapter layer for easily supporting more ORMs.

* Internal: added .rvmrc to auto-switch to 1.8.7 with gemset - see issue #231.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.4.1...1.5.0].


## 1.4.1 (November 12, 2010)

* Renaming skip_authorization to skip_authorization_check - see issue #169.

* Adding :through_association option to load_resource ([@hunterae][]) - see issue #171.

* The :shallow option now works with the :singleton option ([@nandalopes][]) - see issue #187.

* Play nicely with quick_scopes gem ([@ramontayag][]) - see issue #183.

* Fix odd behavior when "cache_classes = false" ([@mphalliday][]) - see issue #174.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.4.0...1.4.1].


## 1.4.0 (October 5, 2010)

* Adding Gemfile; to get specs running just +bundle+ and +rake+ - see issue #163.

* Stop at 'cannot' definition when there are no conditions - see issue #161.

* The :through option will now call a method with that name if instance variable doesn't exist - see issue #146.

* Adding :shallow option to load_resource to bring back old behavior of fetching a child without a parent.

* Raise AccessDenied error when loading a child and parent resource isn't found.

* Abilities defined on a module will apply to anything that includes that module - see issue #150 and #152.

* Abilities can be defined with a string of SQL in addition to a block so accessible_by works with a block - see issue #150.

* Adding better support for InheritedResource - see issue #23.

* Loading the collection instance variable (for index action) using accessible_by - see issue #137.

* Adding action and subject variables to I18n unauthorized message - closes #142.

* Adding check_authorization and skip_authorization controller class methods to ensure authorization is performed ([@justinko][]) - see issue #135.

* Setting initial attributes based on ability conditions in new/create actions - see issue #114.

* Check parent attributes for nested association in index action - see issue #121.

* Supporting nesting in can? method using hash - see issue #121.

* Adding I18n support for Access Denied messages ([@EppO][]) - see issue #103.

* Passing no arguments to +can+ definition will pass action, class, and object to block - see issue #129.

* Don't pass action to block in +can+ definition when using :+manage+ option - see issue #129.

* No longer calling block in +can+ definition when checking on class - see issue #116.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.3.4...1.4.0].


## 1.3.4 (August 31, 2010)

* Don't stop at +cannot+ with hash conditions when checking class ([@tamoya][]) - see issue #131.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.3.3...1.3.4].


## 1.3.3 (August 20, 2010)

* Switching to Rspec namespace to remove deprecation warning in Rspec 2 - see issue #119.

* Pluralize nested associations for conditions in accessible_by ([@mlooney][]) - see issue #123.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.3.2...1.3.3].


## 1.3.2 (August 7, 2010)

* Fixing slice error when passing in custom resource name - see issue #112.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.3.1...1.3.2].


## 1.3.1 (August 6, 2010)

* Fixing protected sanitize_sql error - see issue #111.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.3.0...1.3.1].


## 1.3.0 (August 6, 2010)

* Adding :find_by option to load_resource - see issue #19.

* Adding :singleton option to load_resource - see issue #93.

* Supporting multiple resources in :through option for polymorphic associations - see issue #73.

* Supporting Single Table Inheritance for "can" comparisons - see issue #55.

* Adding :instance_name option to load/authorize_resource - see issue #44.

* Don't pass nil to "new" to keep MongoMapper happy - see issue #63.

* Parent resources are now authorized with :read action.

* Changing :resource option in load/authorize_resource back to :class with ability to pass false.

* Removing :nested option in favor of :through option with separate load/authorize call.

* Moving internal logic from ResourceAuthorization to ControllerResource class.

* Supporting multiple "can" and "cannot" calls with accessible_by (funny-falcon) - see issue #71.

* Supporting deeply nested aliases - see issue #98.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.2.0...1.3.0].


## 1.2.0 (July 16, 2010)

* Load nested parent resources on collection actions such as "index" (dohzya).

* Adding :name option to load_and_authorize_resource if it does not match controller - see issue #65.

* Fixing issue when using accessible_by with nil can conditions (jrallison) - see issue #66.

* Pluralize table name for belongs_to associations in can conditions hash (logandk) - see issue #62.

* Support has_many association or arrays in can conditions hash.

* Adding joins clause to accessible_by when conditions are across associations.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.1.1...1.2.0].


## 1.1.1 (April 17, 2010)

* Fixing behavior in Rails 3 by properly initializing ResourceAuthorization.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.1...1.1.1].


## 1.1.0 (April 17, 2010)

* Supporting arrays, ranges, and nested hashes in ability conditions.

* Removing "unauthorized!" method in favor of "authorize!" in controllers.

* Adding action, subject and default_message abilities to AccessDenied exception - see issue #40.

* Adding caching to current_ability controller method, if you're overriding this be sure to add caching too.

* Adding "accessible_by" method to Active Record for fetching records matching a specific ability.

* Adding conditions behavior to Ability#can and fetch with Ability#conditions - see issue #53.

* Renaming :class option to :resource for load_and_authorize_resource which now supports a symbol for non models - see issue #45.

* Properly handle Admin::AbilitiesController in params[:controller] - see issue #46.

* Adding be_able_to RSpec matcher (dchelimsky), requires Ruby 1.8.7 or higher - see issue #54.

* Support additional arguments to can? which get passed to the block - see issue #48.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.0.2...1.1].


## 1.0.2 (Dec 30, 2009)

* Adding clear_aliased_actions to Ability which removes previously defined actions including defaults - see issue #20.

* Append aliased actions (don't overwrite them) - see issue #20.

* Adding custom message argument to unauthorized! method (tjwallace) - see issue #18.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.0.1...1.0.2].


## 1.0.1 (Dec 14, 2009)

* Adding :class option to load_resource so one can customize which class to use for the model - see issue #17.

* Don't fetch parent of nested resource if *_id parameter is missing so it works with shallow nested routes - see issue #14.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/1.0.0...1.0.1].


## 1.0.0 (Dec 13, 2009)

* Don't set resource instance variable if it has been set already - see issue #13.

* Allowing :nested option to accept an array for deep nesting.

* Adding :nested option to load resource method - see issue #10.

* Pass :only and :except options to before filters for load/authorize resource methods.

* Adding :collection and :new options to load_resource method so we can specify behavior of additional actions if needed.

* BACKWARDS INCOMPATIBLE: turning load and authorize resource methods into class methods which set up the before filter so they can accept additional arguments.

* {see the full list of changes}[https://github.com/CanCanCommunity/cancancan/compare/0.2.1...1.0.0].


## 0.2.1 (Nov 26, 2009)

* Many internal refactorings - see issues #11 and #12.

* Adding "cannot" method to define which abilities cannot be done - see issue #7.

* Support custom objects (usually symbols) in can definition - see issue #8.

* See the full list of changes [https://github.com/CanCanCommunity/cancancan/compare/0.2.0...0.2.1].


## 0.2.0 (Nov 17, 2009)

* Fix behavior of load_and_authorize_resource for namespaced controllers - see issue #3.

* Support arrays being passed to "can" to specify multiple actions or classes - see issue #2.

* Adding "cannot?" method to ability, controller, and view which is inverse of "can?" - see issue #1.

* BACKWARDS INCOMPATIBLE: use Ability#initialize instead of 'prepare' to set up abilities - see issue #4.

* See the full list of changes [https://github.com/CanCanCommunity/cancancan/compare/0.1.0...0.2.0].


## 0.1.0 (Nov 16, 2009)

* Initial release.

[@coorasse]: https://github.com/coorasse
[@cb341]: https://github.com/cb341
[@kraflab]: https://github.com/kraflab
[@lizzyaustad]: https://github.com/lizzyaustad
[@kevintyll]: https://github.com/kevintyll
[@BookOfGreg]: https://github.com/BookOfGreg
[@arturoherrero]: https://github.com/arturoherrero
[@Eric-Guo]: https://github.com/Eric-Guo
[@ajgon]: https://github.com/ajgon
[@jpmckinney]: https://github.com/jpmckinney
[@sethcharles]: https://github.com/sethcharles
[@anilmaurya]: https://github.com/anilmaurya
[@DNNX]: https://github.com/DNNX
[@clemens]: https://github.com/clemens
[@bryanrite]: https://github.com/bryanrite
[@emmanuel]: https://github.com/emmanuel
[@thatothermitch]: https://github.com/thatothermitch
[@amw]: https://github.com/amw
[@stellard]: https://github.com/stellard
[@natemueller]: https://github.com/natemueller
[@bowsersenior]: https://github.com/bowsersenior
[@hunterae]: https://github.com/hunterae
[@nandalopes]: https://github.com/nandalopes
[@ramontayag]: https://github.com/ramontayag
[@mphalliday]: https://github.com/mphalliday
[@justinko]: https://github.com/justinko
[@EppO]: https://github.com/EppO
[@tamoya]: https://github.com/tamoya
[@mlooney]: https://github.com/mlooney
[@rrosen]: https://github.com/rrosen
[@steerio]: https://github.com/steerio
[@yuszuv]: https://github.com/yuszuv
[@albertobajo]: https://github.com/albertobajo
[@xinuc]: https://github.com/xinuc
[@oliverklee]: https://github.com/oliverklee
[@gingray]: https://github.com/gingray
[@timraymond]: https://github.com/timraymond
[@s-mage]: https://github.com/s-mage
[@Jcambass]: https://github.com/Jcambass
[@nyamadori]: https://github.com/nyamadori
[@andrew-aladev]: https://github.com/andrew-aladev
[@phaedryx]: https://github.com/phaedryx
[@kaspernj]: https://github.com/kaspernj
[@frostblooded]: https://github.com/frostblooded
[@eloyesp]: https://github.com/eloyesp
[@mtsmfm]: https://github.com/mtsmfm
[@koic]: https://github.com/koic
[@fsateler]: https://github.com/fsateler
[@aleksejleonov]: https://github.com/aleksejleonov
[@albb0920]: https://github.com/albb0920
[@ayumu838]: https://github.com/ayumu838
[@Liberatys]: https://github.com/Liberatys
[@ghiculescu]: https://github.com/ghiculescu
[@mtoneil]: https://github.com/mtoneil
[@Juleffel]: https://github.com/Juleffel
[@honigc]: https://github.com/honigc
[@WriterZephos]: https://github.com/WriterZephos
[@MrChoclate]: https://github.com/MrChoclate
[@pandermatt]: https://github.com/pandermatt
[@kalsan]: https://github.com/kalsan
[@bruno-costanzo]: https://github.com/bruno-costanzo
[@benaitcheson]: https://github.com/benaitcheson
[@daveallie]: https://github.com/daveallie
[@cgunther]: https://github.com/cgunther
[@mswiszcz]: https://github.com/mswiszcz
[@andrykonchin]: https://github.com/andrykonchin
[@ammarghaus]: https://github.com/ammarghaus
[@mark-young-atg]: https://github.com/mark-young-atg
[@jaredbeck]: https://github.com/jaredbeck
[@NikosVlagoidis]: https://github.com/NikosVlagoidis
[@olistik]: https://github.com/olistik
[@oboxodo]: https://github.com/oboxodo
[@takayamaki]: https://github.com/takayamaki
[@sjoulbak]: https://github.com/sjoulbak
[@0llirocks]: https://github.com/0llirocks
[@kevinluo201]: https://github.com/kevinluo201
[@jtagle2]: https://github.com/jtagle2
[@mamhoff]: https://github.com/mamhoff
[@tr4b4nt]: https://github.com/tr4b4nt
[@enmanuelm19]: https://github.com/enmanuelm19
