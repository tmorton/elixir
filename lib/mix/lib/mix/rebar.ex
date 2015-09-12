defmodule Mix.Rebar do
  @moduledoc false

  @doc """
  Returns the path supposed to host the local copy of rebar.
  """
  def local_rebar_path(manager) do
    Path.join(Mix.Utils.mix_home, Atom.to_string(manager))
  end

  @doc """
  Returns the path to the global copy of rebar, if one exists.
  """
  def global_rebar_cmd(manager) do
    wrap_cmd System.find_executable(Atom.to_string(manager))
  end

  @doc """
  Returns the path to the local copy of rebar, if one exists.
  """
  def local_rebar_cmd(manager) do
    cmd = local_rebar_path(manager)
    wrap_cmd(if File.regular?(cmd), do: cmd)
  end

  @doc """
  Returns the path to the available rebar command.
  """
  def rebar_cmd(manager) do
    global_rebar_cmd(manager) || local_rebar_cmd(manager)
  end

  @doc """
  Loads the rebar.config and evaluates rebar.config.script if it
  exists in the given directory.
  """
  def load_config(dir) do
    config_path = Path.join(dir, "rebar.config")
    script_path = Path.join(dir, "rebar.config.script")

    config = case :file.consult(config_path) do
      {:ok, config} ->
        config
      {:error, :enoent} ->
        []
      {:error, error} ->
        reason = :file.format_error(error)
        Mix.raise "Error consulting rebar config #{config_path}: #{reason}"
    end

    if File.exists?(script_path) do
      eval_script(script_path, config)
    else
      config
    end
  end

  @doc """
  Parses the dependencies in given rebar.config to Mix's dependency format.
  """
  def deps(app, config, overrides) do
    # We don't have to handle rebar3 profiles because dependencies
    # are always in the default profile which cannot be customized
    config = apply_overrides(app, config, overrides)
    if deps = config[:deps] do
      Enum.map(deps, &parse_dep/1)
    else
      []
    end
  end

  @doc """
  Runs `fun` for the given config and for each `sub_dirs` in the
  given rebar config.
  """
  def recur(config, fun) when is_binary(config) do
    recur(load_config(config), fun)
  end

  def recur(config, fun) do
    subs = (config[:sub_dirs] || [])
     |> Enum.map(&Path.wildcard(&1))
     |> Enum.concat
     |> Enum.filter(&File.dir?(&1))
     |> Enum.map(&recur(&1, fun))
     |> Enum.concat

    [fun.(config)|subs]
  end

  defp parse_dep(app) when is_atom(app) do
    parse_dep({app, nil})
  end

  defp parse_dep({app, req}) when is_list(req) do
    {app, List.to_string(req)}
  end

  defp parse_dep({app, source}) when is_tuple(source) do
    parse_dep({app, nil, source, []})
  end

  defp parse_dep({app, req, source}) do
    parse_dep({app, req, source, []})
  end

  defp parse_dep({app, req, source, opts}) do
    [scm, url | source] = Tuple.to_list(source)
    mix_opts = [{scm, to_string(url)}]

    ref =
      case source do
        [""|_]                -> [branch: "HEAD"]
        [{:branch, branch}|_] -> [branch: to_string(branch)]
        [{:tag, tag}|_]       -> [tag: to_string(tag)]
        [{:ref, ref}|_]       -> [ref: to_string(ref)]
        [ref|_]               -> [ref: to_string(ref)]
        _                     -> []
      end

    mix_opts = mix_opts ++ ref

    if :proplists.get_value(:raw, opts, false) do
      mix_opts = mix_opts ++ [compile: false]
    end

    {app, compile_req(req), mix_opts}
  end

  defp compile_req(nil) do
    nil
  end

  defp compile_req(req) do
    case Regex.compile(List.to_string(req)) do
      {:ok, re} ->
        re
      {:error, reason} ->
        Mix.raise "Unable to compile version regex: \"#{req}\", #{reason}"
    end
  end

  defp eval_script(script_path, config) do
    script = Path.basename(script_path) |> String.to_char_list

    result = File.cd!(Path.dirname(script_path), fn ->
      :file.script(script, eval_binds(CONFIG: config, SCRIPT: script))
    end)

    case result do
      {:ok, config} ->
        config
      {:error, error} ->
        reason = :file.format_error(error)
        Mix.shell.error("Error evaluating rebar config script #{script_path}: #{reason}")
        Mix.shell.error("You may solve this issue by adding rebar as a dependency to your project")
        Mix.shell.error("Any dependency defined in the script won't be available " <>
                        "unless you add them to your Mix project")
        config
    end
  end

  defp eval_binds(binds) do
    Enum.reduce(binds, :erl_eval.new_bindings, fn ({k, v}, binds) ->
      :erl_eval.add_binding(k, v, binds)
    end)
  end

  defp wrap_cmd(nil), do: nil
  defp wrap_cmd(rebar) do
    if match?({:win32, _}, :os.type) and not String.ends_with?(rebar, ".cmd") do
      "escript.exe \"#{rebar}\""
    else
      rebar
    end
  end

  defp apply_overrides(app, config, overrides) do
    # Inefficient. We want the order we get here though.

    config =
      Enum.reduce(overrides, config, fn
        {:override, overrides}, config ->
          Enum.reduce(overrides, config, fn {key, value}, config ->
            Dict.put(config, key, value)
          end)
        _, config ->
          config
       end)

    config =
      Enum.reduce(overrides, config, fn
        {:override, oapp, overrides}, config when oapp == app ->
          Enum.reduce(overrides, config, fn {key, value}, config ->
            Dict.put(config, key, value)
          end)
        _, config ->
          config
      end)

    Enum.reduce(overrides, config, fn
      {:add, oapp, overrides}, config when oapp == app ->
        Enum.reduce(overrides, config, fn {key, value}, config ->
          old_value = Dict.get(config, key, [])
          Dict.put(config, key, value ++ old_value)
      end)
      _, config ->
        config
    end)
  end
end
