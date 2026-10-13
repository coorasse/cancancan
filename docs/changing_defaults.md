# Customize the controller helpers

We now dig deeper in the customizations and options we have when working with [controller helpers](./controller_helpers.md)

## current_ability and current_user

CanCanCan makes two assumptions about your application:

- You have an `Ability` class which defines the permissions.
- You have a `current_user` method in the controller which returns the current user model.

You can override both of these by defining the `current_ability` method in your `ApplicationController`. The default method looks like this.

```ruby
def current_ability
  @current_ability ||= Ability.new(current_user)
end
```

The `Ability` class and `current_user` method can easily be changed to something else.

```ruby
# in ApplicationController
def current_ability
  @current_ability ||= AccountAbility.new(current_account)
end
```

Sometimes you might have a gem in your project which provides its own Rails engine which also uses CanCanCan, in this case the current_ability override in the ApplicationController can also be useful.

```ruby
# in ApplicationController
def current_ability
  if request.fullpath =~ /\/rails_admin/
    @current_ability ||= RailsAdmin::Ability.new(current_user)
  else
    @current_ability ||= Ability.new(current_user)
  end
end
```

If your method that returns the currently logged in user just has another name than `current_user`, it may be the easiest solution to simply alias the method in your ApplicationController like this:

```ruby
class ApplicationController < ActionController::Base
  alias_method :current_user, :name_of_your_method # Could be :current_member or :logged_in_user
end
```

## Strong parameters

If your parameters sanitization method does not follow the naming convention, `load_and_authorize_resource` takes a `param_method` option to specify a custom method in the controller to run to sanitize input.

You can associate the `param_method` option with a symbol corresponding to the name of a method that will get called:

```ruby
class ArticlesController < ApplicationController
  load_and_authorize_resource param_method: :my_sanitizer

  def create
    @article.save
  end

  private

  def my_sanitizer
    params.require(:article).permit(:name)
  end
end
```

You can also use a string that will be evaluated in the context of the controller using `instance_eval` and needs to contain valid Ruby code.

```ruby
load_and_authorize_resource param_method: 'permitted_params.post'
```

Finally, it's possible to associate `param_method` with a Proc object which will be called with the controller as the only argument:

```ruby
load_and_authorize_resource param_method: -> { |c| c.params.require(:article).permit(:name) }
```

If your model name and controller name differ, you can specify a `class` option.

> Note that the method will still be `articles_params` and not `post_params`, since we are in `ArticlesController`.

```ruby
class ArticlesController < ApplicationController
  load_and_authorize_resource class: 'Post'

  def create
    @article.save
  end

  private

  def article_params
    params.require(:article).permit(:name)
  end
end
```

## Non RESTful controllers

You can use CanCanCan with controllers that do not follow the traditional REST actions, however you should not use the `load_and_authorize_resource` method since there is no resource to load. Instead you can call `authorize!` in each action separately.

For example, let's say we have a controller which does some miscellaneous administration tasks such as rolling log files. We can use the `authorize!` method here.

```ruby
class AdminController < ActionController::Base
  def roll_logs
    authorize! :roll, :logs
    # roll the logs here
  end
end
```

And then authorize that in the `Ability` class.

```ruby
can :roll, :logs if user.admin?
```

Notice you can pass a symbol as the second argument to both `authorize!` and `can`. It doesn't have to be a model class or instance.

Alternatively you can use the `authorize_resource` and specify that there's no class. This way it will pass the resource symbol instead. This is good if you still have a Resource-like controller but no model class backing it.

```ruby
class ToolsController < ApplicationController
  authorize_resource class: false

  def show
    # automatically calls authorize!(:show, :tool)
  end
end
```

## skip load and authorize

You can use the `skip_load_and_authorize_resource`, `skip_load_resource` or `skip_authorize_resource` methods to skip any of the applied behavior and specify specific actions like in a before filter. For example:

```ruby
class ProductsController < ActionController::Base
  load_and_authorize_resource
  skip_authorize_resource only: :new
end
```
All three methods also support the `:if` and `:unless` options. Either one takes a method name as a symbol or a
lambda/proc, which is evaluated on the controller instance. The behavior is skipped only if `:if` returns a truthy
value, and only if `:unless` returns a falsy value. Like in a `before_action`, all the given options must match:

```ruby
class ProductsController < ActionController::Base
  load_and_authorize_resource
  skip_authorize_resource only: :index, if: :admin?
  skip_load_resource unless: -> { request.format.html? }
end
```

Here the authorization is skipped on `index` only when `admin?` returns true, and the loading is skipped on every
action unless the request asks for HTML.

Every call to `authorize_resource` or `load_and_authorize_resource` adds a new `before_action`, so calling it again in a subclass does not replace the one inherited from the parent controller. To change its options, skip the inherited one and give a name to the new one, so that the skip does not apply to it:

