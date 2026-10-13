# frozen_string_literal: true

module CanCan
  # Handle the load and authorization controller logic
  # so we don't clutter up all controllers with non-interface methods.
  # This class is used internally, so you do not need to call methods directly on it.
  class ControllerResource # :nodoc:
    def self.add_before_action(controller_class, method, *args)
      options = args.extract_options!
      resource_name = args.first
      before_action_method = before_callback_name(options)
      controller_class.send(before_action_method, options.slice(:only, :except, :if, :unless)) do |controller|
        controller.class.cancan_resource_class
                  .new(controller, resource_name, options.except(:only, :except, :if, :unless)).send(method)
      end
    end

    def self.before_callback_name(options)
      options.delete(:prepend) ? :prepend_before_action : :before_action
    end

    def initialize(controller, *args)
      @controller = controller
      @params = controller.params
      @options = args.extract_options!
      @name = args.first&.to_sym
    end

    def load_and_authorize_resource
      load_resource
      authorize_resource
    end

    def load_resource
      return if skip?(:load)

      if load_instance?
        self.resource_instance ||= load_resource_instance
      elsif load_collection?
        self.collection_instance ||= load_collection
      end
    end

    def authorize_resource
      return if skip?(:authorize)

      @controller.authorize!(authorization_action, resource_instance || resource_class_with_parent)
    end

    def parent?
      @options.key?(:parent) ? @options[:parent] : @name && @name != name_from_controller.to_sym
    end

    # The options of skip_load_resource, skip_authorize_resource and skip_load_and_authorize_resource
    # are combined like in a before_action: every given option must match.
    def skip?(behavior)
      options = @controller.class.cancan_skipper[behavior][@name]
      return false unless options

      action_matches?(options) && conditions_met?(options)
    end

    protected

    def name
      @name || name_from_controller
    end

    def name_from_controller
      @params[:controller].split('/').last.singularize
    end

    def namespace
      @params[:controller].split('/')[0..-2]
    end

    def namespaced_name
      [namespace, name].join('/').singularize.camelize.safe_constantize || name
    end

    def instance_name
      @options[:instance_name] || name
    end

    # Returns the class used for this resource. This can be overridden by the :class option.
    # If +false+ is passed in it will use the resource name as a symbol in which case it should
    # only be used for authorization, not loading since there's no class to load through.
    def resource_class
      @resource_class ||= resource_class_from_options
    end

    def resource_class_from_options
      case @options[:class]
      when false
        name.to_sym
      when nil
        namespaced_name.to_s.camelize.constantize
      when String
        @options[:class].constantize
      else
        @options[:class]
      end
    end

    def resource_class_with_parent
      parent_resource ? { parent_resource => resource_class } : resource_class
    end

    def new_actions
      %i[new create] + Array(@options[:new]).map(&:to_sym)
    end

    def collection_actions
      [:index] + Array(@options[:collection]).map(&:to_sym)
    end

    def save_actions
      %i[create update]
    end

    def member_action?
      new_actions.include?(@params[:action].to_sym) || @options[:singleton] ||
        ((@params[:id] || @params[@options[:id_param]]) &&
          !collection_actions.include?(@params[:action].to_sym))
    end

    def load_instance?
      parent? || member_action?
    end

    def load_collection?
      resource_base.respond_to?(:accessible_by) && !current_ability.has_block?(authorization_action, resource_class)
    end

    def parent_authorization_action
      @options[:parent_action] || :show
    end

    def authorization_action
      parent? ? parent_authorization_action : @params[:action].to_sym
    end

    def resource_instance=(instance)
      @controller.instance_variable_set("@#{instance_name}", instance)
    end

    def resource_instance
      return unless load_instance? && @controller.instance_variable_defined?("@#{instance_name}")

      @controller.instance_variable_get("@#{instance_name}")
    end

    def collection_instance=(instance)
      @controller.instance_variable_set("@#{instance_name.to_s.pluralize}", instance)
    end

    def collection_instance
      return unless @controller.instance_variable_defined?("@#{instance_name.to_s.pluralize}")

      @controller.instance_variable_get("@#{instance_name.to_s.pluralize}")
    end

    def load_collection
      resource_base.accessible_by(current_ability, authorization_action)
    end

    def load_resource_instance
      if !parent? && new_actions.include?(@params[:action].to_sym)
        build_resource
      elsif id_param || @options[:singleton]
        find_resource
      end
    end

    def fetch_parent(name)
      if @controller.instance_variable_defined? "@#{name}"
        @controller.instance_variable_get("@#{name}")
      elsif @controller.respond_to?(name, true)
        @controller.send(name)
      end
    end

    # The object to load this resource through.
    def parent_resource
      parent_name && fetch_parent(parent_name)
    end

    def parent_name
      @options[:through] && [@options[:through]].flatten.detect { |i| fetch_parent(i) }
    end

    def resource_base_through_parent_resource
      if @options[:singleton]
        resource_class
      else
        parent_resource.send(@options[:through_association] || name.to_s.pluralize)
      end
    end

    def resource_base_through
      if parent_resource
        resource_base_through_parent_resource
      elsif @options[:shallow]
        resource_class
      else
        # maybe this should be a record not found error instead?
        raise AccessDenied.new(nil, authorization_action, resource_class)
      end
    end

    # The object that methods (such as "find", "new" or "build") are called on.
    # If the :through option is passed it will go through an association on that instance.
    # If the :shallow option is passed it will use the resource_class if there's no parent
    # If the :singleton option is passed it won't use the association because it needs to be handled later.
    def resource_base
      @options[:through] ? resource_base_through : resource_class
    end

    def find_resource
      singleton_association_name = @options[:through_association] || name
      if @options[:singleton] && parent_resource.respond_to?(singleton_association_name)
        parent_resource.send(singleton_association_name)
      elsif @options[:find_by]
        find_resource_using_find_by
      else
        adapter.find(resource_base, id_param)
      end
    end

    def find_resource_using_find_by
      find_by_dynamic_finder || find_by_find_by_finder || resource_base.send(@options[:find_by], id_param)
    end

    def find_by_dynamic_finder
      method_name = "find_by_#{@options[:find_by]}!"
      resource_base.send(method_name, id_param) if resource_base.respond_to? method_name
    end

    def find_by_find_by_finder
      resource_base.find_by(@options[:find_by].to_sym => id_param) if resource_base.respond_to? :find_by
    end

    def id_param
      # A whitespace-only id is blank but given, so it must also be looked up.
      id = @params[id_param_key].to_s
      id unless id.empty?
    end

    def id_param_key
      if @options[:id_param]
        @options[:id_param]
      else
        parent? ? :"#{name}_id" : :id
      end
    end

    def build_resource
      resource = resource_base.new(resource_params || {})
      assign_attributes(resource)
    end

    def assign_attributes(resource)
      assign_parent(resource) if @options[:singleton] && parent_resource
      initial_attributes.each do |attr_name, value|
        resource.send("#{attr_name}=", value)
      end
      resource
    end

    # The parent is assigned through the setter named after the :through option when the resource has one,
    # otherwise through the inverse of the association on the parent.
    def assign_parent(resource)
      setter = "#{parent_name}="
      setter = "#{inverse_association_name}=" unless resource.respond_to?(setter)
      resource.send(setter, parent_resource)
    end

    def inverse_association_name
      association_name = @options[:through_association] || name
      inverse = inverse_of_association(parent_resource.class, association_name)
      return inverse if inverse

      raise Error, "Cannot assign the parent to the singleton resource: #{resource_class} has no " \
                   "#{parent_name}= method and the association #{association_name} on #{parent_resource.class} " \
                   'has no inverse. Define inverse_of on the association or use a through option named after it.'
    end

    def inverse_of_association(parent_class, association_name)
      return unless parent_class.respond_to?(:reflect_on_association)

      reflection = parent_class.reflect_on_association(association_name)
      reflection && (reflection.inverse_of&.name || reflection.options[:as])
    end

    def initial_attributes
      scoped_attributes = attributes_from_parent_scope
      current_ability.attributes_for(@params[:action].to_sym, resource_class).delete_if do |key, _value|
        scoped_attributes.include?(key.to_s) || resource_params&.include?(key)
      end
    end

    def attributes_from_parent_scope
      return [] unless @options[:through] && resource_base.respond_to?(:scope_for_create)

      resource_base.scope_for_create.keys.map(&:to_s)
    end

    # The params method of the controller can have side effects, so it is called at most once per request.
    def resource_params
      return @resource_params if defined?(@resource_params)

      @resource_params =
        if parameters_require_sanitizing? && params_method.present?
          sanitize_parameters
        else
          resource_params_by_namespaced_name
        end
    end

    def parameters_require_sanitizing?
      save_actions.include?(@params[:action].to_sym) || resource_params_by_namespaced_name.present?
    end

    def resource_params_by_key(key)
      return unless @options[key] && @params.key?(extract_key(@options[key]))

      @params[extract_key(@options[key])]
    end

    def resource_params_by_namespaced_name
      resource_params_by_key(:instance_name) || resource_params_by_key(:class) || (
      params = @params[extract_key(namespaced_name)]
      params.respond_to?(:to_h) ? params : nil)
    end

    def sanitize_parameters
      case params_method
      when Symbol
        @controller.send(params_method)
      when String
        @controller.instance_eval(params_method)
      when Proc
        params_method.call(@controller)
      end
    end

    def params_methods
      methods = [:"#{@params[:action]}_params", :"#{name}_params", :resource_params]
      methods.unshift(@options[:param_method]) if @options[:param_method].present?
      methods
    end

    def params_method
      params_methods.each do |method|
        return method if (method.is_a?(Symbol) && @controller.respond_to?(method, true)) ||
                         method.is_a?(String) || method.is_a?(Proc)
      end
      nil
    end

    private

    def action_matches?(options)
      (options[:only].nil? || action_exists_in?(options[:only])) &&
        (options[:except].nil? || !action_exists_in?(options[:except]))
    end

    def conditions_met?(options)
      (options[:if].nil? || condition_met?(options[:if])) &&
        (options[:unless].nil? || !condition_met?(options[:unless]))
    end

    def action_exists_in?(actions)
      Array(actions).map(&:to_sym).include?(@params[:action].to_sym)
    end

    def condition_met?(condition)
      result = condition.respond_to?(:call) ? call_condition(condition) : @controller.send(condition)
      !!result
    end

    def call_condition(condition)
      condition.arity.zero? ? @controller.instance_exec(&condition) : condition.call(@controller)
    end

    def extract_key(value)
      value.to_s.underscore.tr('/', '_')
    end

    def adapter
      ModelAdapters::AbstractAdapter.adapter_class(resource_class)
    end

    def current_ability
      @controller.send(:current_ability)
    end
  end
end
