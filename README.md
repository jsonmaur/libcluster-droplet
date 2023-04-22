# Libcluster Droplet Strategy

<a href="https://github.com/jsonmaur/libcluster_droplet/actions/workflows/test.yml">
  <img alt="Test Status" src="https://img.shields.io/github/actions/workflow/status/jsonmaur/libcluster_droplet/test.yml?label=test&style=plastic">
</a>

<a href="https://hexdocs.pm/libcluster_droplet">
  <img alt="Hex Version" src="https://img.shields.io/hexpm/v/libcluster_droplet?style=plastic" />
</a>

A Digital Ocean Droplet clustering strategy for [libcluster](https://github.com/bitwalker/libcluster). This strategy will connect all Droplets in your account to the cluster and can optionally be filtered by Droplet name or tag. It works by polling the Digital Ocean API, so a valid [access token](https://docs.digitalocean.com/reference/api/create-personal-access-token/) is required.

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
        tag_name: "foobar"
      ]
    ]
  ]
```

## Config

| Key | Required | Description |
| --- | -------- | ----------- |
| `:token` | ✓ | The Digital Ocean [access token](https://docs.digitalocean.com/reference/api/create-personal-access-token/) used for authenticating with the API. |
| `:network` |  | Whether to use private or public IP addresses in the node name. Defaults to `:public`. |
| `:ipv6` |  | Whether to use IPv6 addresses in the node name. Defaults to `false`. |
| `:tag_name` |  | Droplet tag to filter by when adding to the cluster. Cannot be combined with `:name`. |
| `:name` |  | Droplet name to filter by when adding to the cluster. Cannot be combined with `:tag_name`. |
| `:node_basename` |  | The base name of the nodes you want to connect to. Defaults to the Droplet name. |
| `:polling_interval` |  | Number of milliseconds between polls to the API. Defaults to `5_000`. |
