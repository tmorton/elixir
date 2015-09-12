defmodule Mix.Tasks.Local.Rebar do
  use Mix.Task

  @rebar2_url "http://s3.hex.pm/rebar"
  @rebar3_url "http://s3.hex.pm/rebar3"
  @shortdoc  "Install rebar locally"

  @moduledoc """
  Fetch a copy of rebar or rebar3 from the given path or url. It fetches
  it from #{@rebar2_url} and #{@rebar3_url} unless another path is specified.

  The local copy is stored in your MIX_HOME (defaults to ~/.mix).
  This version of rebar will be used as required by `mix deps.compile`.

  ## Command line options

    * `rebar PATH` - specify a path or url for rebar

    * `rebar3 PATH` - specify a path or url for rebar3

    * `--force` - forces installation without a shell prompt; primarily
      intended for automation in build systems like make
  """
  @spec run(OptionParser.argv) :: true
  def run(argv) do
    {opts, argv, _} = OptionParser.parse(argv, switches: [force: :boolean])

    case argv do
      [] ->
       do_install(:rebar, @rebar2_url, opts)
       do_install(:rebar3, @rebar3_url, opts)
      ["rebar", path | _] ->
       do_install(:rebar, path, opts)
      ["rebar3", path | _] ->
       do_install(:rebar3, path, opts)
    end
  end

  defp do_install(manager, path, opts) do
    local = Mix.Rebar.local_rebar_path(manager)

    if opts[:force] || Mix.Utils.can_write?(path) do
      case Mix.Utils.read_path(path, opts) do
        {:ok, binary} ->
          File.mkdir_p!(Path.dirname(local))
          File.write!(local, binary)
          File.chmod!(local, 0o755)
          Mix.shell.info [:green, "* creating ", :reset, Path.relative_to_cwd(local)]
        :badname ->
          Mix.raise "Expected #{inspect path} to be a url or a local file path"
        {:local, message} ->
          Mix.raise message
        {:remote, message} ->
          Mix.raise """
          #{message}

          Could not fetch #{manager} at:

              #{path}

          Please download the file above manually to your current directory and run:

              mix local.rebar #{manager} ./#{Path.basename(local)}
          """
      end
    end

    true
  end
end
