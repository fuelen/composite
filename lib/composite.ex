defmodule Composite do
  @moduledoc """
  A utility for writing composable queries.
  """
  import Kernel, except: [apply: 3]
  defstruct param_definitions: [], dep_definitions: %{}, params: nil, input_query: nil
  @type dependency_name :: atom()
  @type param_option(query) ::
          {:requires,
           dependency_name()
           | [dependency_name()]
           | (value :: any -> nil | dependency_name() | [dependency_name()])}
          | {:ignore?, (any() -> boolean())}
          | {:on_ignore, (query -> query)}
  @type dependency_option :: {:requires, dependency_name() | [dependency_name()]}
  @type param_path_item :: any()
  @type apply_param(query) :: (query, any() -> query)
  @type load_dependency(query) :: (query -> query)
  @type params :: Access.t()
  @type t(query) :: %__MODULE__{
          param_definitions: [{[param_path_item()], apply_param(query), [param_option(query)]}],
          dep_definitions: %{
            optional(dependency_name()) => [{load_dependency(query), [dependency_option()]}]
          },
          params: params(),
          input_query: query
        }

  @doc """
  Initializes a `Composite` struct with delayed application of `query` and `params`.

  Must be used with `apply/3`.

      composite =
        Composite.new()
        |> Composite.param(:organization_id, &where(&1, organization_id: ^&2))
        |> Composite.param(:age_more_than, &where(&1, [users], users.age > ^&2))

      params = %{organization_id: 1}

      User
      |> where(active: true)
      |> Composite.apply(composite, params)
      |> Repo.all()
  """
  @spec new :: t(any())
  def new, do: %__MODULE__{}

  @doc """
  Initializes a `Composite` struct with `query` and `params`.

  Must be used with `apply/1`.

  This strategy is useful when working with `Ecto.Query` in pipe-based queries.

      params = %{organization_id: 1}

      User
      |> where(active: true)
      |> Composite.new(params)
      |> Composite.param(:organization_id, &where(&1, organization_id: ^&2))
      |> Composite.param(:age_more_than, &where(&1, [users], users.age > ^&2))
      |> Repo.all()

  Please note, that there is no explicit `Composite.apply/1` call before `Repo.all/1`, because `Composite`
  implements `Ecto.Queryable` protocol.
  """
  @spec new(query, params()) :: t(query) when query: any()
  def new(input_query, params) do
    %__MODULE__{params: params, input_query: input_query}
  end

  @doc """
  Defines a parameter handler.

  Handler is applied to a query when `apply/1` or `apply/3` is invoked.
  All handlers are invoke in the same order as they are defined.

  If the parameter requires dependencies, then they will be loaded before the parameters' handler and only if
  parameter wasn't ignored. Examples with dependencies usage can be found in doc for `dependency/4`

      User
      |> Composite.new(%{location: "Arctic", order: :age_desc})
      |> Composite.param(:location, &where(&1, location: ^&2),
        ignore?: &(&1 in [nil, "WORLDWIDE", ""])
      )
      |> Composite.param(
        :order,
        fn
          query, :name_asc -> query |> order_by(name: :asc)
          query, :age_desc -> query |> order_by(age: :desc)
        end,
        on_ignore: &order_by(&1, inserted_at: :desc)
      )

  """
  @spec param(t(query), param_path_item() | [param_path_item()], apply_param(query), [
          param_option(query)
        ]) :: t(query)
        when query: any()
  def param(
        %__MODULE__{param_definitions: param_definitions} = composite,
        path,
        func,
        opts \\ []
      )
      when is_function(func, 2) do
    %{composite | param_definitions: [{List.wrap(path), func, opts} | param_definitions]}
  end

  @doc """
  Defines a dependency loader.

  Dependency is an instruction which is being applied lazily to a query.
  The same dependency can be required by many parameters, but it will be invoked only once.
  Dependency can depend on other dependency.

  Useful for joining tables via SQL.

      User
      |> Composite.new(%{org_type: :nonprofit, is_org_closed: false})
      |> Composite.param(:is_org_closed, &where(&1, [orgs: orgs], orgs.closed == ^&2), requires: :orgs)
      |> Composite.param(:org_type, &where(&1, [orgs: orgs], orgs.type == ^&2), requires: :orgs)
      |> Composite.dependency(
        :orgs,
        &join(&1, :inner, [users], orgs in assoc(users, :org), as: :orgs)
      )
  """
  @spec dependency(t(query), dependency_name(), load_dependency(query), [dependency_option]) ::
          t(query)
        when query: any()
  def dependency(
        %__MODULE__{dep_definitions: dep_definitions} = composite,
        dependency,
        func,
        opts \\ []
      )
      when is_function(func, 1) do
    %{composite | dep_definitions: Map.put(dep_definitions, dependency, {func, opts})}
  end

  @doc """
  Applies handlers to query.

  Used when composite is defined with `new/2`
  """
  @spec apply(t(query)) :: query when query: any()
  def apply(%__MODULE__{} = composite) do
    apply(nil, composite, nil)
  end

  @doc """
  Applies handlers to query.

  Used when composite is defined with `new/0`
  """
  @spec apply(query, t(query), params()) :: query when query: any()
  def apply(
        input_query,
        %__MODULE__{} = composite,
        params
      ) do
    composite =
      composite
      |> set_once!(:input_query, input_query)
      |> set_once!(:params, params)

    {query, _loaded_deps} =
      composite.param_definitions
      |> Enum.reverse()
      |> Enum.reduce({composite.input_query, MapSet.new()}, fn {path, func, opts},
                                                               {query, loaded_deps} ->
        value = get_in(composite.params, path)

        ignore? = Keyword.get(opts, :ignore?, &is_nil/1)

        if ignore?.(value) do
          on_ignore = Keyword.get(opts, :on_ignore, &Function.identity/1)
          {on_ignore.(query), loaded_deps}
        else
          required_deps =
            opts
            |> Keyword.get(:requires)
            |> case do
              requires when is_function(requires, 1) -> requires.(value)
              requires -> requires
            end
            |> List.wrap()

          {query, loaded_deps} =
            load_dependencies(query, composite.dep_definitions, loaded_deps, required_deps)

          {func.(query, value), loaded_deps}
        end
      end)

    query
  end

  defp set_once!(composite, key, value) do
    case {value, Map.fetch!(composite, key)} do
      {nil, nil} -> raise "#{inspect(key)} is not set"
      {nil, _} -> composite
      {_, nil} -> Map.replace!(composite, key, value)
      {_, _} -> raise "#{inspect(key)} has already been provided"
    end
  end

  defp load_dependencies(query, deps_definitions, loaded_deps, required_deps) do
    deps_to_load = required_deps |> MapSet.new() |> MapSet.difference(loaded_deps)

    {query, loaded_deps} =
      Enum.reduce(deps_to_load, {query, loaded_deps}, fn dependency_name, {query, loaded_deps} ->
        {loader, opts} =
          case Map.fetch(deps_definitions, dependency_name) do
            {:ok, result} ->
              result

            :error ->
              raise "unable to load dependency `#{dependency_name}`"
          end

        required_deps = opts |> Keyword.get(:requires) |> List.wrap()

        {query, loaded_deps} =
          query |> load_dependencies(deps_definitions, loaded_deps, required_deps)

        {loader.(query), loaded_deps}
      end)

    {query, MapSet.union(loaded_deps, deps_to_load)}
  end

  if Code.ensure_loaded?(Ecto.Queryable) do
    defimpl Ecto.Queryable do
      def to_query(composite) do
        Composite.apply(composite)
      end
    end
  end
end
