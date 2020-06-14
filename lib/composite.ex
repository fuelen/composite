defmodule Composite do
  defstruct param_definitions: [], dep_definitions: %{}, params: nil, input_query: nil
  @type dependency_name :: atom()
  @type param_option ::
          {:requires, dependency_name() | [dependency_name()]} | {:ignore?, (any() -> boolean())}
  @type dependency_option :: {:requires, dependency_name() | [dependency_name()]}
  @type param_path_item :: any()
  @type query :: any()
  @type apply_param :: (query(), any() -> query())
  @type load_dependency :: (query() -> query())
  @type params :: Access.t()
  @type t :: %__MODULE__{
          param_definitions: [{[param_path_item()], apply_param(), [param_option()]}],
          dep_definitions: %{
            optional(dependency_name()) => [{load_dependency(), [dependency_option()]}]
          },
          params: params(),
          input_query: query()
        }

  @spec new(query(), params()) :: t()
  def new(input_query \\ nil, params \\ nil) do
    %__MODULE__{params: params, input_query: input_query}
  end

  @spec param(t(), param_path_item() | [param_path_item()], apply_param, [param_option]) :: t()
  def param(
        %__MODULE__{param_definitions: param_definitions} = composite,
        path,
        func,
        opts \\ []
      )
      when is_function(func, 2) do
    %{composite | param_definitions: [{List.wrap(path), func, opts} | param_definitions]}
  end

  @spec dependency(t(), dependency_name(), load_dependency, [dependency_option]) :: t()
  def dependency(
        %__MODULE__{dep_definitions: dep_definitions} = flexible_query,
        dependency,
        func,
        opts \\ []
      )
      when is_function(func, 1) do
    %{flexible_query | dep_definitions: Map.put(dep_definitions, dependency, {func, opts})}
  end

  @spec apply(t(), query(), params()) :: query()
  def apply(
        %__MODULE__{} = composite,
        input_query \\ nil,
        params \\ nil
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
          {query, loaded_deps}
        else
          {query, loaded_deps} =
            load_dependencies(query, composite.dep_definitions, loaded_deps, opts)

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

  defp load_dependencies(query, deps_definitions, loaded_deps, opts) do
    required_deps = opts |> Keyword.get(:requires) |> List.wrap() |> MapSet.new()
    deps_to_load = MapSet.difference(required_deps, loaded_deps)

    {query, loaded_deps} =
      Enum.reduce(deps_to_load, {query, loaded_deps}, fn dependency_name, {query, loaded_deps} ->
        {loader, opts} =
          case Map.fetch(deps_definitions, dependency_name) do
            {:ok, result} ->
              result

            :error ->
              raise "unable to load dependency `#{dependency_name}`"
          end

        {query, loaded_deps} = query |> load_dependencies(deps_definitions, loaded_deps, opts)
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
