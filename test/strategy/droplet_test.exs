defmodule Cluster.Strategy.DropletTest do
  use ExUnit.Case, async: true
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc

  import ExUnit.CaptureLog

  alias Cluster.Strategy.Droplet
  alias Cluster.Strategy.State

  setup do
    ExVCR.Config.cassette_library_dir("test/fixtures/vcr_cassettes", "test/fixtures/custom_cassettes")

    droplets = [
      %{
        "id" => 1,
        "name" => "foobar",
        "status" => "active",
        "networks" => %{
          "v4" => [
            %{"type" => "public", "ip_address" => "1.1.1.1"},
            %{"type" => "private", "ip_address" => "127.0.0.1"}
          ],
          "v6" => [
            %{"type" => "public", "ip_address" => "2606:4700:4700::1111"},
            %{"type" => "private", "ip_address" => "::1"}
          ]
        }
      },
      %{
        "id" => 2,
        "name" => "foobar",
        "status" => "off",
        "networks" => %{
          "v4" => [
            %{"type" => "public", "ip_address" => "2.2.2.2"},
            %{"type" => "private", "ip_address" => "127.0.0.2"}
          ]
        }
      },
      %{
        "id" => 3,
        "name" => "foobar",
        "status" => "active",
        "networks" => %{
          "v4" => [
            %{"type" => "public", "ip_address" => "3.3.3.3"},
            %{"type" => "private", "ip_address" => "127.0.0.3"}
          ]
        }
      }
    ]

    %{droplets: droplets}
  end

  describe "start_link/1" do
    setup do
      state = %Cluster.Strategy.State{
        topology: Droplet,
        list_nodes: {__MODULE__, :list_nodes, [[]]},
        connect: {__MODULE__, :connect, [self()]},
        disconnect: {__MODULE__, :disconnect, [self()]},
        config: [
          polling_interval: 100,
          token: "dop_v1_abc123",
          tag_name: "foobar"
        ]
      }

      %{state: state}
    end

    test "should add new nodes", ctx do
      use_cassette "droplets", custom: true do
        capture_log(fn -> Droplet.start_link([ctx.state]) end)
      end

      assert_receive {:connect, :"example@10.128.192.124"}, 100
    end

    test "should remove nodes", ctx do
      use_cassette "droplets", custom: true do
        nodes = [:"example@1.2.3.4", :"example@10.128.192.124"]
        state = Map.put(ctx.state, :meta, MapSet.new(nodes))
        state = Map.put(state, :list_nodes, {__MODULE__, :list_nodes, [nodes]})

        capture_log(fn -> Droplet.start_link([state]) end)
      end

      assert_receive {:disconnect, :"example@1.2.3.4"}, 100
      refute_receive {:connect, :"example@10.128.192.124"}, 100
    end

    test "should not do anything if nodes have not changed", ctx do
      use_cassette "droplets", custom: true do
        nodes = [:"example@10.128.192.124"]
        state = Map.put(ctx.state, :meta, MapSet.new(nodes))
        state = Map.put(state, :list_nodes, {__MODULE__, :list_nodes, [nodes]})

        capture_log(fn -> Droplet.start_link([state]) end)
      end

      refute_receive {:connect, _}, 100
      refute_receive {:disconnect, _}, 100
    end

    test "should not make any changes if API returns an error", ctx do
      use_cassette "droplets", custom: true do
        nodes = [:"example@1.2.3.4"]
        state = Map.put(ctx.state, :meta, MapSet.new(nodes))
        state = Map.put(state, :list_nodes, {__MODULE__, :list_nodes, [nodes]})

        config = Keyword.put(state.config, :tag_name, "error")
        state = Map.put(state, :config, config)

        capture_log(fn -> Droplet.start_link([state]) end)
      end

      refute_receive {:connect, _}, 100
      refute_receive {:disconnect, _}, 100
    end

    test "should raise if both name and tag name are defined", ctx do
      use_cassette "droplets", custom: true do
        Process.flag(:trap_exit, true)

        config = Keyword.put(ctx.state.config, :name, "foobar")
        state = Map.put(ctx.state, :config, config)

        assert {:error, _} = Droplet.start_link([state])
      end
    end
  end

  describe "get_nodes/4" do
    test "should return a list of all nodes" do
      auth = fn _, k, _ -> Enum.member?(k[:headers], {"Authorization", "Bearer dop_v1_abc123"}) end

      use_cassette "droplets", custom: true, match_requests_on: [:query], custom_matchers: [auth] do
        assert Droplet.get_nodes(%State{}, "https://api.digitalocean.com/v2/droplets", "dop_v1_abc123", nil) == [
                 :"example@10.128.192.124",
                 :"example@10.128.192.138"
               ]
      end
    end

    test "should not return self in list of nodes" do
      use_cassette "droplets", custom: true, match_requests_on: [:query] do
        assert Droplet.get_nodes(%State{}, "https://api.digitalocean.com/v2/droplets", "dop_v1_abc123", "3164444") == [
                 :"example@10.128.192.138"
               ]
      end
    end

    test "should return api error" do
      use_cassette "droplets", custom: true, match_requests_on: [:query] do
        assert capture_log(fn ->
                 assert Droplet.get_nodes(%State{}, "https://api.digitalocean.com/v2/droplets?page=3", nil, nil) ==
                          :error
               end) =~ "Bad Request"
      end
    end
  end

  describe "get_metadata/1" do
    test "should return the droplet id" do
      use_cassette "droplets", custom: true do
        assert Droplet.get_metadata("id") == "123456789"
      end
    end

    test "should return nil on error" do
      use_cassette "droplets", custom: true do
        refute Droplet.get_metadata("error")
      end
    end
  end

  describe "to_node_names/3" do
    test "should return list of names", ctx do
      assert Droplet.to_node_names(%State{}, ctx.droplets) == [:"foobar@127.0.0.1", :"foobar@127.0.0.3"]
    end

    test "should return list of names without self", ctx do
      assert Droplet.to_node_names(%State{}, ctx.droplets, 1) == [:"foobar@127.0.0.3"]
    end

    test "should not return name for droplet with no ip address", ctx do
      droplets = ctx.droplets ++ [%{"id" => 4, "name" => "foobar", "status" => "active", "networks" => %{}}]

      assert capture_log(fn ->
               assert Droplet.to_node_names(%State{}, droplets) == [:"foobar@127.0.0.1", :"foobar@127.0.0.3"]
             end) =~ "No private ipv4 network was found for droplet #4"
    end
  end

  describe "to_node_name/2" do
    setup ctx do
      %{droplet: Enum.at(ctx.droplets, 0)}
    end

    test "should return name from ipv4 private address", ctx do
      assert Droplet.to_node_name(%State{}, ctx.droplet) == :"foobar@127.0.0.1"
    end

    test "should return name from ipv4 public address", ctx do
      assert Droplet.to_node_name(%State{config: [network: :public]}, ctx.droplet) == :"foobar@1.1.1.1"
    end

    test "should return name from ipv6 private address", ctx do
      assert Droplet.to_node_name(%State{config: [ipv6: true]}, ctx.droplet) == :"foobar@::1"
    end

    test "should return name from ipv6 public address", ctx do
      assert Droplet.to_node_name(%State{config: [ipv6: true, network: :public]}, ctx.droplet) ==
               :"foobar@2606:4700:4700::1111"
    end

    test "should return name with a base name", ctx do
      assert Droplet.to_node_name(%State{config: [node_basename: "yo"]}, ctx.droplet) == :"yo@127.0.0.1"
    end

    test "should not return name for droplet with no ip address" do
      assert capture_log(fn ->
               refute Droplet.to_node_name(%State{}, %{"id" => 1, "networks" => %{}})
             end) =~ "No private ipv4 network was found for droplet #1"
    end

    test "should return name for droplet with passing health check" do
      state = %State{config: [node_basename: "yo", health_check: {:tcp, port: 80}]}
      droplet = %{"networks" => %{"v4" => [%{"type" => "private", "ip_address" => "1.1.1.1"}]}}

      assert Droplet.to_node_name(state, droplet) == :"yo@1.1.1.1"
    end

    test "should not return name for droplet with failing health check" do
      state = %State{config: [node_basename: "yo", health_check: {:tcp, port: 80, timeout: 100}]}
      droplet = %{"networks" => %{"v4" => [%{"type" => "private", "ip_address" => "2.2.2.2"}]}}

      refute Droplet.to_node_name(state, droplet)
    end
  end

  describe "healthy?/2" do
    test "should return true if no health check is provided" do
      assert Droplet.healthy?("localhost", nil)
    end

    test "should return true if health check passes" do
      assert Droplet.healthy?("hex.pm", {:tcp, port: 80})
    end

    test "should return false if health check times out" do
      refute Droplet.healthy?("hex.pm", {:tcp, port: 80, timeout: 1})
    end

    test "should return false if health check fails" do
      refute Droplet.healthy?("hex.pm", {:tcp, port: 9999, timeout: 100})
    end
  end

  def list_nodes(nodes), do: nodes

  def connect(caller, result \\ true, node) do
    send(caller, {:connect, node})
    result
  end

  def disconnect(caller, result \\ true, node) do
    send(caller, {:disconnect, node})
    result
  end
end
