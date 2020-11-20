defmodule Composite do
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

  @spec new :: t(any())
  def new, do: %__MODULE__{}

  @spec new(query, params()) :: t(query) when query: any()
  def new(input_query, params) do
    %__MODULE__{params: params, input_query: input_query}
  end

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

  @spec apply(t(query)) :: query when query: any()
  def apply(%__MODULE__{} = composite) do
    apply(nil, composite, nil)
  end

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
