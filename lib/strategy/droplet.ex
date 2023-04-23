defmodule Cluster.Strategy.Droplet do
  @moduledoc """
  Digital Ocean Droplet strategy for libcluster
  """

  use GenServer
  use Cluster.Strategy

  alias Cluster.Logger
  alias Cluster.Strategy
  alias Cluster.Strategy.State

  @interval 5_000
  @api_url "https://api.digitalocean.com/v2/droplets"
  @metadata_url "http://169.254.169.254/metadata/v1/"

  @doc """
  Starts a GenServer to poll the Digital Ocean API for a list of nodes to add to the cluster.

  Any nodes currently in the cluster that are no longer returned from the API will be removed from
  the cluster. Filtering can be done by tag name or Droplet name, but not both. Otherwise an
  exception will be raised. The current Droplet will be excluded so the node doesn't try to
  connect to itself.

  If there is an issue making the API request, the node list is kept as is with no changes. This
  is because we don't want all the nodes tp disconnect from each other if the Digital Ocean API
  goes down.
  """
  def start_link(opts) do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init([%State{meta: nil} = state]), do: {:ok, poll(%State{state | meta: MapSet.new()})}
  def init([%State{} = state]), do: {:ok, poll(state)}

  @impl true
  def handle_info(:timeout, state), do: handle_info(:poll, state)
  def handle_info(:poll, state), do: {:noreply, poll(state)}
  def handle_info(_, state), do: {:noreply, state}

  defp poll(%State{config: config} = state) do
    interval = Keyword.get(config, :polling_interval, @interval)
    token = Keyword.fetch!(config, :token)
    tag_name = Keyword.get(config, :tag_name)
    name = Keyword.get(config, :name)

    filters = Enum.filter([tag_name: tag_name, name: name], fn {_, v} -> !is_nil(v) end)
    url = "#{@api_url}?#{URI.encode_query(filters)}"
    id = get_metadata("id")

    if filters[:tag_name] && filters[:name] do
      raise ArgumentError, "Cannot specify both `tag_name` and `name` config values"
    end

    nodes =
      case get_nodes(state, url, token, id) do
        :error ->
          # Something went wrong with the API, don't add or remove any nodes
          state.meta

        nodes ->
          MapSet.new(nodes)
      end

    removed = MapSet.difference(state.meta, nodes) |> MapSet.to_list()

    nodes =
      case Strategy.disconnect_nodes(state.topology, state.disconnect, state.list_nodes, removed) do
        :ok ->
          nodes

        {:error, bad_nodes} ->
          # Add back the nodes which should have been removed but couldn't be
          Enum.reduce(bad_nodes, nodes, fn {n, _}, acc -> MapSet.put(acc, n) end)
      end

    nodes =
      case Cluster.Strategy.connect_nodes(state.topology, state.connect, state.list_nodes, MapSet.to_list(nodes)) do
        :ok ->
          nodes

        {:error, bad_nodes} ->
          # Remove the nodes which should have been added but couldn't be
          Enum.reduce(bad_nodes, nodes, fn {n, _}, acc -> MapSet.delete(acc, n) end)
      end

    Process.send_after(self(), :poll, interval)

    %{state | meta: nodes}
  end

  @doc """
  Makes a request to the Digital Ocean API for a list of droplets and recurses through the pages.

  Will return a parsed list of node names derived from the droplet objects. Expects a full URL and
  a valid access token to be passed. Logs a warning and returns `:error` if the API didn't return
  a successful response.
  """
  def get_nodes(%State{} = state, url, token, id) do
    headers = [
      {to_charlist("Content-Type"), to_charlist("application/json")},
      {to_charlist("Authorization"), to_charlist("Bearer #{token}")}
    ]

    ssl = [
      verify: :verify_peer,
      depth: 99,
      cacerts: :certifi.cacerts(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    case :httpc.request(:get, {to_charlist(url), headers}, [ssl: ssl], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        body = Jason.decode!(body)
        droplets = Map.get(body, "droplets", [])
        nodes = to_node_names(state, droplets, id)

        if next = get_in(body, ["links", "pages", "next"]) do
          nodes ++ get_nodes(state, next, token, id)
        else
          nodes
        end

      {_, error} ->
        Logger.error(state.topology, inspect(error))
        :error
    end
  end

  @doc """
  Returns the Droplet metadata top-level index, or specific metadata values.

  See https://docs.digitalocean.com/products/droplets/how-to/retrieve-droplet-metadata/
  """
  def get_metadata(type) do
    case :httpc.request(:get, {"#{@metadata_url}#{type}", []}, [], []) do
      {:ok, {{_, 200, _}, _, body}} -> body
      _ -> nil
    end
  end

  @doc """
  Returns a list of node names as described in `to_node_name/2`.

  Will not return node names for droplets that don't have a status of "active", or that match the
  provided ID of the current droplet.
  """
  def to_node_names(%State{} = state, droplets, id \\ nil) when is_list(droplets) do
    droplets
    |> Enum.filter(&(&1["id"] != id && &1["status"] == "active"))
    |> Enum.map(&to_node_name(state, &1))
    |> Enum.filter(& &1)
  end

  @doc """
  Converts a droplet map returned from the Digital Ocean API to a node name such as
  `:"foobar@127.0.0.1"`.

  Will optionally run a health check on the node to ensure it is ready to connect to the cluster.
  Returns nil if the health check fails, or if the droplet doesn't have an address for the defined
  network type and ip version.
  """
  def to_node_name(%State{} = state, droplet) when is_map(droplet) do
    basename = Keyword.get(state.config, :node_basename, Map.get(droplet, "name"))
    type = Keyword.get(state.config, :network, :private)
    ipv = if Keyword.get(state.config, :ipv6, false), do: "v6", else: "v4"
    health_check = Keyword.get(state.config, :health_check)

    network =
      droplet
      |> Map.get("networks", %{})
      |> Map.get(ipv, [])
      |> Enum.find(&(&1["type"] == Atom.to_string(type)))

    case network do
      %{"ip_address" => ip_address} ->
        if healthy?(ip_address, health_check) do
          :"#{basename}@#{ip_address}"
        else
          nil
        end

      _ ->
        Logger.warn(
          state.topology,
          "No #{type} ip#{ipv} network was found for droplet ##{droplet["id"]}"
        )

        nil
    end
  end

  @doc """
  Runs a health check for the provided IP address.
  """
  def healthy?(_ip, nil), do: true

  def healthy?(ip, {:tcp, opts}) do
    port = Keyword.fetch!(opts, :port)
    timeout = Keyword.get(opts, :timeout, 500)

    with {:ok, socket} <- :gen_tcp.connect(to_charlist(ip), port, [], timeout),
         :ok <- :gen_tcp.close(socket) do
      true
    else
      _ -> false
    end
  end
end
