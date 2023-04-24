<a href="https://github.com/jsonmaur/libcluster-droplet/actions/workflows/test.yml"><img alt="Test Status" src="https://img.shields.io/github/actions/workflow/status/jsonmaur/libcluster-droplet/test.yml?label=&style=for-the-badge&logo=github"></a> <a href="https://hexdocs.pm/libcluster_droplet/"><img alt="Hex Version" src="https://img.shields.io/hexpm/v/libcluster_droplet?style=for-the-badge&label=&logo=elixir" /></a>

A [libcluster](https://github.com/bitwalker/libcluster) strategy for Digital Ocean Droplets. This clustering strategy will connect all Droplets in your account to the cluster and can optionally be filtered by Droplet name or tag. It works by polling the Digital Ocean API, so a valid [access token](https://docs.digitalocean.com/reference/api/create-personal-access-token/) is required.

## Getting Started

```elixir
def deps do
  [
    {:libcluster_droplet, "~> 1.0"}
  ]
end
```

```elixir
config :libcluster,
  topologies: [
    example: [
      strategy: Cluster.Strategy.Droplet,
      config: [
        token: System.fetch_env!("DIGITALOCEAN_TOKEN"),
        health_check: {:tcp, port: 80},
        tag_name: "foobar"
      ]
    ]
  ]
```

### Config

| Key | Required | Description |
| :-- | :------: | :---------- |
| `:token` | ✓ | The Digital Ocean [access token](https://docs.digitalocean.com/reference/api/create-personal-access-token/) used for authenticating with the API. |
| `:network` |  | Whether to use private or public IP addresses in the node name. Defaults to `:private`. |
| `:ipv6` |  | Whether to use IPv6 addresses in the node name. Defaults to `false`. |
| `:tag_name` |  | Droplet tag to filter by when adding to the cluster. Cannot be combined with `:name`. |
| `:name` |  | Droplet name to filter by when adding to the cluster. Cannot be combined with `:tag_name`. |
| `:node_basename` |  | The base name of the nodes you want to connect to. Defaults to the Droplet name. |
| `:health_check` |  | Whether to run [health checks](#health-checks) against the nodes before adding them to the cluster. |
| `:polling_interval` |  | Number of milliseconds between polls to the API. Defaults to `5_000`. |

### Health Checks

When optionally defined in the config, nodes will not be added to the cluster until they are reported as healthy. `:health_check` should be a tuple with the first element being the health check type, and the second element being a keyword list of options. Currently the only supported type is `:tcp` with the following options:

* `:port` - The port to run the health check on. Value is required.
* `:timeout` - Number of milliseconds to wait before the node is considered unhealthy. Defaults to `500`.

## Releases

If you are using distributed Erlang and Mix releases, you'll need to set some environment variables in order for the clustering to work properly. This can be done in the `env.sh.eex` file generated when running `mix release.init`, or some other way of setting environment variables. Check out the [elixir docs](https://elixir-lang.org/getting-started/mix-otp/config-and-releases.html#operating-system-environment-configuration) and the [release docs](https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-vm-args-and-env-sh-env-bat) for more info.

You will need to set these three values:

  * `RELEASE_DISTRIBUTION` - Set to `name` so the cluster works across nodes
  * `RELEASE_NODE` - The full name of the current node (e.g. `app@127.0.0.1`)
  * `RELEASE_COOKIE` - A type of "password" that allows nodes to connect to the cluster

Here is an example `env.sh.eex` file that makes HTTP requests to the Droplet's metadata API to build the node name:

```sh
#!/bin/sh

# Set this to "public" if you have `network: :public` in your strategy config
NETWORK="private"

# Set this to "ipv6" if you have `ipv6: true` in your strategy config
IPV="ipv4"

# Droplet hostname is only needed if `:node_basename` is not defined in your strategy config.
# Otherwise, replace this curl command with the value defined in `:node_basename`.
HOSTNAME=$(curl -s http://169.254.169.254/metadata/v1/hostname)

IP_ADDRESS=$(curl -s http://169.254.169.254/metadata/v1/interfaces/$NETWORK/0/$IPV/address)

export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=$HOSTNAME@$IP_ADDRESS
export RELEASE_COOKIE=some-secret-value
```

## Firewalls

Erlang's [epmd](https://www.erlang.org/doc/man/epmd.html) communicates on port 4369, as well as a random port for each node in the cluster. If your Droplet has a firewall, you will need to add a rule to allow all incoming TCP traffic from other Droplets in the cluster. This can be done dynamically using a tag if you're using a [Cloud Firewall](https://docs.digitalocean.com/products/networking/firewalls/).

If you want to tighten security even further and only allow specific ports, you can customize the ports used by epmd by adding this to your `env.sh.eex` file:

```sh
# This port will be used by epmd instead of port 4369.
ERL_EPMD_PORT=9000

# This port will be used by epmd instead of a random port for each node.
# Note that if you set this value, you can only run one app instance in each Droplet.
ERL_NODE_PORT=9001

case $RELEASE_COMMAND in
  start*|daemon*)
    export ELIXIR_ERL_OPTIONS="-kernel inet_dist_listen_min $ERL_NODE_PORT inet_dist_listen_max $ERL_NODE_PORT"
    ;;
  *)
    ;;
esac
```
