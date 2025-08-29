defmodule Composite do
  @moduledoc """
  A utility for writing dynamic queries.

  It allows getting rid of some boilerplate when building a query based on input parameters.

      params = %{search_query: "John Doe"}

      User
      |> where(active: true)
      |> Composite.new(params)
      |> Composite.param(:org_id, &filter_by_org_id/2)
      |> Composite.param(:search_query, &search_by_full_name/2)
      |> Composite.param(:org_name, &filter_by_org_name/2, requires: :org)
      |> Composite.param(:org_type, &filter_by_org_type/2, requires: :org)
      |> Composite.dependency(:org, &join_orgs/1)
      |> Repo.all()

  Even though most of the examples in this doc use `Ecto`, Composite itself is not limited only to it.
  `Ecto` is an optional dependency and it is present only for having an implementation of `Ecto.Queryable` OOTB.
  You're able to use Composite with any Elixir term, as it is just an advanced wrapper around `Enum.reduce/3`.
  """
  import Kernel, except: [apply: 3]

  @derive {Inspect,
           optional: [
             :param_definitions,
             :dep_definitions,
             :params,
             :input_query,
             :required_deps,
             :strict,
             :ignore?
           ]}
  defstruct param_definitions: [],
            dep_definitions: %{},
            params: nil,
            input_query: nil,
            required_deps: [],
            strict: false,
            ignore?: &__MODULE__.default_ignore?/1

  @type dependency_name :: atom()
  @type dependencies ::
          nil
          | dependency_name()
          | [dependency_name()]
  @type param_option(query) ::
          {:requires, dependencies() | (value :: any -> dependencies())}
          | {:ignore?, (any() -> boolean())}
          | {:on_ignore, (query -> query)}
          | {:ignore_requires, dependencies()}
  @type dependency_option :: {:requires, dependencies()}
  @type option :: {:strict, boolean()} | {:ignore?, (any() -> boolean())}
  @type param_path_item :: any()
  @type apply_fun(query) :: (query, value :: any() -> query) | (query -> query)
  @type load_dependency(query) :: (query -> query) | (query, params() -> query)
  @type params :: Access.t()
  @type t(query) :: %__MODULE__{
          param_definitions: [{[param_path_item()], apply_fun(query), [param_option(query)]}],
          dep_definitions: %{
            optional(dependency_name()) => [{load_dependency(query), [dependency_option()]}]
          },
          required_deps: [dependency_name()],
          params: params() | nil,
          input_query: query,
          strict: boolean(),
          ignore?: (any() -> boolean())
        }

  @doc """
  Default ignore function.

  Returns `true` if the value is `nil`, `""`, `[]`, or `%{}`.
  """
  @spec default_ignore?(any()) :: boolean()
  def default_ignore?(value) do
    value in [nil, "", [], %{}]
  end

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

  ### Options

  * `:strict` - if `true`, then `apply/3` will raise an error if the caller provides params that are not defined in `Composite.param/4`.
  Defaults to `false`.
  * `:ignore?` - a function that determines if a value should be considered "empty" and ignored by default when no explicit `:ignore?` option is provided in `param/4`.
  Defaults to `&Composite.default_ignore?/1` which checks if the value is in `[nil, "", [], %{}]`.
  """
  @spec new([option]) :: t(any())
  def new(opts \\ []) do
    %__MODULE__{
      strict: Keyword.get(opts, :strict, false),
      ignore?: Keyword.get(opts, :ignore?, &__MODULE__.default_ignore?/1)
    }
  end

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

  ### Options

  * `:strict` - if `true`, then `apply/3` will raise an error if the caller provides params that are not defined in `Composite.param/4`.
  Defaults to `false`.
  * `:ignore?` - a function that determines if a value should be considered "empty" and ignored by default when no explicit `:ignore?` option is provided in `param/4`.
  Defaults to `&Composite.default_ignore?/1` which checks if the value is in `[nil, "", [], %{}]`.
  """
  @spec new(query, params(), [option]) :: t(query) when query: any()
  def new(input_query, params, opts \\ []) do
    %__MODULE__{
      params: params,
      input_query: input_query,
      strict: Keyword.get(opts, :strict, false),
      ignore?: Keyword.get(opts, :ignore?, &__MODULE__.default_ignore?/1)
    }
  end

  @doc """
  Defines a parameter handler.

  Handler is applied to a query when `apply/1` or `apply/3` is invoked.
  All handlers are invoke in the same order as they are defined.

  If the parameter requires dependencies, then they will be loaded before the parameters' handler and only if
  parameter wasn't ignored. Examples with dependencies usage can be found in doc for `dependency/4`

      params = %{location: "Arctic", order: :age_desc}

      User
      |> Composite.new(params)
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

  If input parameters have nested maps (or any other key-based data structure):

      params = %{filter: %{name: "John"}}

      User
      |> Composite.new(params)
      |> Composite.param([:filter, :name], &where(&1, name: ^&2))

  ### Options

  * `:ignore?` - if function returns `true`, then handler `t:apply_fun/1` won't be applied.
  Default value is `composite.ignore?`, which can be customized via the `:ignore?` option when creating the composite.
  * `:on_ignore` - a function that will be applied instead of `t:apply_fun/1` if value is ignored.
  Defaults to `Function.identity/1`.
  * `:requires` - points to the dependencies which has to be loaded before calling `t:apply_fun/1`.
  It is, also, possible to specify dependencies dynamically based on a value of the parameter by
  passing a function. The latter function will always receive not ignored values.
  Defaults to `nil` (which is equivalent to `[]`).
  * `:ignore_requires` - points to the dependencies which has to be loaded when value is ignored. May be needed
  for custom `:on_ignore` implementation.
  """
  @spec param(t(query), param_path_item() | [param_path_item()], apply_fun(query), [
          param_option(query)
        ]) :: t(query)
        when query: any()
  def param(
        %__MODULE__{param_definitions: param_definitions} = composite,
        path,
        func,
        opts \\ []
      )
      when is_function(func, 1) or is_function(func, 2) do
    ensure_unknown_opts_absent!(opts, [:ignore?, :on_ignore, :requires, :ignore_requires])
    %{composite | param_definitions: [{List.wrap(path), func, opts} | param_definitions]}
  end

  @doc """
  Defines a dependency loader.

  Dependency is an instruction which is being applied lazily to a query.
  The same dependency can be required by many parameters, but it will be invoked only once.
  Dependency can depend on other dependency.

  Useful for joining tables.

      params = %{org_type: :nonprofit, is_org_closed: false}

      User
      |> Composite.new(params)
      |> Composite.param(:is_org_closed, &where(&1, [orgs: orgs], orgs.closed == ^&2), requires: :orgs)
      |> Composite.param(:org_type, &where(&1, [orgs: orgs], orgs.type == ^&2), requires: :orgs)
      |> Composite.dependency(:orgs, &join(&1, :inner, [users], orgs in assoc(users, :org), as: :orgs))

  It is also possible to require a dependency only if specific value is set. In example below dependency `:phone` will be
  loaded only if value of `:search` param starts from `+` sign

      composite
      |> Composite.param(
        :search,
        fn
          query, "+" <> _ = phone_number -> where(query, [phones: phones], phones.number == ^phone_number)
          query, query_string -> where(query, [records], ilike(records.text, ^query_string))
        end,
        requires: fn
          "+" <> _ -> :phone
          _ -> nil
        end
      )
      |> Composite.dependency(:phone, &join(&1, :inner, [records], phones in assoc(records, :phone), as: :phones))

  When `loader` function has arity 2, then all parameters are passed in the second argument.

  ### Options

  * `:requires` - allows to set dependencies for current dependency.
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
      when is_function(func, 1) or is_function(func, 2) do
    ensure_unknown_opts_absent!(opts, [:requires])
    %{composite | dep_definitions: Map.put(dep_definitions, dependency, {func, opts})}
  end

  @doc """
  Applies handlers to query.

  Used when composite is defined with `new/2`.

  If used with `Ecto`, then calling this function is not necessary,
  as `Composite` implements `Ecto.Queryable` protocol, so applying will be done automatically when it is needed.
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

    maybe_raise_on_unknown_params(composite)

    {query, loaded_deps} =
      load_dependencies(
        composite.input_query,
        composite.params,
        composite.dep_definitions,
        MapSet.new(),
        composite.required_deps
      )

    {query, _loaded_deps} =
      composite.param_definitions
      |> Enum.reverse()
      |> Enum.reduce({query, loaded_deps}, fn {path, func, opts}, {query, loaded_deps} ->
        value = get_in(composite.params, path)

        ignore? = Keyword.get(opts, :ignore?, composite.ignore?)

        if ignore?.(value) do
          on_ignore =
            case Keyword.fetch(opts, :on_ignore) do
              {:ok, on_ignore} when is_function(on_ignore, 1) -> on_ignore
              :error -> &Function.identity/1
            end

          required_deps = opts |> Keyword.get(:ignore_requires) |> List.wrap()

          {query, loaded_deps} =
            load_dependencies(
              query,
              composite.params,
              composite.dep_definitions,
              loaded_deps,
              required_deps
            )

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
            load_dependencies(
              query,
              composite.params,
              composite.dep_definitions,
              loaded_deps,
              required_deps
            )

          case func do
            func when is_function(func, 1) -> {func.(query), loaded_deps}
            func when is_function(func, 2) -> {func.(query, value), loaded_deps}
          end
        end
      end)

    query
  end

  @doc """
  Forces loading dependency even if it is not required by `params`.
  """
  @spec force_require(t(query), dependency_name() | [dependency_name()]) :: t(query)
        when query: any()
  def force_require(
        %__MODULE__{required_deps: required_deps} = composite,
        dependency_or_dependencies
      ) do
    dependencies = List.wrap(dependency_or_dependencies)
    %__MODULE__{composite | required_deps: dependencies ++ required_deps}
  end

  defp ensure_unknown_opts_absent!([], _allowlist), do: :ok

  defp ensure_unknown_opts_absent!(opts, allowlist) do
    diff =
      MapSet.difference(
        MapSet.new(Keyword.keys(opts)),
        MapSet.new(allowlist)
      )

    case MapSet.to_list(diff) do
      [] -> :ok
      unknown_keys -> raise ArgumentError, "Unsupported options: #{inspect(unknown_keys)}"
    end
  end

  defp set_once!(composite, key, value) do
    case {value, Map.fetch!(composite, key)} do
      {nil, nil} -> raise ArgumentError, "#{inspect(key)} is not set"
      {nil, _} -> composite
      {_, nil} -> Map.replace!(composite, key, value)
      {_, _} -> raise ArgumentError, "#{inspect(key)} has already been provided"
    end
  end

  defp load_dependencies(query, _params, _deps_definitions, loaded_deps, [] = _required_deps) do
    {query, loaded_deps}
  end

  defp load_dependencies(query, params, deps_definitions, loaded_deps, required_deps) do
    deps_to_load = required_deps |> MapSet.new() |> MapSet.difference(loaded_deps)

    Enum.reduce(deps_to_load, {query, loaded_deps}, fn dependency_name, {query, loaded_deps} ->
      if dependency_name in loaded_deps do
        {query, loaded_deps}
      else
        {loader, opts} =
          case Map.fetch(deps_definitions, dependency_name) do
            {:ok, result} ->
              result

            :error ->
              raise ArgumentError,
                    "Unknown dependency: `#{dependency_name}`. Please declare this dependency using Composite.dependency/4"
          end

        required_deps = opts |> Keyword.get(:requires) |> List.wrap()

        {query, loaded_deps} =
          load_dependencies(query, params, deps_definitions, loaded_deps, required_deps)

        query =
          case loader do
            loader when is_function(loader, 1) -> loader.(query)
            loader when is_function(loader, 2) -> loader.(query, params)
          end

        {query, MapSet.put(loaded_deps, dependency_name)}
      end
    end)
  end

  defp maybe_raise_on_unknown_params(composite) do
    if composite.strict and
         ((is_map(composite.params) and not is_struct(composite.params)) or
            Keyword.keyword?(composite.params)) do
      paths = Enum.map(composite.param_definitions, &elem(&1, 0))

      maybe_raise_on_unknown_params(composite.params, paths, [])
    end

    :noop
  end

  defp maybe_raise_on_unknown_params(params, paths, current_path) do
    paths = Enum.group_by(paths, &hd/1, &tl/1)

    absent_paths =
      Enum.flat_map(params, fn {key, value} ->
        case Enum.find(paths, fn {path_key, _subpaths} ->
               path_key == key
             end) do
          nil ->
            [current_path ++ [key]]

          {^key, [[]]} ->
            []

          {^key, subpaths} ->
            maybe_raise_on_unknown_params(value, subpaths, current_path ++ [key])
            []
        end
      end)

    if absent_paths != [] do
      raise ArgumentError,
            "Unknown parameters found under the following paths: #{Enum.map_join(absent_paths, ", ", &inspect/1)}"
    end
  end

  if Code.ensure_loaded?(Ecto.Queryable) do
    defimpl Ecto.Queryable do
      def to_query(composite) do
        case Composite.apply(composite) do
          %Ecto.Query{} = query -> query
          other -> Ecto.Queryable.to_query(other)
        end
      end
    end
  end
end
