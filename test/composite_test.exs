defmodule CompositeTest do
  use ExUnit.Case
  doctest Composite
  import Ecto.Query

  describe "compose dynamic ecto query" do
    test "pipeline" do
      users_query = from(users in "users")

      query =
        users_query
        |> Composite.new(%{name: "John", active: true})
        |> Composite.param(:name, &where(&1, name: ^&2))
        |> Composite.param(:active, &where(&1, active: true), ignore?: &(!&1))
        |> select([:id, :name])

      assert inspect(query) ==
               inspect(
                 from(users in "users",
                   where: users.name == ^"John",
                   where: users.active == true,
                   select: [:id, :name]
                 )
               )
    end

    test "prepared composite" do
      filter_by_company_name = &where(&1, [companies: companies], companies.name == ^&2)

      join_companies = fn query ->
        join(query, :inner, [departments: departments], companies in "companies",
          on: companies.id == departments.company_id,
          as: :companies
        )
      end

      join_departments = fn query ->
        join(query, :inner, [users], departments in "departments",
          on: departments.id == users.department_id,
          as: :departments
        )
      end

      composite =
        Composite.new()
        |> Composite.param(:name, &where(&1, name: ^&2))
        |> Composite.param([:company, :name], filter_by_company_name, requires: :companies)
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
        |> Composite.dependency(:companies, join_companies, requires: :departments)
        |> Composite.dependency(:departments, join_departments)

      users_query = from(users in "users", select: [:id, :name])

      query = users_query |> Composite.apply(composite, %{})
      assert inspect(query) == inspect(users_query)

      query = users_query |> Composite.apply(composite, %{locations: []})
      assert inspect(query) == inspect(users_query)

      query = users_query |> Composite.apply(composite, %{locations: ["Worldwide"]})
      assert inspect(query) == inspect(users_query)

      query = users_query |> Composite.apply(composite, %{order: :username_asc})

      assert inspect(query) ==
               inspect(from(users in "users", select: [:id, :name], order_by: [asc: :name]))

      query = users_query |> Composite.apply(composite, %{order: :department_name_asc})

      assert inspect(query) ==
               inspect(
                 from(users in "users",
                   join: departments in "departments",
                   as: :departments,
                   on: departments.id == users.department_id,
                   select: [:id, :name],
                   order_by: [asc: departments.name]
                 )
               )

      query =
        users_query
        |> Composite.apply(composite, %{
          name: "John",
          company: %{name: "Pear"},
          locations: ["Ukraine", "Costa Rica"],
          unused_param: :something
        })

      assert inspect(query) ==
               inspect(
                 from(users in "users",
                   join: departments in "departments",
                   as: :departments,
                   on: departments.id == users.department_id,
                   join: companies in "companies",
                   as: :companies,
                   on: companies.id == departments.company_id,
                   where: users.name == ^"John",
                   where: companies.name == ^"Pear",
                   where: departments.location in ^["Ukraine", "Costa Rica"],
                   select: [:id, :name]
                 )
               )
    end

    test "prepared composite - on_ignore parameter" do
      composite =
        Composite.new()
        |> Composite.param(:order, &order_by(&1, ^&2), on_ignore: &order_by(&1, :name))

      users_query = from(users in "users")

      assert inspect(users_query |> Composite.apply(composite, %{order: :age})) ==
               inspect(from(users in "users", order_by: [asc: users.age]))

      assert inspect(users_query |> Composite.apply(composite, %{order: nil})) ==
               inspect(from(users in "users", order_by: [asc: users.name]))
    end
  end
end
