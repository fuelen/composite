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
        |> Composite.param(:active, &where(&1, active: true))
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

  test "dependencies resolution" do
    assert []
           |> Composite.new(%{search: "text"})
           |> Composite.param(:search, fn query, _value -> [:search | query] end,
             requires: [:a, :b]
           )
           |> Composite.dependency(:a, &[:a | &1], requires: :b)
           |> Composite.dependency(:b, &[:b | &1])
           |> Composite.apply() ==
             [:search, :a, :b]
  end

  test "dependency resolver with arity 2 accepts params as a second arg" do
    assert []
           |> Composite.new(%{search: "text"})
           |> Composite.param(:search, &[:search | &1], requires: [:a])
           |> Composite.dependency(:a, &[{:a, &2} | &1])
           |> Composite.apply() == [:search, {:a, %{search: "text"}}]
  end

  test "force require" do
    assert []
           |> Composite.new(%{})
           |> Composite.param(:search, &[:search | &1], requires: [:a])
           |> Composite.dependency(:a, &[:a | &1])
           |> Composite.force_require(:a)
           |> Composite.apply() == [:a]
  end

  test "using undefined dependency" do
    assert_raise ArgumentError,
                 "Unknown dependency: `something`. Please declare this dependency using Composite.dependency/4",
                 fn ->
                   []
                   |> Composite.new(%{search: "text"})
                   |> Composite.param(:search, &[:search | &1], requires: :something)
                   |> Composite.apply()
                 end
  end

  test "set params multiple times" do
    assert_raise ArgumentError, ":params has already been provided", fn ->
      query = []
      composite = Composite.new(nil, %{})
      Composite.apply(query, composite, %{})
    end
  end

  test "set query multiple times" do
    assert_raise ArgumentError, ":input_query has already been provided", fn ->
      query = []
      composite = Composite.new(query, %{})
      Composite.apply(query, composite, %{})
    end
  end

  test ":input_query is not set" do
    assert_raise ArgumentError, ":input_query is not set", fn ->
      nil
      |> Composite.new(%{})
      |> Composite.apply()
    end
  end

  test ":params is not set" do
    assert_raise ArgumentError, ":params is not set", fn ->
      []
      |> Composite.new(nil)
      |> Composite.apply()
    end
  end

  test "unknown options" do
    assert_raise ArgumentError, "Unsupported options: [:onignore]", fn ->
      Composite.new()
      |> Composite.param(:order, &order_by(&1, ^&2), onignore: &order_by(&1, :name))
    end

    assert_raise ArgumentError, "Unsupported options: [:ignore]", fn ->
      Composite.new()
      |> Composite.param(:order, &order_by(&1, ^&2), ignore: fn _ -> true end)
    end
  end

  test "unknown params when strict option is true" do
    composite =
      [strict: true]
      |> Composite.new()
      |> Composite.param(:name, &Map.put(&1, :name, &2))
      |> Composite.param([:company, :name], &Map.put(&1, :company_name, &2))
      |> Composite.param([:company, :type], &Map.put(&1, :company_type, &2))

    assert_raise ArgumentError,
                 "Unknown parameters found under the following paths: [:company, :service]",
                 fn ->
                   Composite.apply(%{}, composite, %{company: %{name: "Pear", service: "IT"}})
                 end

    assert_raise ArgumentError,
                 "Unknown parameters found under the following paths: [:companies]",
                 fn -> Composite.apply(%{}, composite, %{companies: %{}}) end

    assert_raise ArgumentError,
                 "Unknown parameters found under the following paths: [:names]",
                 fn -> Composite.apply(%{}, composite, %{names: %{}}) end
  end

  test "recursively apply Ecto.Queryable.to_query to input query" do
    assert "users"
           |> Composite.new(%{})
           |> Composite.param(:name, &where(&1, name: ^&2))
           |> Ecto.Queryable.to_query()
           |> inspect() == inspect(from(users in "users"))
  end

  test "new/1 with ignore? option" do
    composite = Composite.new(ignore?: &(&1 in [nil, "EMPTY"]))

    assert is_function(composite.ignore?, 1)
    assert composite.ignore?.(nil) == true
    assert composite.ignore?.("EMPTY") == true
    assert composite.ignore?.("John") == false

    params = %{search: "EMPTY", filter: nil, name: "John"}

    query =
      %{base: true}
      |> Composite.new(params, ignore?: &(&1 in [nil, "EMPTY"]))
      |> Composite.param(:search, fn query, _value -> Map.put(query, :search_applied, true) end)
      |> Composite.param(:filter, fn query, _value -> Map.put(query, :filter_applied, true) end)
      |> Composite.param(:name, fn query, _value -> Map.put(query, :name_applied, true) end)
      |> Composite.apply()

    assert Map.get(query, :search_applied) == nil
    assert Map.get(query, :filter_applied) == nil
    assert query.name_applied == true
    assert query.base == true
  end

  test "default ignore? behavior" do
    composite = Composite.new()

    assert is_function(composite.ignore?, 1)
    assert composite.ignore?.(nil) == true
    assert composite.ignore?.("") == true
    assert composite.ignore?.([]) == true
    assert composite.ignore?.(%{}) == true
    assert composite.ignore?.("John") == false

    params = %{search: "", filter: [], name: "John"}

    query =
      %{base: true}
      |> Composite.new(params)
      |> Composite.param(:search, fn query, _value -> Map.put(query, :search_applied, true) end)
      |> Composite.param(:filter, fn query, _value -> Map.put(query, :filter_applied, true) end)
      |> Composite.param(:name, fn query, _value -> Map.put(query, :name_applied, true) end)
      |> Composite.apply()

    assert Map.get(query, :search_applied) == nil
    assert Map.get(query, :filter_applied) == nil
    assert query.name_applied == true
    assert query.base == true
  end

  test "ignore? with operations" do
    params = %{search: " \t ", min_age: 0, max_length: -1, user_ids: []}

    query =
      %{base: true}
      |> Composite.new(params,
        ignore?: fn
          value when is_binary(value) -> String.trim(value) == ""
          value when is_number(value) -> value <= 0
          value when is_list(value) -> value == []
          value -> value in [nil, %{}]
        end
      )
      |> Composite.param(:search, fn query, _value -> Map.put(query, :search_applied, true) end)
      |> Composite.param(:min_age, fn query, _value -> Map.put(query, :min_age_applied, true) end)
      |> Composite.param(:max_length, fn query, _value ->
        Map.put(query, :max_length_applied, true)
      end)
      |> Composite.param(:user_ids, fn query, _value ->
        Map.put(query, :user_ids_applied, true)
      end)
      |> Composite.apply()

    assert query == %{base: true}
  end
end
