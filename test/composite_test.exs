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

  test "dependencies load in declaration order of :requires" do
    # MapSet.new([:a, :b, :c, :d]) iterates as [:c, :a, :b, :d] — so a
    # MapSet-based implementation would yield [:search, :d, :b, :a, :c].
    # Declaration order must be preserved regardless.
    result =
      []
      |> Composite.new(%{search: "x"})
      |> Composite.param(:search, &[:search | &1], requires: [:a, :b, :c, :d])
      |> Composite.dependency(:a, &[:a | &1])
      |> Composite.dependency(:b, &[:b | &1])
      |> Composite.dependency(:c, &[:c | &1])
      |> Composite.dependency(:d, &[:d | &1])
      |> Composite.apply()

    assert result == [:search, :d, :c, :b, :a]
  end

  test "dependency resolver with arity 2 accepts params as a second arg" do
    assert []
           |> Composite.new(%{search: "text"})
           |> Composite.param(:search, &[:search | &1], requires: [:a])
           |> Composite.dependency(:a, &[{:a, &2} | &1])
           |> Composite.apply() == [:search, {:a, %{search: "text"}}]
  end

  test "duplicate param paths chain — all handlers run in declaration order" do
    result =
      []
      |> Composite.new(%{search: "x"})
      |> Composite.param(:search, &[:first | &1])
      |> Composite.param(:search, &[:second | &1])
      |> Composite.param(:search, &[:third | &1])
      |> Composite.apply()

    assert result == [:third, :second, :first]
  end

  test "force require" do
    assert []
           |> Composite.new(%{})
           |> Composite.param(:search, &[:search | &1], requires: [:a])
           |> Composite.dependency(:a, &[:a | &1])
           |> Composite.force_require(:a)
           |> Composite.apply() == [:a]
  end

  test "dependency/4 warns and keeps last definition when declared twice" do
    {result, warning} =
      ExUnit.CaptureIO.with_io(:stderr, fn ->
        []
        |> Composite.new(%{search: "x"})
        |> Composite.param(:search, &[:search | &1], requires: :orgs)
        |> Composite.dependency(:orgs, &[:old | &1])
        |> Composite.dependency(:orgs, &[:new | &1])
        |> Composite.apply()
      end)

    assert result == [:search, :new]

    [first_line | _] = String.split(warning, "\n")

    assert first_line ==
             "warning: dependency :orgs is already defined; the previous loader will be overwritten"
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

  test "strict: true does not raise when all params are known (happy path)" do
    composite =
      [strict: true]
      |> Composite.new()
      |> Composite.param(:name, &Map.put(&1, :name, &2))
      |> Composite.param([:company, :name], &Map.put(&1, :company_name, &2))
      |> Composite.param([:company, :type], &Map.put(&1, :company_type, &2))

    assert Composite.apply(%{}, composite, %{
             name: "John",
             company: %{name: "Pear", type: "LLC"}
           }) == %{name: "John", company_name: "Pear", company_type: "LLC"}
  end

  test "strict: true supports keyword list params" do
    composite =
      [strict: true]
      |> Composite.new()
      |> Composite.param(:name, &Map.put(&1, :name, &2))

    assert Composite.apply(%{}, composite, name: "John") == %{name: "John"}

    assert_raise ArgumentError,
                 "Unknown parameters found under the following paths: [:surname]",
                 fn -> Composite.apply(%{}, composite, name: "John", surname: "Doe") end
  end

  test "strict: true accepts nil at a known nested parameter path" do
    composite =
      [strict: true]
      |> Composite.new()
      |> Composite.param([:company, :name], &Map.put(&1, :company_name, &2))

    assert Composite.apply(%{}, composite, %{company: nil}) == %{}
  end

  test "strict: true accepts a value when both its path and a nested path are declared" do
    composite =
      [strict: true]
      |> Composite.new()
      |> Composite.param(:company, &Map.put(&1, :company, &2))
      |> Composite.param([:company, :name], &Map.put(&1, :company_name, &2))

    assert Composite.apply(%{}, composite, %{company: %{name: "Pear", type: "LLC"}}) == %{
             company: %{name: "Pear", type: "LLC"},
             company_name: "Pear"
           }
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

  describe "apply_tagged/3" do
    test "returns :unchanged when no handler fires" do
      composite =
        Composite.new()
        |> Composite.param(:name, &[:name | &1])

      assert Composite.apply_tagged([], composite, %{}) == :unchanged
    end

    test "returns {:changed, query} when a handler fires" do
      composite =
        Composite.new()
        |> Composite.param(:name, &[:name | &1])

      assert Composite.apply_tagged([], composite, %{name: "John"}) == {:changed, [:name]}
    end
  end

  describe "apply_tagged/1" do
    test "returns :unchanged when params are empty and no handlers fire" do
      result =
        []
        |> Composite.new(%{})
        |> Composite.param(:name, &[:name | &1])
        |> Composite.param(:company, &[:company | &1])
        |> Composite.apply_tagged()

      assert result == :unchanged
    end

    test "returns {:changed, query} when at least one handler fires" do
      result =
        []
        |> Composite.new(%{name: "John"})
        |> Composite.param(:name, &[:name | &1])
        |> Composite.param(:company, &[:company | &1])
        |> Composite.apply_tagged()

      assert result == {:changed, [:name]}
    end

    test "on_ignore counts as modification (input != applied)" do
      result =
        []
        |> Composite.new(%{})
        |> Composite.param(:order, &[&2 | &1], on_ignore: &[:default | &1])
        |> Composite.apply_tagged()

      assert result == {:changed, [:default]}
    end

    test "raises when input_query or params are not set (inherits apply/1 preconditions)" do
      assert_raise ArgumentError, ":input_query is not set", fn ->
        Composite.new() |> Composite.apply_tagged()
      end

      assert_raise ArgumentError, ":params is not set", fn ->
        [] |> Composite.new(nil) |> Composite.apply_tagged()
      end
    end
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

    assert query == %{name_applied: true, base: true}
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

    assert query == %{name_applied: true, base: true}
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