```ruby
class ApplicationController < ActionController::Base
  authorize_resource
end

class ReportsController < ApplicationController
  skip_authorize_resource
  authorize_resource :report, class: "Analytics::Report"
end
```

### Custom class name

If the model is named differently than the controller, then you may explicitly name the model that should be loaded:

```ruby
class ArticlesController < ApplicationController
  load_and_authorize_resource :post
end
```

The post is loaded with `params[:id]` and authorized with the action of the controller. It is considered a parent resource, loaded with `params[:post_id]` and authorized with `:show`, only when another resource is loaded `through` it or when the request has a `post_id` parameter. Pass `parent: false` to never treat it as a parent.

If the model class is namespaced differently than the controller you will need to specify the `:class` option.

```ruby
class ProductsController < ApplicationController
  load_and_authorize_resource class: "Store::Product"
end
```

### Custom find

If you want to fetch a resource by something other than `id` it can be done so using the `find_by` option.

```ruby
load_resource find_by: :permalink # will use find_by!(permalink: params[:id])
authorize_resource
```

`find_by` only changes the column, the value is still read from `params[:id]`. If your route uses another parameter, for example with `resources :books, param: :uuid`, pass it with `id_param`:

```ruby
load_and_authorize_resource find_by: :uuid, id_param: :uuid # will use find_by!(uuid: params[:uuid])
```

CanCanCan considers an action a member action, and loads a single record, only when the id parameter is present. Without `id_param`, `show` and `edit` would load the collection instead, and authorize the action on the class.

### Override loading

The resource will only be loaded into an instance variable if it hasn't been already. This allows you to easily override how the loading happens in a separate `before_action`.

```ruby
class BooksController < ApplicationController
  before_action :find_published_book, only: :show
  load_and_authorize_resource

  private

  def find_published_book
    @book = Book.released.find(params[:id])
  end
end
```

The instance variable must be set to a record: if it is `nil`, CanCanCan loads the resource again. Use `find`, which raises `ActiveRecord::RecordNotFound`, instead of `find_by`.
The instance variable is used only for member actions, so when the record is identified by another parameter than `:id`, set `id_param` as explained in [Custom find](#custom-find).

## check_authorization

If you want to be certain authorization is not forgotten in some controller action, add `check_authorization` to your `ApplicationController`.

```ruby
class ApplicationController < ActionController::Base
  check_authorization
end
```

This will add an `after_action` to ensure authorization takes place in every inherited controller action. If no authorization happens it will raise a `CanCan::AuthorizationNotPerformed` exception. You can skip this check by adding `skip_authorization_check` to that controller. Both of these methods take the same arguments as `before_action` so you can exclude certain actions with `:only` and `:except`.

```ruby
class UsersController < ApplicationController
  skip_authorization_check :only => [:new, :create]
  # ...
end
```

The `check_authorization` method supports `:if` and `:unless` options. Either one takes a method name as a symbol. This method will be called to determine if the authorization check will be performed. This makes it very easy to skip this check on all Devise controllers since they provide a `devise_controller?` method.

```ruby
class ApplicationController < ActionController::Base
  check_authorization unless: :devise_controller?
end
```

Here's another example where authorization is only ensured for the admin subdomain.

```ruby
class ApplicationController < ActionController::Base
  check_authorization if: :admin_subdomain?

  private

  def admin_subdomain?
    request.subdomain == "admin"
  end
end
```

> Note: The `check_authorization` only ensures that authorization is performed. If you have `authorize_resource` the authorization will still be performed no matter what is returned here.

The default operation for CanCanCan is to authorize based on user and the object identified in `load_resource`. So if you have a `WidgetsController` and also an `Admin::WidgetsController`, you can use some different approaches.

# Overriding authorizations for Namespaced controllers

You can create differing authorization rules that depend on the controller namespace.

In this case, just override the `current_ability` method in `ApplicationController` to include the controller namespace, and create an `Ability` class that knows what to do with it.

```ruby
class Admin::WidgetsController < ActionController::Base
  #...

  private

  def current_ability
    # I am sure there is a slicker way to capture the controller namespace
    controller_name_segments = params[:controller].split('/')
    controller_name_segments.pop
    controller_namespace = controller_name_segments.join('/').camelize
    @current_ability ||= Ability.new(current_user, controller_namespace)
  end
end


class Ability
  include CanCan::Ability

  def initialize(user, controller_namespace)
    case controller_namespace
      when 'Admin'
        can :manage, :all if user.has_role? 'admin'
      else
        # rules for non-admin controllers here
    end
  end
end
```

Another way to achieve the same is to use a completely different Ability class in this controller:

```ruby
class Admin::WidgetsController < ActionController::Base
  #...

  private

  def current_ability
    @current_ability ||= AdminAbility.new(current_user)
  end
end
```
