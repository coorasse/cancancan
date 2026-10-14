# frozen_string_literal: true

module CanCan
  def self.valid_accessible_by_strategies
    %i[left_join joined_alias_exists_subquery joined_alias_each_rule_as_exists_subquery subquery]
  end

  # You can disable the rules compressor if it's causing unexpected issues.
  def self.rules_compressor_enabled
    return @rules_compressor_enabled if defined?(@rules_compressor_enabled)

    @rules_compressor_enabled = true
  end

  def self.rules_compressor_enabled=(value)
    @rules_compressor_enabled = value
  end

  def self.with_rules_compressor_enabled(value)
    return yield if value == rules_compressor_enabled

    begin
      rules_compressor_enabled_was = rules_compressor_enabled
      @rules_compressor_enabled = value
      yield
    ensure
      @rules_compressor_enabled = rules_compressor_enabled_was
    end
  end

  # Since 4.0, a `cannot` rule with a scope excludes the records of the scope. It used to select the records
  # that remain accessible, so such rules must be reviewed when upgrading. Until this is set to false, every
  # `cannot` rule with a scope is reported once with a warning.
  #
  #   # config/initializers/cancan.rb
  #   CanCan.warn_on_cannot_rules_with_scope = false
  def self.warn_on_cannot_rules_with_scope
    return @warn_on_cannot_rules_with_scope if defined?(@warn_on_cannot_rules_with_scope)

    @warn_on_cannot_rules_with_scope = true
  end

  def self.warn_on_cannot_rules_with_scope=(value)
    @warn_on_cannot_rules_with_scope = value
  end

  @warned_cannot_rules_with_scope = Set.new

  # Reports a cannot rule with a scope once per place it is defined. The locations are the frames of the caller
  # of `cannot`, so rules defined through a helper method are reported for each call of the helper.
  def self.warn_on_cannot_rule_with_scope(rule, locations)
    return unless warn_on_cannot_rules_with_scope && rule.with_scope?
    return unless @warned_cannot_rules_with_scope.add?([locations.map(&:to_s), rule.actions, rule.subjects])

    Kernel.warn cannot_rule_with_scope_warning(rule, locations.first)
  end

  def self.cannot_rule_with_scope_warning(rule, location)
    "CanCanCan 4.0: the scope of the cannot rule at #{location.path}:#{location.lineno} selects the records that " \
      "cannot be #{rule.actions.join(', ')}, while it used to select the accessible ones: " \
      "cannot #{rule.actions.map(&:inspect).join(', ')}, #{rule.subjects.join(', ')}, #{rule.conditions.to_sql}. " \
      'Review the rule and set CanCan.warn_on_cannot_rules_with_scope = false. See ' \
      'https://github.com/CanCanCommunity/cancancan/blob/main/docs/define_abilities_with_blocks.md' \
      '#block-conditions-with-activerecord-scopes'
  end

  # Determines how CanCan should build queries when calling accessible_by,
  # if the query will contain a join. The default strategy is `:subquery`.
  #
  #   # config/initializers/cancan.rb
  #   CanCan.accessible_by_strategy = :subquery
  #
  # Valid strategies are:
  # - :subquery - Creates a nested query with all joins, wrapped by a
  #               WHERE IN query.
  # - :left_join - Calls the joins directly using `left_joins`, and
  #                ensures records are unique using `distinct`. Note that
  #                `distinct` is not reliable in some cases. See
  #                https://github.com/CanCanCommunity/cancancan/pull/605
  # - :joined_alias_exists_subquery, :joined_alias_each_rule_as_exists_subquery -
  #                Build an EXISTS subquery on an aliased table.
  # - a subclass of CanCan::ModelAdapters::Strategies::Base - Your own
  #                strategy. Implement `execute!` and return the relation.
  def self.accessible_by_strategy
    Thread.current[:cancan_accessible_by_strategy_override] ||
      @accessible_by_strategy ||
      default_accessible_by_strategy
  end

  def self.default_accessible_by_strategy
    :subquery
  end

  def self.accessible_by_strategy=(value)
    validate_accessible_by_strategy!(value)
    @accessible_by_strategy = value
  end

  # Overrides the strategy for the duration of the block. The override is local to the current
  # thread and fiber, so it never leaks into concurrent requests.
  def self.with_accessible_by_strategy(value)
    return yield if value == accessible_by_strategy

    validate_accessible_by_strategy!(value)

    begin
      override_was = Thread.current[:cancan_accessible_by_strategy_override]
      Thread.current[:cancan_accessible_by_strategy_override] = value
      yield
    ensure
      Thread.current[:cancan_accessible_by_strategy_override] = override_was
    end
  end

  def self.validate_accessible_by_strategy!(value)
    return if valid_accessible_by_strategies.include?(value)
    return if custom_accessible_by_strategy?(value)

    raise ArgumentError, "accessible_by_strategy must be one of #{valid_accessible_by_strategies.join(', ')} " \
                         'or a subclass of CanCan::ModelAdapters::Strategies::Base'
  end

  def self.custom_accessible_by_strategy?(value)
    value.is_a?(Class) &&
      defined?(CanCan::ModelAdapters::Strategies::Base) &&
      value < CanCan::ModelAdapters::Strategies::Base
  end
end
