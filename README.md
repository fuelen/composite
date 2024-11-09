# Composite

## Installation

The package can be installed from [hex.pm](https://hex.pm/packages/composite) by
adding `composite` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:composite, "~> 0.5"}
  ]
end
```
Docs can be found at [https://hexdocs.pm/composite](https://hexdocs.pm/composite).

## About

Composite is a versatile utility library for building dynamic queries in Elixir. It simplifies the process of
constructing complex queries based on input parameters, making your code more concise and readable. While the library
was with Ecto in mind, it can be used with any Elixir term, as it's essentially an advanced wrapper around Enum.reduce/3.

The majority of the features of the library can be expressed by this example:
```elixir
def list_users(params) do
  MyApp.User
  |> where(active: true)
  |> Composite.new(params)
  |> Composite.param(:name, &where(&1, name: ^&2))
  |> Composite.param([:company, :name], &where(&1, [companies: companies], companies.name == ^&2),
    requires: :companies
  )
  |> Composite.param(
    :locations,
    &where(&1, [departments: departments], departments.location in ^&2),
    requires: :departments,
    ignore?: &(&1 in [nil, []] or "Worldwide" in &1)
  )
  |> Composite.param(
    :order,
    fn
      query, :department_name_asc ->
        query |> order_by([departments: departments], asc: departments.name)

      query, :username_asc ->
        query |> order_by(asc: :name)
    end,
    requires: fn
      :department_name_asc -> :departments
      _ -> nil
    end
  )
  |> Composite.dependency(:departments, fn query ->
    join(query, :inner, [users], assoc(users, :department), as: :departments)
  end)
  |> Composite.dependency(
    :companies,
    fn query ->
      join(query, :inner, [departments: departments], assoc(departments, :company), as: :companies)
    end,
    requires: :departments
  )
  |> MyApp.Repo.all()
end
```

Let's move anonymous functions to named functions, so it doesn't look so scary:
```elixir
def list_users(params) do
  MyApp.User
  |> where(active: true)
  |> Composite.new(params)
  |> Composite.param(:name, &where(&1, name: ^&2))
  |> Composite.param([:company, :name], &filter_users_by_company_name/2, requires: :companies)
  |> Composite.param(:locations, &filter_users_by_department_locations/2, requires: :departments, ignore?: &(&1 in [nil, []] or "Worldwide" in &1))
  |> Composite.param(:order, &order_users/2, requires: &if(&1 == :department_name_asc, do: :departments))
  |> Composite.dependency(:departments, &join_departments/1)
  |> Composite.dependency(:companies, &join_companies/1, requires: :departments)
  |> MyApp.Repo.all()
end
```
Yes, it looks like a router.
The example above starts with Ecto query. 
The query is wrapped into `Composite` struct by calling `Composite.new/2`. It will be unwrapped automatically during
`MyApp.Repo.all/1` call, as `Composite` implements `Ecto.Queryable` protocol.
Parameter handlers are defined using `Composite.param/3` and `Composite.param/4`. These instructions define
how the query should be modified if given parameters are present. By default parameters are ignored if they have
one of the following values: `nil`, `""`, `[]`, `%{}`. However, this behaviour can be adjusted by using `:ignore?` option.

Parameter keys are not limited to atoms only, they can have any type. Lists have special meaning: if list is specified,
then this is a path to nested structure.
Here is an example with all parameters for our `list_users/1` function:
```elixir
# all keys are optional
%{name: "John", company: %{name: "GitHub"}, order: :department_name_asc, locations: ["USA"]}
```

As you may noticed, there is a concept of dependencies.
Dependencies can be declared with `Composite.dependency/3` and `Composite.dependency/4` functions by specifying loader function.
The loader function is invoked before invoking parameter handler.
Dependencies can have other dependencies as well. Dependencies are loaded only when they're needed and only once.
So, if multiple parameter handlers require the same table to be joined to the query, it will be joined only once without any errors.

## Links

* Article: [Writing dynamic Ecto queries with Composite](https://dev.to/arturplysiuk/writing-dynamic-ecto-queries-with-composite-26g4)
