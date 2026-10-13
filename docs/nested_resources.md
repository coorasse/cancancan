# Nested Resources

Let's say we have nested resources set up in our routes.

```ruby
resources :projects do
  resources :tasks
end
```

We can then tell CanCanCan to load the project and then load the task through that.

```ruby
class TasksController < ApplicationController
  load_and_authorize_resource :project
  load_and_authorize_resource :task, through: :project
end
```

This will fetch the project using `Project.find(params[:project_id])` on every controller action, save it in the `@project` instance variable, and authorize it using the `:read` action to ensure the user has the ability to access that project. If you don't want to do the authorization you can simply use `load_resource`, but calling just `authorize_resource` for the parent object is insufficient. The task is then loaded through the `@project.tasks` association.

If the name of the association doesn't match the resource name, for instance `has_many :issues, class_name: 'Task'`, you can specify the association name using `:through_association`.

```ruby
  class TasksController < ApplicationController
    load_and_authorize_resource :project
    load_and_authorize_resource :task, through: :project, through_association: :issues
  end
```

The same option applies to singleton resources, for instance `has_one :profile, class_name: 'Account'`:

```ruby
  class AccountsController < ApplicationController
    load_and_authorize_resource :user
    load_and_authorize_resource :account, through: :user, through_association: :profile, singleton: true
  end
```

If the resource name (`:project` in this case) does not match the controller, it is considered a parent resource when another resource is loaded `through` it or when the request has a parameter named after it, such as `project_id`. A parent resource is loaded with `params[:project_id]` and authorized with the `:show` action (see `:parent_action`). You can manually specify parent/child resources using the `parent: true` and `parent: false` options.

> **Warning**: a parent resource is always authorized with the `:show` action, whatever the action of the controller. If a resource with a different name than the controller is not a parent, pass `parent: false`, otherwise it will be authorized with `:show` also for actions like `update` or `destroy`.

## Securing `through` changes

If you are using `through`, you need to be wary of potential changes to the parent model. For example, consider this controller:

```ruby
class TasksController < ApplicationController
  load_and_authorize_resource :project
  load_and_authorize_resource :task, through: :project

  def update
    @task.update(task_params)
  end

  private

  def task_params
    params.require(:task).permit(:project_id)
  end
end
```

Now consider a request to `/projects/1/tasks/42` with params `{ task: { project_id: 2 } }`.

- `load_and_authorize_resource :project` will load project 1 and authorize it.
- `load_and_authorize_resource :task, through: :project` will load task 42 from project 1, and authorize it.
- `@task.update(task_params)` will change the task's project ID from 1, to 2.
- Project 2 is never authorized! An attacker could inject a project belonging to another customer here.

How you handle this depends on your intended behavior.

- If you don't want a task's project ID to ever change, don't permit it as a param.
- If you allow tasks to be moved between projects, manually verify the ID change and avoid mass assigning it.

```ruby
  def update
    @task.project = Project.find(task_params[:project_id])
    authorize!(@task)
    @task.assign(task_params.except(:project_id))
  end
```

## Nested through method

It's also possible to nest through a method, this is commonly the `current_user` method.

```ruby
class ProjectsController < ApplicationController
  load_and_authorize_resource through: :current_user
end
```

Here everything will be loaded through the `current_user.projects` association.

## Shallow nesting

The parent resource is required to be present and it will raise an exception if the parent is ever `nil`. If you want it to be optional (such as with shallow routes), add the `shallow: true` option to the child.

```ruby
class TasksController < ApplicationController
  load_and_authorize_resource :project
  load_and_authorize_resource :task, through: :project, shallow: true
end
```

## Singleton resource

What if each project only had one task through a `has_one` association? To set up singleton resources you can use the `:singleton` option.

```ruby
class TasksController < ApplicationController
  load_and_authorize_resource :project
  load_and_authorize_resource :task, through: :project, singleton: true
end
```

It will then use `@project.task` to fetch the record. New records are built with `Task.new` and the parent is assigned through `task.project=`, so the existing record of the `has_one` association is not touched. If the `:through` option does not match a setter on the resource, for instance `through: :current_project`, the parent is assigned through the inverse of the association, so define `inverse_of` on it when Rails cannot infer it.

If the project has no task, `@task` is `nil` and the action is authorized on `{ @project => Task }`, as for actions without an instance. No error is raised: if you want to respond with a 404, check it in the controller.

```ruby
before_action -> { raise ActiveRecord::RecordNotFound unless @task }, only: :show
```

## Polymorphic associations

Let's say tasks can either be assigned to a Project or an Event through a polymorphic association. An array can be passed into the `:through` option and it will use the first one it finds.

```ruby
load_resource :project
load_resource :event
load_and_authorize_resource :task, through: [:project, :event]
```

Here it will check both the `@project` and `@event` variables and fetch the task through whichever one exists. Note that this is only loading the parent model, if you want to authorize the parent you will need to do it through a before_action because there is special logic involved.

```ruby
before_action :authorize_parent

private

def authorize_parent
  authorize! :read, (@event || @project)
end
```

## Accessing parent in ability

Sometimes the child permissions are closely tied to the parent resource. For example, if there is a `user_id` column on Project, one may want to only allow access to tasks if the user owns their project.

This will happen automatically due to the `@project` instance being authorized in the nesting. However it's still a good idea to restrict the tasks separately. You can do so by going through the project association.

```ruby
# in Ability
can :manage, Task, project: { user_id: user.id }
```

This means you will need to have a project tied to the tasks which you pass into here. For example, if you are checking if the user has permission to create a new task, do that by building it through the project.

```ruby
can? :create, @project.tasks.build
```

It's also possible to check permission through an association like this.

```ruby
can? :read, @project => Task
```

This will use the above `:project` hash conditions and ensure `@project` meets those conditions.

## Has_many through associations

How to load and authorize resources with a `has_many :through` association?

Given that situation:

```ruby
class User < ActiveRecord::Base
  has_many :groups_users
  has_many :groups, through: :groups_users
end
```

```ruby
class Group < ActiveRecord::Base
  has_many :groups_users
  has_many :users, through: :groups_users
end
```

```ruby
class GroupsUsers < ActiveRecord::Base
  belongs_to :group, inverse_of: :groups_users
  belongs_to :user, inverse_of: :groups_users
end
```

and in the controller:

```ruby
class UsersController < ApplicationController
  load_and_authorize_resource :group
  load_and_authorize_resource through: :group
```

in ability.rb

```ruby
can :create, User, groups_users: { group: { CONDITION_ON_GROUP } }
```

Don't forget the **inverse_of** option, it is the trick to make it work correctly.

Remember to define the ability through the **groups_users** model (i.e. don't write `can :create, User, groups: { CONDITION_ON_GROUP }`)

You will be able to persist the association just calling `@user.save` instead of `@group.save`.
